import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';
import '../../core/telemetry/mem_error_reporter.dart';

/// Page size for the search lane. Deliberately **not** the timeline's 40 — the
/// two lanes have different semantics and must not share tuning either.
const int kNotesSearchLimit = 20;

/// Below this the query is not sent at all (§5.1).
const int kNotesSearchMinChars = 2;

/// Keystroke debounce before a request goes out (§5.1).
const Duration kNotesSearchDebounce = Duration(milliseconds: 300);

/// The Notes search lane, isolated from the timeline (§5.1).
///
/// **Why this is its own object.** `searchNotes` is a *second pagination lane
/// with foreign semantics*: the timeline pages an opaque `next_page` cursor,
/// search pages a numeric `offset`. Mixing them is how a search response ends
/// up overwriting the timeline's cursor and silently truncating the list. So
/// the isolation is structural, not a convention:
///
/// * This class holds **all** search state. It has no reference to the page's
///   `_items`, `_nextPage`, or `_filterCollectionId`, and it cannot write to
///   them — the page reads this object, never the other way round.
/// * Every request carries a monotonically increasing **sequence number**; a
///   response whose sequence is no longer the latest is dropped on the floor,
///   so a slow response for `mem` can never land after a fast one for `memo`.
/// * Failures report under the **new** `'notes_search'` telemetry context.
///   `'notes_load'` belongs to the timeline and is consumed downstream; this
///   is additive and does not disturb it.
///
/// The client is injected as a **function**, never a snapshot: `MemApiClient`
/// is constructed fresh per operation from the current `memApiKey`, so a key
/// change applies immediately.
class NotesSearchController extends ChangeNotifier {
  NotesSearchController({required this.resolveClient});

  /// Returns a client built from the *current* key, or null when there is no
  /// key. Called once per request — never cached.
  final MemApiClient? Function() resolveClient;

  bool _active = false;
  String _query = '';
  List<MemNoteListItem> _results = const <MemNoteListItem>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _offset = 0;

  /// Monotonic request counter. Bumped on every request, and on every path
  /// that invalidates one (query change below the minimum, exit, dispose), so
  /// a stale response has nothing to land on.
  int _seq = 0;

  Timer? _debounce;
  bool _disposed = false;

  /// True while the page is in search mode: the chip strip hides and the
  /// results replace the timeline. The timeline itself is untouched underneath.
  bool get active => _active;

  /// The trimmed query as last typed (not necessarily the one on screen — the
  /// debounce may not have fired yet).
  String get query => _query;

  /// Results so far, oldest page first. Immutable: the page renders it, and
  /// only [_run] ever replaces it.
  List<MemNoteListItem> get results => _results;

  /// A first page (or a retry) is in flight, or the debounce is still running.
  /// The page renders skeleton rows for this.
  bool get loading => _loading;

  /// A `loadMore` append is in flight. The page renders three tail rows.
  bool get loadingMore => _loadingMore;

  /// The last page came back full, so there is probably another one.
  bool get hasMore => _hasMore;

  /// Raw error object, formatted only at the point of display by
  /// `memErrorText` — a raw exception string never reaches a widget.
  Object? get error => _error;

  /// The query is long enough to have been sent.
  bool get hasQuery => _query.length >= kNotesSearchMinChars;

  /// Enter search mode. Idempotent; does not fetch anything on its own.
  void enter() {
    if (_active) return;
    _active = true;
    _notify();
  }

  /// Leave search mode and drop every scrap of search state.
  ///
  /// The timeline is deliberately **not** touched or refetched — exiting search
  /// restores it exactly as it was (§5.1), which only works because this object
  /// never owned any of it.
  void exit() {
    _debounce?.cancel();
    _debounce = null;
    // Anything in flight belongs to a mode we are no longer in.
    _seq++;
    _active = false;
    _resetQueryState();
    _notify();
  }

