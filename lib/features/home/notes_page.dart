import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';
import '../../core/telemetry/mem_error_reporter.dart';
import '../../theme/mem_metrics.dart';
import '../../ui/app_list_section.dart';
import '../../ui/async_page_mixin.dart';
import '../../ui/chip_strip.dart';
import '../../ui/collection_tag.dart';
import '../../ui/date_labels.dart';
import '../../ui/empty_state.dart';
import '../../ui/error_state.dart';
import '../../ui/inline_spinner.dart';
import '../../ui/search_pill.dart';
import '../../ui/section_header.dart';
import '../../ui/skeleton.dart';
import '../../widgets/settings_launcher.dart';
import '../note/note_detail_page.dart';
import '../settings/settings_page.dart';
import 'collections_manage_page.dart';
import 'notes_search_controller.dart';

/// Fire the next page this far from the end of the scroll extent (§5.3).
const double _kInfiniteScrollTrigger = 400;

/// All notes in a scannable timeline, with a live search lane, a collection
/// filter, and entry to collection management.
///
/// **Two lanes, one screen.** The timeline pages an opaque `next_page` cursor;
/// search pages a numeric offset. They share this widget's scroll view and
/// nothing else — search state lives entirely in [NotesSearchController] and
/// can never write into `_items`, `_nextPage`, or `_filterCollectionId`.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> with AsyncPageMixin<NotesPage> {
  // ---------------------------------------------------------------------
  // Timeline lane — the data layer. Semantics here are contract-frozen.
  // ---------------------------------------------------------------------
  final List<MemNoteListItem> _items = [];
  List<MemCollectionItem> _collections = [];
  String? _nextPage;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadingCols = false;
  Object? _error;
  Object? _collectionsError;
  String? _filterCollectionId;

  /// The `!alreadyLoaded` half of the idempotent lazy-load guard (§4.2).
  ///
  /// This must be an explicit flag, never `_items.isNotEmpty`: a completed
  /// timeline load that legitimately returned zero rows (empty account, or a
  /// filter that matches nothing) is indistinguishable from "never loaded" by
  /// row count alone. Because [_tryInitialLoad] is reachable from every
  /// `AppState` notification — the page depends on `AppScope`, so any
  /// `notifyListeners` fires both [_onAppStateChanged] and
  /// [didChangeDependencies] — a row-count proxy re-fetches on every theme
  /// toggle or settings write and swaps the empty state for a skeleton each
  /// time. Set only on a successful refresh; deliberately *not* set on error,
  /// so a failed first load stays retryable through the same paths.
  bool _didInitialLoad = false;

  /// Monotonic request counter for the timeline lane.
  ///
  /// Infinite scroll made an old race reachable: a `notesListRevision` bump can
  /// land a refresh while an append is still in flight, and the append's
  /// `addAll` would then paste a stale page onto a freshly cleared list. Every
  /// request takes a sequence number and a response that is no longer the
  /// latest is dropped — the newer request still owns (and clears) both
  /// loading flags, so nothing can get stuck.
  int _timelineSeq = 0;

  /// **View-layer only** stale-content retention (§5.3).
  ///
  /// The data layer still clears `_items` and the cursor before every refresh,
  /// exactly as the contract requires. This immutable copy is what the sliver
  /// renders in the gap, so a refresh never blanks the list. Its rows are
  /// **non-tappable** — a stale row could open a note the server just deleted —
  /// and it is dropped on success *and* on error, so a dimmed list can never
  /// persist indefinitely.
  List<MemNoteListItem>? _displaySnapshot;

  // ---------------------------------------------------------------------
  // Search lane — fully isolated. See notes_search_controller.dart.
  // ---------------------------------------------------------------------
  late final NotesSearchController _search;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Timeline scroll offset captured on entering search, restored on exit so
  /// the timeline comes back "exactly as it was" (§5.1).
  double _timelineOffset = 0;

  final ScrollController _scrollController = ScrollController();

  AppState? _app;
  VoidCallback? _appListener;

  MemApiClient? _client(BuildContext context) {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  @override
  void initState() {
    super.initState();
    // The client resolver is a *function*, not a snapshot: every search request
    // builds a fresh client from the current key.
    _search = NotesSearchController(resolveClient: () => _client(context))
      ..addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryInitialLoad());
  }

  void _onNotesRevision() {
    if (!mounted) return;
    _loadNotes(refresh: true);
    _loadCollections();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    _tryInitialLoad();
    setState(() {});
  }

  void _onSearchChanged() => setStateIfMounted(() {});

  /// Consume-once-and-clear, mirroring `shellTabRequest` (§5.4). Clearing the
  /// channel re-enters this listener with a null value, which is the base case.
  void _onNotesFilterRequest() {
    if (!mounted) return;
    final app = _app;
    if (app == null) return;
    final id = app.notesFilterRequest.value;
    if (id == null) return;
    scheduleMicrotask(() {
      if (app.notesFilterRequest.value == id) {
        app.notesFilterRequest.value = null;
      }
    });
    _setFilter(id);
  }

  void _tryInitialLoad() {
    final app = _app;
    if (app == null || !app.isHydrated || !app.hasMemRest) return;
    if (_loading || _loadingMore) return;
    if (_didInitialLoad && _error == null) return;
    unawaited(_loadNotes(refresh: true));
    unawaited(_loadCollections());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (!identical(_app, app)) {
      _app?.notesListRevision.removeListener(_onNotesRevision);
      _app?.notesFilterRequest.removeListener(_onNotesFilterRequest);
      if (_appListener != null) {
        _app?.removeListener(_appListener!);
      }
      _app = app;
      _appListener = _onAppStateChanged;
      _app!.addListener(_appListener!);
      _app!.notesListRevision.addListener(_onNotesRevision);
      _app!.notesFilterRequest.addListener(_onNotesFilterRequest);
      // A filter may already be pending from before we attached. Deferred to
      // post-frame because applying it calls setState.
      postFrame(_onNotesFilterRequest);
    }
    _tryInitialLoad();
  }

  @override
  void dispose() {
    _app?.notesListRevision.removeListener(_onNotesRevision);
    _app?.notesFilterRequest.removeListener(_onNotesFilterRequest);
    if (_appListener != null) {
      _app?.removeListener(_appListener!);
    }
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------

  Future<void> _loadCollections() async {
    final c = _client(context);
    if (c == null) return;
    setState(() => _loadingCols = true);
    try {
      final list = await c.listCollections(limit: 100);
      if (!mounted) return;
      setState(() {
        _collections = list;
        _loadingCols = false;
        _collectionsError = null;
        if (_filterCollectionId != null &&
            !_collections.any((x) => x.id == _filterCollectionId)) {
          _filterCollectionId = null;
        }
      });
    } catch (e) {
      // Non-fatal by contract — the timeline works without collection titles.
      // But it must not be *silent* (`#1`): the strip above the timeline says
      // so and offers a retry.
      if (mounted) {
        setState(() {
          _loadingCols = false;
          _collectionsError = e;
        });
      }
    }
  }

  Future<void> _loadNotes({bool refresh = false}) async {
    final app = AppScope.of(context);
    final c = _client(context);
    if (c == null) {
      if (!app.isHydrated) {
        setState(() {
          _loading = true;
          _error = null;
        });
        return;
      }
      // No key. The `!hasMemRest` branch of the tree owns this state and
      // renders the "Connect your Mem account" empty state, so there is no
      // error to surface here.
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _error = null;
      if (refresh) {
        _loading = true;
        // Snapshot and clear in the SAME setState — there is no frame in which
        // the rows are gone and the snapshot is not yet standing in for them.
        _displaySnapshot = _items.isEmpty
            ? null
            : List<MemNoteListItem>.unmodifiable(_items);
        _items.clear();
        _nextPage = null;
      } else {
        _loadingMore = true;
      }
    });
    final int seq = ++_timelineSeq;
    try {
      final raw = await c.rawListNotes(
        limit: 40,
        page: refresh ? null : _nextPage,
        includeContent: false,
        collectionId: _filterCollectionId,
      );
      final results = raw['results'] as List<dynamic>? ?? [];
      final parsed = results
          .map(
            (e) => MemNoteListItem(
              id: e['id'] as String,
              title: e['title'] as String? ?? '',
              snippet: e['snippet'] as String?,
              content: null,
              createdAt: DateTime.parse(e['created_at'] as String),
              updatedAt: DateTime.parse(e['updated_at'] as String),
              collectionIds: (e['collection_ids'] as List<dynamic>? ?? [])
                  .map((x) => x as String)
                  .toList(),
            ),
          )
          .toList();
      if (!mounted) return;
      // A newer request already owns the list; this page is stale.
      if (seq != _timelineSeq) return;
      setState(() {
        if (refresh) {
          _items
            ..clear()
            ..addAll(parsed);
        } else {
          _items.addAll(parsed);
        }
        final n = raw['next_page'];
        _nextPage = n is String ? n : null;
        _loading = false;
        _loadingMore = false;
        _displaySnapshot = null;
        if (refresh) _didInitialLoad = true;
      });
    } catch (e, st) {
      MemErrorReporter.report(
        message: e.toString(),
        stack: st.toString(),
        context: 'notes_load',
      );
      if (!mounted) return;
      // Reported either way — but a superseded failure must not blank a list a
      // newer request is about to fill.
      if (seq != _timelineSeq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        // Dropped on error too: a stale list with no way forward is worse than
        // an error with a retry.
        _displaySnapshot = null;
        _error = e;
      });
    }
  }

  /// The infinite-scroll append. Fires once per page: `_loadingMore` is set
  /// synchronously inside `_loadNotes`'s first `setState`, and the cursor is
  /// only replaced once the response lands.
  void _maybeLoadMorePage() {
    if (_loading || _loadingMore) return;
    if (_nextPage == null) return;
    unawaited(_loadNotes());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - _kInfiniteScrollTrigger) return;
    if (_search.active) {
      unawaited(_search.loadMore());
      return;
    }
    _maybeLoadMorePage();
  }

  Future<void> _onRefresh() async {
    if (_search.active) {
      await _search.retry();
      return;
    }
    await _loadCollections();
    await _loadNotes(refresh: true);
  }

  // ---------------------------------------------------------------------
  // Navigation and filtering
  // ---------------------------------------------------------------------

  Map<String, List<MemNoteListItem>> _group(List<MemNoteListItem> source) {
    final map = <String, List<MemNoteListItem>>{};
    for (final n in source) {
      // The grouping KEY is contract-frozen. `memDayLabel` is a pure
      // presentation map over it and never changes grouping or ordering;
      // groups render in the order their keys first appear.
      final key = DateFormat.yMMMEd().format(n.updatedAt.toLocal());
      map.putIfAbsent(key, () => []).add(n);
    }
    return map;
  }

  void _setFilter(String? collectionId) {
    if (_search.active) {
      // A new filter means a new list; restoring the pre-search offset would
      // land the user in the middle of rows they have never seen.
      _timelineOffset = 0;
      _exitSearch();
    }
    setState(() => _filterCollectionId = collectionId);
    unawaited(_loadNotes(refresh: true));
  }

  Future<void> _openManageCollections() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const CollectionsManagePage(),
      ),
    );
    if (!mounted) return;
    await _loadCollections();
    await _loadNotes(refresh: true);
  }

  void _openNote(String noteId) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NoteDetailPage(noteId: noteId),
      ),
    );
  }

  void _openAccountSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsPage(focusSection: SettingsSection.account),
      ),
    );
  }

  /// Client-side join of `collectionIds` against the already-fetched list.
  /// A missing title falls back to the raw id rather than hiding the tag.
  String _collectionTitle(String id) {
    for (final c in _collections) {
      if (c.id == id) return c.title;
    }
    return id;
  }

  // ---------------------------------------------------------------------
  // Search mode
  // ---------------------------------------------------------------------

  void _enterSearch() {
    if (_search.active) return;
    _timelineOffset =
        _scrollController.hasClients ? _scrollController.offset : 0;
    _search.enter();
    // The pill lives in the scroll body, so "focus the search field" means
    // bringing it back into view first.
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: MemMotion.standard,
          curve: MemMotion.emphasized,
        ),
      );
    }
    // The TextField only exists after this rebuild.
    postFrame(_searchFocus.requestFocus);
  }

  void _clearSearchQuery() {
    _searchCtrl.clear();
    _search.onQueryChanged('');
    _searchFocus.requestFocus();
  }

  void _exitSearch() {
    _searchFocus.unfocus();
    _searchCtrl.clear();
    // Drops all search state and touches nothing in the timeline — no refetch.
    _search.exit();
    postFrame(() {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(
        _timelineOffset.clamp(0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: <Widget>[
          if (app.hasMemRest && !_search.active)
            IconButton(
              tooltip: 'Search notes',
              icon: const Icon(Icons.search),
              onPressed: _enterSearch,
            ),
          ...settingsIconActions(context),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            if (app.hasMemRest)
              SliverToBoxAdapter(child: _buildSearchPill(context)),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: MemMotion.micro,
                switchInCurve: MemMotion.emphasized,
                switchOutCurve: MemMotion.emphasized,
                child: _buildStripSlot(context, app),
              ),
            ),
            // Every body branch appends its own bottom clearance — a
            // `SliverFillRemaining` cannot see a sliver below it, so the inset
            // has to live *inside* it or the CTA hides under the nav bar.
            ..._bodySlivers(context, app),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPill(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MemInsets.pageH,
        MemSpace.x2,
        MemInsets.pageH,
        0,
      ),
      child: SearchPill(
        hint: 'Search notes',
        controller: _searchCtrl,
        focusNode: _searchFocus,
        active: _search.active,
        onTap: _enterSearch,
        onChanged: _search.onQueryChanged,
        onClear: _clearSearchQuery,
        onCancel: _exitSearch,
      ),
    );
  }

  /// The band under the pill: the filter chips in timeline mode, the results
  /// count in search mode. Bounded height, so the [AnimatedSwitcher] cross-fade
  /// stays inside the per-frame budget — the *list* is never faded.
  Widget _buildStripSlot(BuildContext context, AppState app) {
    // The filter bar must not render without a Mem key.
    if (!app.hasMemRest) {
      return const SizedBox.shrink(key: ValueKey<String>('no-strip'));
    }
    if (_search.active) {
      if (!_search.hasQuery || _search.loading || _search.error != null) {
        return const SizedBox.shrink(key: ValueKey<String>('search-quiet'));
      }
      return _ResultsStrip(
        key: const ValueKey<String>('results'),
        count: _search.results.length,
        onClear: _exitSearch,
      );
    }
    return Column(
      key: const ValueKey<String>('filters'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ChipStrip(
          leadingPinned: ChoiceChip(
            label: const Text('All'),
            selected: _filterCollectionId == null,
            onSelected: (_) => _setFilter(null),
          ),
          trailingAction: IconButton(
            tooltip: 'Manage collections',
            icon: const Icon(Icons.tune),
            onPressed: _openManageCollections,
          ),
          children: <Widget>[
            for (final c in _collections)
              CollectionTag(
                collectionId: c.id,
                title: c.title,
                variant: CollectionTagVariant.chip,
                count: c.noteCount,
                selected: _filterCollectionId == c.id,
                onTap: () => _setFilter(c.id),
              ),
          ],
        ),
        if (_collectionsError != null)
          _CollectionsUnavailableStrip(
            busy: _loadingCols,
            onRetry: () => unawaited(_loadCollections()),
          ),
      ],
    );
  }

  /// Bottom clearance for the shell's NavigationBar. Notes is the only screen
  /// whose sole bottom chrome is the nav bar, so 104 is the whole budget.
  static const Widget _bottomInset = SliverToBoxAdapter(
    child: SizedBox(height: MemInsets.listBottomForNav),
  );

  /// A centred, full-height state (empty / error) that still clears the nav bar
  /// and still pulls to refresh.
  Widget _fill(Widget child) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: MemInsets.listBottomForNav),
        child: child,
      ),
    );
  }

  List<Widget> _bodySlivers(BuildContext context, AppState app) {
    // Pre-hydration: normal chrome plus skeletons, never a naked spinner.
    if (!app.isHydrated) {
      return const [
        SliverToBoxAdapter(child: SkeletonList(rowCount: 8)),
        _bottomInset,
      ];
    }
    if (!app.hasMemRest) {
      return [
        _fill(
          EmptyState(
            firstRun: true,
            icon: Icons.vpn_key_outlined,
            headline: 'Connect your Mem account',
            body: 'Add your Mem API key to read and edit your notes.',
            ctaLabel: 'Open Settings',
            onCta: _openAccountSettings,
          ),
        ),
      ];
    }
    if (_search.active) return _searchSlivers(context);
    return _timelineSlivers(context, app);
  }

  List<Widget> _timelineSlivers(BuildContext context, AppState app) {
    final Object? error = _error;
    if (error != null) {
      return [
        _fill(
          ErrorState(error: error, onRetry: () => unawaited(_onRefresh())),
        ),
      ];
    }

    if (_items.isEmpty) {
      final List<MemNoteListItem>? snapshot = _displaySnapshot;
      if (snapshot != null) {
        // Stale retention: the rows the refresh just cleared, rendered at
        // reduced emphasis and NOT tappable.
        return [
          ..._noteGroupSlivers(snapshot, tappable: false),
          _bottomInset,
        ];
      }
      if (_loading) {
        return const [
          SliverToBoxAdapter(child: SkeletonList(rowCount: 8)),
          _bottomInset,
        ];
      }
      final bool filtered = _filterCollectionId != null;
      return [
        _fill(
          EmptyState(
            icon: filtered
                ? Icons.filter_alt_off_outlined
                : Icons.note_add_outlined,
            headline:
                filtered ? 'Nothing in this collection' : 'Capture your first note',
            body: filtered
                ? 'No notes carry this collection yet.'
                : 'Notes you capture on this device show up here.',
            ctaLabel: filtered ? 'Show all notes' : 'Capture a note',
            onCta: filtered ? () => _setFilter(null) : () => app.goToShellTab(1),
          ),
        ),
      ];
    }

    return [
      ..._noteGroupSlivers(_items, tappable: true),
      if (_loadingMore) _tailSkeleton(),
      _bottomInset,
    ];
  }

  List<Widget> _searchSlivers(BuildContext context) {
    final Object? error = _search.error;
    if (error != null) {
      return [
        _fill(
          ErrorState(
            error: error,
            title: "Couldn't search",
            onRetry: () => unawaited(_search.retry()),
          ),
        ),
      ];
    }
    if (!_search.hasQuery) {
      return [
        _fill(
          const EmptyState(
            icon: Icons.search,
            headline: 'Search your notes',
            body: 'Type at least two characters.',
          ),
        ),
      ];
    }
    if (_search.loading) {
      return const [
        SliverToBoxAdapter(child: SkeletonList(rowCount: 6)),
        _bottomInset,
      ];
    }
    if (_search.results.isEmpty) {
      return [
        _fill(
          const EmptyState(
            icon: Icons.search_off,
            headline: 'No notes match',
            body: 'Try a shorter query or a different word.',
          ),
        ),
      ];
    }
    // Search results are relevance-ordered, so they are one flat section — day
    // grouping would imply an ordering the endpoint does not have.
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: MemSpace.x3),
          child: AppListSection(
            children: <Widget>[
              for (final n in _search.results)
                _NoteRow(
                  note: n,
                  titleFor: _collectionTitle,
                  onOpen: () => _openNote(n.id),
                ),
            ],
          ),
        ),
      ),
      if (_search.loadingMore) _tailSkeleton(),
      _bottomInset,
    ];
  }

  /// One [AppListSection] per day group, headed by a sentence-case day label.
  List<Widget> _noteGroupSlivers(
    List<MemNoteListItem> source, {
    required bool tappable,
  }) {
    final groups = _group(source);
    final slivers = <Widget>[];
    for (final e in groups.entries) {
      slivers.add(
        SliverToBoxAdapter(
          child: AppListSection(
            header: SectionHeader(
              label: memDayLabel(e.value.first.updatedAt),
              uppercase: false,
              padding: const EdgeInsets.only(top: MemSpace.sectionGap),
            ),
            children: <Widget>[
              for (final n in e.value)
                _NoteRow(
                  note: n,
                  titleFor: _collectionTitle,
                  onOpen: tappable ? () => _openNote(n.id) : null,
                ),
            ],
          ),
        ),
      );
    }
    return slivers;
  }

  Widget _tailSkeleton() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: MemSpace.x3),
        child: SkeletonList(rowCount: 3),
      ),
    );
  }
}

