import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_api_exception.dart';
import '../../core/mem/mem_models.dart';
import '../../theme/mem_metrics.dart';
import '../../ui/app_list_section.dart';
import '../../ui/async_page_mixin.dart';
import '../../ui/collection_tag.dart';
import '../../ui/confirm_destructive_dialog.dart';
import '../../ui/date_labels.dart';
import '../../ui/editor_sheet.dart';
import '../../ui/empty_state.dart';
import '../../ui/error_state.dart';
import '../../ui/feedback.dart';
import '../../ui/search_pill.dart';
import '../../ui/skeleton.dart';
import '../settings/settings_page.dart';

/// Above this many collections the AppBar grows a search affordance. Below it
/// the whole list is on one or two screens and a filter would be noise (§4.3).
const int _kSearchThreshold = 10;

/// Create, rename, describe, or delete collections (Mem folders).
///
/// Presentation notes that are load-bearing:
/// * The **row tap edits**. The old kebab-only edit made the whole row an inert
///   false affordance (`#10`) and doubled the taps needed to rename anything
///   (`#6`). The kebab now holds `Delete` only — a secondary verb.
/// * The subtitle carries the description **and** the pluralised note count,
///   never one or the other (`#11`).
/// * The FAB stays — creating belongs in the thumb zone. The last row is no
///   longer hidden underneath it because the list reserves
///   [MemInsets.listBottomForFab] (`#8`).
class CollectionsManagePage extends StatefulWidget {
  const CollectionsManagePage({super.key});

  @override
  State<CollectionsManagePage> createState() => _CollectionsManagePageState();
}