  /// Wired to the pill's `onChanged`. Debounces, enforces the 2-character
  /// minimum, and shows the typing state immediately so the wait is legible.
  void onQueryChanged(String raw) {
    final String next = raw.trim();
    _debounce?.cancel();
    _debounce = null;
    if (next == _query) return;
    _query = next;

    if (next.length < kNotesSearchMinChars) {
      // Too short to send: invalidate anything in flight and go quiet.
      _seq++;
      _resetQueryState(keepQuery: true);
      _notify();
      return;
    }

    // The skeleton appears on the keystroke, not 300 ms later.
    _loading = true;
    _error = null;
    _notify();
    _debounce = Timer(kNotesSearchDebounce, () {
      _debounce = null;
      unawaited(_run(reset: true));
    });
  }

  /// Re-run the current query from offset 0. Used by the error state's retry
  /// and by pull-to-refresh while in search mode.
  Future<void> retry() async {
    if (!hasQuery) return;
    _debounce?.cancel();
    _debounce = null;
    await _run(reset: true);
  }

  /// Next page, on the same 400 dp-from-end trigger the timeline uses.
  ///
  /// Guarded so it fires **once per page**: [_loadingMore] is set before the
  /// await, and [_hasMore] goes false as soon as a short page comes back.
  Future<void> loadMore() async {
    if (!_active || !hasQuery) return;
    if (_loading || _loadingMore || !_hasMore) return;
    await _run(reset: false);
  }

  Future<void> _run({required bool reset}) async {
    final String query = _query;
    if (query.length < kNotesSearchMinChars) return;

    final MemApiClient? client = resolveClient();
    if (client == null) {
      // No key. The page's `!hasMemRest` branch owns that story; search just
      // has nothing to say.
      _loading = false;
      _loadingMore = false;
      _results = const <MemNoteListItem>[];
      _hasMore = false;
      _notify();
      return;
    }

    final int seq = ++_seq;
    final int offset = reset ? 0 : _offset;
    if (reset) {
      _loading = true;
      _error = null;
    } else {
      _loadingMore = true;
    }
    _notify();

    try {
      // NOTE: `snapshotId` is not threaded. `MemApiClient.searchNotes` returns
      // `List<MemNoteListItem>` and discards the response envelope, so the
      // `snapshot_id` the API hands back for consistent paging never reaches
      // this layer. Offset paging alone is correct, just not snapshot-pinned:
      // a note created mid-scroll can shift the window by one. Fixing it needs
      // a raw search on the client (see the PR's requests list), which is
      // `lib/core/**` and not this package's to edit.
      final List<MemNoteListItem> page = await client.searchNotes(
        query: query,
        limit: kNotesSearchLimit,
        offset: offset,
        includeContent: false,
      );
      // Stale-response cancellation. Not a `mounted` check — this object can
      // outlive a request that no longer represents what the user typed.
      if (seq != _seq) return;
      _results = reset
          ? List<MemNoteListItem>.unmodifiable(page)
          : List<MemNoteListItem>.unmodifiable(
              <MemNoteListItem>[..._results, ...page],
            );
      _offset = offset + page.length;
      _hasMore = page.length >= kNotesSearchLimit;
      _loading = false;
      _loadingMore = false;
      _error = null;
      _notify();
    } catch (e, st) {
      // Additive context: the timeline's consumed 'notes_load' string is
      // untouched.
      MemErrorReporter.report(
        message: e.toString(),
        stack: st.toString(),
        context: 'notes_search',
      );
      if (seq != _seq) return;
      _error = e;
      _loading = false;
      _loadingMore = false;
      if (reset) {
        _results = const <MemNoteListItem>[];
        _hasMore = false;
        _offset = 0;
      }
      _notify();
    }
  }

  /// Everything except [_active]. [keepQuery] holds the typed text while the
  /// user is still below the 2-character minimum.
  void _resetQueryState({bool keepQuery = false}) {
    if (!keepQuery) _query = '';
    _results = const <MemNoteListItem>[];
    _error = null;
    _loading = false;
    _loadingMore = false;
    _hasMore = false;
    _offset = 0;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    // Any in-flight response is now stale by construction.
    _seq++;
    super.dispose();
  }
}