/// One note in the timeline (or in a search result list).
///
/// 76 dp minimum, no leading article glyph — every note carried the identical
/// icon; the collection inks carry identity and this buys ~24 dp of width.
/// [onOpen] null means a stale snapshot row: non-tappable, reduced emphasis,
/// and no `Hero` (the flight belongs to the live row).
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.titleFor,
    required this.onOpen,
  });

  final MemNoteListItem note;
  final String Function(String) titleFor;
  final VoidCallback? onOpen;

  /// `snippet` when the server sent one, else `content` when it is present.
  /// Never a "No preview" placeholder — the row simply shrinks.
  String? get _snippet {
    final String? snippet = note.snippet;
    if (snippet != null && snippet.isNotEmpty) return snippet;
    final String? content = note.content;
    if (content != null && content.isNotEmpty) return content;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool live = onOpen != null;
    final String? snippet = _snippet;
    final Widget titleText = Text(note.title);
    return AppRow(
      minHeight: MemSize.rowNote,
      enabled: live,
      onTap: onOpen,
      title: live
          ? Hero(
              tag: 'note-title-${note.id}',
              flightShuttleBuilder: _noteTitleShuttle,
              child: titleText,
            )
          : titleText,
      subtitle: snippet == null ? null : Text(snippet),
      meta: note.collectionIds.isEmpty
          ? null
          : _NoteTags(ids: note.collectionIds, titleFor: titleFor),
      trailingText: memRelativeTime(note.updatedAt),
    );
  }
}