class _CollectionsManagePageState extends State<CollectionsManagePage>
    with AsyncPageMixin {
  List<MemCollectionItem> _items = [];

  /// The raw error, kept raw: it is formatted exactly once, by `memErrorText`
  /// inside [ErrorState] / [errSnack]. No `e.toString()` reaches a widget.
  Object? _error;
  bool _loading = true;

  /// Distinct from [_error]: there is nothing to retry until a key exists.
  bool _missingKey = false;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;
  String _query = '';

  /// Resolved fresh from the CURRENT key on every call — never cached, never
  /// snapshotted into a sheet, so a key change applies immediately.
  MemApiClient? _client() {
    final k = AppScope.of(context).memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  Future<void> _load() async {
    final c = _client();
    if (c == null) {
      setState(() {
        _missingKey = true;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _missingKey = false;
    });
    try {
      final list = await c.listCollections(limit: 100);
      setStateIfMounted(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_items.isEmpty) {
        setState(() {
          _error = e;
          _loading = false;
        });
      } else {
        // A failed refresh must never blank rows that are already on screen
        // (§0.1 rule 9) — the failure goes to a snackbar with a Retry instead.
        setState(() => _loading = false);
        showError(e, onRetry: _load);
      }
    }
  }

  /// The page-side half of every mutation: reload, then bump the sole
  /// cross-screen invalidation channel. `AppState` is read **before** the await.
  Future<void> _reloadAndBump() async {
    if (!mounted) return;
    final app = AppScope.of(context);
    await _load();
    if (!mounted) return;
    app.bumpNotesListRevision();
  }

  // ---------------------------------------------------------------- editor

  Future<void> _openEditor({MemCollectionItem? existing}) async {
    // Captured from the PAGE, before anything async and before the sheet
    // exists, so the confirmation still lands after the sheet is popped.
    final messenger = messengerOf();

    // Controllers are seeded from `existing` and owned here, so they outlive
    // the sheet's own build and are disposed exactly once.
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    try {
      await showEditorSheet<void>(
        context: context,
        title: existing == null ? 'New collection' : 'Edit collection',
        saveLabel: existing == null ? 'Create' : 'Save',
        isValid: () => titleCtrl.text.trim().isNotEmpty,
        fieldsBuilder: (BuildContext sheetContext, EditorSheetState state) {
          return <Widget>[
            TextField(
              controller: titleCtrl,
              autofocus: existing == null,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              // Borders come from the global InputDecorationTheme.
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => state.refresh(),
            ),
            const SizedBox(height: MemSpace.x3),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                // The create/update payload asymmetry, surfaced: on edit an
                // empty field is sent as an empty string and CLEARS the
                // stored description.
                helperText: existing == null ? null : 'Leave empty to clear',
              ),
              onChanged: (_) => state.refresh(),
            ),
          ];
        },
        onSave: (BuildContext sheetContext) async {
          final title = titleCtrl.text.trim();
          final desc = descCtrl.text.trim();
          // Resolved as a function at save time — never a client captured when
          // the sheet was opened.
          final c = _client();
          if (c == null) throw MemApiException('Missing Mem API key.');

          if (existing == null) {
            // Intentional API asymmetry #1: create omits an empty description
            // entirely rather than creating an empty one.
            await c.createCollection(
              title: title,
              description: desc.isEmpty ? null : desc,
            );
          } else {
            // Intentional API asymmetry #2: update sends the trimmed —
            // possibly empty — string, because that is what clears the field.
            await c.updateCollection(
              collectionId: existing.id,
              title: title,
              description: desc,
            );
          }
          if (!sheetContext.mounted) return;
          // Plain pop, no result: NotesPage awaits this push and reloads
          // unconditionally, so a result would be dead weight.
          Navigator.of(sheetContext).pop();
          await _reloadAndBump();
          memSnack(
            messenger,
            existing == null ? 'Collection created.' : 'Collection saved.',
          );
          // A throw anywhere above leaves the sheet open with the user's input
          // intact; showEditorSheet reports it on this same messenger.
        },
      );
    } finally {
      titleCtrl.dispose();
      descCtrl.dispose();
    }
  }

  // ---------------------------------------------------------------- delete

  Future<void> _confirmDelete(MemCollectionItem item) async {
    final int n = item.noteCount;
    final ok = await confirmDestructive(
      context,
      title: 'Delete collection?',
      consequence: n == 0
          ? 'Notes inside are kept — only the collection is removed.'
          : 'Notes inside are kept — only the collection is removed. '
                '$n ${_noteWord(n)} will be untagged.',
      actionLabel: 'Delete',
    );
    if (!ok || !mounted) return;

    // Both captured BEFORE the awaits.
    final app = AppScope.of(context);
    final messenger = messengerOf();
    final c = _client();
    if (c == null) {
      // Reachable only if the key was cleared while this page was open. Say so
      // instead of swallowing the tap (`#1`); the message is a MemApiException,
      // so memErrorText renders it and no raw exception text is involved.
      errSnack(messenger, MemApiException('Missing Mem API key.'));
      return;
    }
    try {
      await c.deleteCollection(item.id);
      await _load();
      if (!mounted) return;
      // Bump only on success — a failed delete has invalidated nothing.
      app.bumpNotesListRevision();
      memSnack(messenger, 'Collection deleted.');
    } catch (e) {
      if (!mounted) return;
      errSnack(messenger, e);
    }
  }

  // ---------------------------------------------------------------- search

  bool get _canSearch => _items.length > _kSearchThreshold;

  /// Client-side only — filtering never costs an API call (§4.3).
  List<MemCollectionItem> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((MemCollectionItem i) {
      if (i.title.toLowerCase().contains(q)) return true;
      final d = i.description;
      return d != null && d.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  void _enterSearch() {
    setState(() => _searching = true);
    postFrame(() => _searchFocus.requestFocus());
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _query = '');
    _searchFocus.requestFocus();
  }

  void _exitSearch() {
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  // ------------------------------------------------------------- lifecycle

  @override
  void initState() {
    super.initState();
    // AppScope is an InheritedWidget: reading it during initState is illegal
    // and the callback can outlive the element, so both halves are deferred.
    postFrame(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ view

  static String _noteWord(int n) => n == 1 ? 'note' : 'notes';

  /// Description **and** count, always both, always pluralised (`#11`).
  static String _subtitleFor(MemCollectionItem item) {
    final d = item.description?.trim();
    final lead = (d == null || d.isEmpty) ? 'No description' : d;
    return '$lead · ${item.noteCount} ${_noteWord(item.noteCount)}';
  }

  Widget _row(MemCollectionItem item) {
    return AppRow(
      minHeight: MemSize.rowSingleLine,
      // The same ink the user already sees on this collection's Notes tags.
      // A dot-only variant is legal here because the title sits beside it.
      leading: CollectionTag(
        collectionId: item.id,
        title: item.title,
        variant: CollectionTagVariant.dot,
      ),
      title: Text(item.title),
      subtitle: Text(_subtitleFor(item)),
      subtitleMaxLines: 2,
      trailingText: 'updated ${memRelativeTime(item.updatedAt)}',
      // The row tap is the primary action; the kebab holds the secondary verb.
      onTap: () => _openEditor(existing: item),
      trailing: SizedBox(
        width: MemSize.touchTarget,
        height: MemSize.touchTarget,
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: 'More actions',
          position: PopupMenuPosition.under,
          icon: const Icon(Icons.more_vert),
          onSelected: (_) => _confirmDelete(item),
          itemBuilder: (BuildContext context) =>
              const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
              ],
        ),
      ),
    );
  }

  /// A centred state that still scrolls, so pull-to-refresh works on every
  /// branch of [build].
  Widget _fullPage(Widget child) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: child),
            ),
          ],
        );
      },
    );
  }

  Widget _body() {
    if (_missingKey) {
      return _fullPage(
        EmptyState(
          icon: Icons.lock_outline,
          headline: 'Mem API key needed',
          body: 'Add your Mem API key to create and manage collections.',
          ctaLabel: 'Open Settings',
          onCta: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => const SettingsPage(),
            ),
          ),
        ),
      );
    }

    // First load only: a refresh keeps the rows it already has.
    if (_loading && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(
          top: MemSpace.x3,
          bottom: MemInsets.listBottomForFab,
        ),
        children: const <Widget>[
          // rowNote (76) is the tallest geometry the skeleton row draws in
          // full; a 64 dp box would clip its third bar.
          SkeletonList(rowCount: 6, rowHeight: MemSize.rowNote),
        ],
      );
    }

    if (_error != null) {
      return _fullPage(ErrorState(error: _error!, onRetry: _load));
    }

    if (_items.isEmpty) {
      return _fullPage(
        EmptyState(
          icon: Icons.folder_outlined,
          headline: 'Group related notes into collections',
          body: 'A collection is a folder — a note can live in several.',
          ctaLabel: 'New collection',
          onCta: () => _openEditor(),
        ),
      );
    }

    final List<MemCollectionItem> visible = _visible;
    if (visible.isEmpty) {
      return _fullPage(
        EmptyState(
          icon: Icons.search_off,
          headline: 'No collections match',
          body: 'Nothing here matches “${_query.trim()}”.',
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        top: MemSpace.x3,
        // Clears the extended FAB, so the last row is reachable (`#8`).
        bottom: MemInsets.listBottomForFab,
      ),
      children: <Widget>[
        AppListSection(
          children: <Widget>[for (final MemCollectionItem i in visible) _row(i)],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        actions: <Widget>[
          if (_canSearch && !_searching)
            IconButton(
              tooltip: 'Search collections',
              icon: const Icon(Icons.search),
              onPressed: _enterSearch,
            ),
        ],
        bottom: _searching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(MemSize.chipStrip),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MemInsets.pageH,
                    0,
                    MemInsets.pageH,
                    MemSpace.x2,
                  ),
                  child: SearchPill(
                    hint: 'Filter collections',
                    active: true,
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    onTap: () => _searchFocus.requestFocus(),
                    onChanged: (String v) => setState(() => _query = v),
                    onClear: _clearSearch,
                    onCancel: _exitSearch,
                  ),
                ),
              )
            : null,
      ),
      floatingActionButton: _missingKey
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('New collection'),
            ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }
}