/// Renders the **destination** style for the whole flight so the title does not
/// restyle mid-air (§2.11). NoteDetail's title is `headlineSmall` (§2.4).
Widget _noteTitleShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final ThemeData theme = Theme.of(flightContext);
  final Hero hero = toHeroContext.widget as Hero;
  return DefaultTextStyle(
    style: theme.textTheme.headlineSmall ?? const TextStyle(),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    child: hero.child,
  );
}

/// The note row's meta line: up to two collection tags, then `+n`.
///
/// Reads [AppRowDensityScope] so it degrades in step with the row: once the
/// text scale forces `condensed`, every tag collapses into a single `+n`.
class _NoteTags extends StatelessWidget {
  const _NoteTags({required this.ids, required this.titleFor});

  final List<String> ids;
  final String Function(String) titleFor;

  @override
  Widget build(BuildContext context) {
    if (AppRowDensityScope.of(context).collapseTags) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: CollectionOverflowTag(count: ids.length),
      );
    }

    final List<String> shown = ids.take(2).toList(growable: false);
    final int hidden = ids.length - shown.length;
    final children = <Widget>[];
    for (final id in shown) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: MemSpace.chipGap));
      }
      // Flexible so two long titles ellipsize instead of overflowing the row.
      children.add(
        Flexible(child: CollectionTag(collectionId: id, title: titleFor(id))),
      );
    }
    if (hidden > 0) {
      children
        ..add(const SizedBox(width: MemSpace.chipGap))
        ..add(CollectionOverflowTag(count: hidden));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// `9 results` plus a way out, in `primaryContainer` — the *tonal* role, not a
/// selection (§2.12).
class _ResultsStrip extends StatelessWidget {
  const _ResultsStrip({super.key, required this.count, required this.onClear});

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MemInsets.pageH,
        MemSpace.x3,
        MemInsets.pageH,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: MemRadius.controlAll,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: MemSpace.x3,
            end: MemSpace.x1,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  count == 1 ? '1 result' : '$count results',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onPrimaryContainer,
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `listCollections` failures are non-fatal, but they must not be silent
/// (`#1`). One 40 dp row above the timeline, with a real way to retry.
class _CollectionsUnavailableStrip extends StatelessWidget {
  const _CollectionsUnavailableStrip({
    required this.busy,
    required this.onRetry,
  });

  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MemInsets.pageH,
        0,
        MemInsets.pageH,
        MemSpace.x2,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: MemRadius.controlAll,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: MemSpace.x3,
              end: MemSpace.x1,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: MemSpace.x2),
                Expanded(
                  child: Text(
                    'Collections unavailable',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : onRetry,
                  child: busy
                      ? const InlineSpinner()
                      : const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
