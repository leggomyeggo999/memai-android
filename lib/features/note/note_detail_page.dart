import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';
import '../../theme/mem_metrics.dart';
import '../../theme/mem_typography.dart';
import '../../ui/async_page_mixin.dart';
import '../../ui/collection_tag.dart';
import '../../ui/confirm_destructive_dialog.dart';
import '../../ui/date_labels.dart';
import '../../ui/empty_state.dart';
import '../../ui/error_state.dart';
import '../../ui/feedback.dart';
import '../../ui/inline_spinner.dart';
import '../../ui/section_header.dart';
import '../../ui/skeleton.dart';
import '../../ui/sticky_action_bar.dart';
import '../settings/settings_page.dart';

/// One note, read and edited in place.
///
/// The state machine is unchanged and is keyed on `inTrash x _editing`: read
/// (Edit + overflow), trash (Restore + a "Delete permanently…" overflow), and
/// edit (Cancel + Save). What is new is that every one of those states is now
/// *stated* rather than implied — an explicit In-Trash banner, a metadata line
/// carrying created / updated / word count, collection tags that actually
/// navigate, a real Undo behind the trash snackbar, and a guard that refuses to
/// throw away unsaved edits on a system back.
class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage>
    with AsyncPageMixin<NoteDetailPage> {
  /// The short-circuit copy when the app has no Mem key. Contract string.
  static const String _kMissingKeyMessage = 'Missing Mem API key.';

  final _editCtrl = TextEditingController();

  String? _markdown;
  String? _titleText;
  DateTime? _createdAt;
  DateTime? _updatedAt;

  /// The raw load failure, formatted only at the widget boundary by
  /// [memErrorText]. Never `toString()`d into the tree.
  Object? _error;

  /// The no-key short-circuit, which is a configuration state rather than a
  /// failure and therefore gets its own recovery (Open Settings), not a Retry.
  bool _missingKey = false;

  bool _loading = true;
  DateTime? _trashedAt;
  int? _version;
  final Set<String> _assignedCollectionIds = {};
  Set<String> _assignedBackup = {};
  List<MemCollectionItem> _collections = [];

  /// `listCollections` failed. **Non-fatal by contract** — the note still
  /// renders and the tags fall back to the raw id via [_collectionTitle]. This
  /// flag only makes the swallow visible as a quiet retry strip.
  bool _collectionsUnavailable = false;
  bool _collectionsRetrying = false;

  bool _editing = false;
  bool _saving = false;

  /// Cached result of [_computeDirty], kept in state so `PopScope.canPop` and
  /// the Cancel button read the same answer without recomputing per frame.
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    // Keystrokes flip the unsaved-changes guard, so the page must know about
    // them — but only when the answer actually changes (see _syncDirty).
    _editCtrl.addListener(_syncDirty);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _editCtrl.removeListener(_syncDirty);
    _editCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- loading

  Future<void> _load() async {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) {
      setState(() {
        _loading = false;
        _missingKey = true;
        _error = null;
      });
      return;
    }
    final c = MemApiClient(apiKey: k);
    try {
      final note = await c.readNote(widget.noteId);
      List<MemCollectionItem> cols = [];
      bool collectionsFailed = false;
      try {
        cols = await c.listCollections(limit: 100);
      } catch (_) {
        // Swallowed by contract: a collections outage must never stop a note
        // from opening. The tags degrade to raw ids and the strip offers a
        // retry.
        collectionsFailed = true;
      }
      if (!mounted) return;
      setState(() {
        _markdown = note.content;
        _titleText = note.title;
        _createdAt = note.createdAt;
        _updatedAt = note.updatedAt;
        _trashedAt = note.trashedAt;
        _version = note.version;
        _assignedCollectionIds
          ..clear()
          ..addAll(note.collectionIds);
        _collections = cols;
        _collectionsUnavailable = collectionsFailed;
        _loading = false;
        _missingKey = false;
        _error = null;
      });
    } catch (e) {
      setStateIfMounted(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Retry from [ErrorState]. Distinct from [_load] because it is the only
  /// entry point allowed to blank the page back to a skeleton — the reload that
  /// follows trash/restore must keep the content that is already on screen.
  void _retryLoad() {
    setState(() {
      _loading = true;
      _error = null;
      _missingKey = false;
    });
    _load();
  }

  /// Re-fetch just the collections after the quiet strip's Retry. Same call
  /// shape as the one inside [_load]; it never touches note state.
  Future<void> _retryCollections() async {
    final c = _client();
    if (c == null) return;
    setState(() => _collectionsRetrying = true);
    try {
      final cols = await c.listCollections(limit: 100);
      setStateIfMounted(() {
        _collections = cols;
        _collectionsUnavailable = false;
        _collectionsRetrying = false;
      });
    } catch (e) {
      setStateIfMounted(() => _collectionsRetrying = false);
      showError(e, onRetry: _retryCollections);
    }
  }

  MemApiClient? _client() {
    final k = AppScope.of(context).memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  // ----------------------------------------------------------- edit session

  void _beginEdit() {
    setState(() {
      _assignedBackup = Set.from(_assignedCollectionIds);
      _editing = true;
      _editCtrl.text = _markdown ?? '';
    });
    _syncDirty();
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _assignedCollectionIds
        ..clear()
        ..addAll(_assignedBackup);
      _editCtrl.text = _markdown ?? '';
    });
    _syncDirty();
  }

  void _toggleCollection(String id, bool selected) {
    setState(() {
      if (selected) {
        _assignedCollectionIds.add(id);
      } else {
        _assignedCollectionIds.remove(id);
      }
    });
    _syncDirty();
  }

  /// The guard's predicate (§5.2): the editor text or the collection set has
  /// moved away from what the server last told us.
  bool _computeDirty() {
    if (!_editing) return false;
    if (_editCtrl.text != (_markdown ?? '')) return true;
    if (_assignedCollectionIds.length != _assignedBackup.length) return true;
    return !_assignedBackup.containsAll(_assignedCollectionIds);
  }

  /// Rebuild only when the *answer* changes, so typing does not rebuild the
  /// page on every keystroke just to re-evaluate `canPop`.
  void _syncDirty() {
    final bool next = _computeDirty();
    if (next == _dirty) return;
    setStateIfMounted(() => _dirty = next);
  }

  /// Shared by the Cancel button and the intercepted system back.
  Future<bool> _confirmDiscard() {
    return confirmDestructive(
      context,
      title: 'Discard changes?',
      consequence: 'Your edits will be lost.',
      actionLabel: 'Discard',
      cancelLabel: 'Keep editing',
    );
  }

  Future<void> _requestCancelEdit() async {
    if (!_dirty) {
      _cancelEdit();
      return;
    }
    final bool ok = await _confirmDiscard();
    if (ok && mounted) _cancelEdit();
  }

  /// System back / AppBar back while there are unsaved edits. `canPop` is false
  /// in that state, so the pop arrives here instead of destroying the route.
  Future<void> _handlePop(bool didPop, Object? result) async {
    if (didPop) return;
    final NavigatorState nav = navigatorOf();
    final bool ok = await _confirmDiscard();
    if (!ok || !mounted) return;
    _cancelEdit();
    nav.pop();
  }

  // --------------------------------------------------------------- mutation

  Future<void> _save() async {
    final v = _version;
    final app = AppScope.of(context);
    final c = _client();
    // No version or no key: the write would either clobber or 401. Stay silent
    // and stay in edit mode — the user's text is still in the controller.
    if (c == null || v == null) return;
    setState(() => _saving = true);
    final messenger = messengerOf();
    try {
      // ONE combined write: markdown + the full collection list + the version.
      final updated = await c.updateNote(
        noteId: widget.noteId,
        markdown: _editCtrl.text,
        version: v,
        collectionIds: _assignedCollectionIds.toList(),
      );
      if (!mounted) return;
      setState(() {
        _markdown = updated.content;
        _titleText = updated.title;
        _createdAt = updated.createdAt;
        _updatedAt = updated.updatedAt;
        _version = updated.version;
        _assignedCollectionIds
          ..clear()
          ..addAll(updated.collectionIds);
        _trashedAt = updated.trashedAt;
        _editing = false;
        _saving = false;
      });
      _syncDirty();
      app.bumpNotesListRevision();
      memSnack(messenger, 'Note saved.');
    } catch (e) {
      // Edit mode and the controller text both survive a failed save.
      setStateIfMounted(() => _saving = false);
      if (mounted) errSnack(messenger, e, onRetry: _save, context: context);
    }
  }

  Future<void> _moveToTrash() async {
    final app = AppScope.of(context);
    final c = _client();
    final messenger = messengerOf();
    if (c == null) return;
    try {
      await c.trashNote(widget.noteId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      app.bumpNotesListRevision();
      // A real Undo: it calls restoreNote, reloads in place and bumps the
      // revision. Trash/restore are eventually consistent, so nothing here
      // optimistically mutates a list — the reload settles it.
      undoSnack(messenger, 'Moved to trash.', onUndo: _restore);
    } catch (e) {
      if (mounted) errSnack(messenger, e, onRetry: _moveToTrash, context: context);
    }
  }

  Future<void> _restore() async {
    // The Undo action can fire after the page is gone; every lookup below reads
    // from `context`, so bail before any of them.
    if (!mounted) return;
    final app = AppScope.of(context);
    final c = _client();
    final messenger = messengerOf();
    if (c == null) return;
    try {
      await c.restoreNote(widget.noteId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      app.bumpNotesListRevision();
      memSnack(messenger, 'Note restored.');
    } catch (e) {
      if (mounted) errSnack(messenger, e, onRetry: _restore, context: context);
    }
  }

  Future<void> _confirmTrash() async {
    final bool ok = await confirmDestructive(
      context,
      title: 'Move to trash?',
      consequence: 'You can restore trashed notes later.',
      actionLabel: 'Move to trash',
    );
    if (ok && mounted) await _moveToTrash();
  }

  Future<void> _confirmDeleteForever() async {
    final bool ok = await confirmDestructive(
      context,
      title: 'Delete permanently?',
      consequence: 'This note cannot be recovered afterwards.',
      actionLabel: 'Delete permanently',
    );
    if (!ok || !mounted) return;
    final app = AppScope.of(context);
    final messenger = messengerOf();
    final nav = navigatorOf();
    final c = _client();
    if (c == null) return;
    try {
      await c.deleteNoteHard(widget.noteId);
      if (!mounted) return;
      app.bumpNotesListRevision();
      memSnack(messenger, 'Note permanently deleted.');
      // The only pop in this file that a mutation owns: the note it was showing
      // no longer exists.
      nav.pop();
    } catch (e) {
      if (mounted) {
        errSnack(messenger, e, onRetry: _confirmDeleteForever, context: context);
      }
    }
  }

  // ------------------------------------------------------------- navigation

  /// A collection tag is a real destination, not decoration: it pops back to
  /// the shell and hands the Notes tab a one-shot filter request (§5.4).
  void _openCollectionFilter(String collectionId) {
    final app = AppScope.of(context);
    final nav = navigatorOf();
    app.requestNotesFilter(collectionId);
    nav.pop();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  // ------------------------------------------------------------ derivations

  String _collectionTitle(String id) {
    for (final c in _collections) {
      if (c.id == id) return c.title;
    }
    return id;
  }

  /// `Created Mar 4, 2026 · Updated 2h ago · 342 words` — all three were
  /// previously computed by the server and shown nowhere.
  String _metadataLine() {
    final parts = <String>[];
    final created = _createdAt;
    if (created != null) {
      parts.add('Created ${DateFormat.yMMMd().format(created.toLocal())}');
    }
    final updated = _updatedAt;
    if (updated != null) parts.add(_updatedLabel(updated));
    parts.add(_wordCountLabel(_markdown ?? ''));
    return parts.join(' · ');
  }

  /// `memRelativeTime` returns either an elapsed counter (`5m`, `2h`) or a date
  /// label (`now`, `Mon`, `Mar 4`). Only the counters take "ago".
  String _updatedLabel(DateTime updated) {
    final String rel = memRelativeTime(updated);
    if (rel == 'now') return 'Updated just now';
    if (RegExp(r'^\d+[mh]$').hasMatch(rel)) return 'Updated $rel ago';
    return 'Updated $rel';
  }

  String _wordCountLabel(String markdown) {
    int words = 0;
    for (final token in markdown.split(RegExp(r'\s+'))) {
      if (token.isNotEmpty) words++;
    }
    return words == 1 ? '1 word' : '$words words';
  }

  // ----------------------------------------------------------------- render

  @override
  Widget build(BuildContext context) {
    final inTrash = _trashedAt != null;
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        appBar: AppBar(actions: _appBarActions(inTrash)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (inTrash && !_editing) _buildTrashBanner(context),
            Expanded(child: _buildBody(context)),
            // Save duplicated above the keyboard. The AppBar Save stays, because
            // the action gating is part of the state machine.
            if (_editing)
              StickyActionBar(
                primary: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving ? const InlineSpinner() : const Text('Save'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _appBarActions(bool inTrash) {
    // Nothing has loaded yet: an Edit pencil over a skeleton or an error page is
    // a false affordance, and its Save would silently no-op without a version.
    if (_markdown == null) return const <Widget>[];

    if (_editing) {
      return <Widget>[
        TextButton(
          onPressed: _saving ? null : _requestCancelEdit,
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const InlineSpinner() : const Text('Save'),
        ),
        const SizedBox(width: MemSpace.x1),
      ];
    }

    return <Widget>[
      if (!inTrash)
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit',
          onPressed: _beginEdit,
        ),
      if (inTrash)
        TextButton(onPressed: _restore, child: const Text('Restore')),
      PopupMenuButton<String>(
        tooltip: 'More actions',
        onSelected: (String v) {
          if (v == 'trash') _confirmTrash();
          if (v == 'delete') _confirmDeleteForever();
        },
        // "Delete permanently…" exists only for a note that is already in the
        // trash — the Mail/Photos convention, and the fix for a one-item
        // overflow that offered a hard delete from the read state.
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          if (!inTrash)
            const PopupMenuItem<String>(
              value: 'trash',
              child: Text('Move to trash'),
            ),
          if (inTrash)
            const PopupMenuItem<String>(
              value: 'delete',
              child: Text('Delete permanently…'),
            ),
        ],
      ),
    ];
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: MemSpace.x5),
        child: SkeletonList(rowCount: 5, inSection: false),
      );
    }
    if (_missingKey) {
      return EmptyState(
        icon: Icons.vpn_key_outlined,
        headline: _kMissingKeyMessage,
        body: 'Add your Mem API key in Settings to open this note.',
        ctaLabel: 'Open Settings',
        onCta: _openSettings,
      );
    }
    final Object? error = _error;
    if (error != null) {
      return ErrorState(
        error: error,
        onRetry: _retryLoad,
        title: "Couldn't open this note",
      );
    }
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(MemSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _editing ? _editChildren(context) : _readChildren(context),
      ),
    );
  }

  /// The explicit trashed state, instead of state implied by which button
  /// happened to appear in the AppBar.
  Widget _buildTrashBanner(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      color: cs.errorContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: MemInsets.pageH,
        vertical: MemSpace.sectionPadV,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.delete_outline, size: 20, color: cs.onErrorContainer),
          const SizedBox(width: MemSpace.x3),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'In Trash',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onErrorContainer,
                  ),
                ),
                Text(
                  'Notes in Trash can be deleted permanently.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: MemSpace.x3),
          FilledButton.tonal(
            onPressed: _restore,
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  List<Widget> _readChildren(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<String> ids = _assignedCollectionIds.toList();

    return <Widget>[
      // The destination half of the Notes-row flight. The shuttle renders the
      // destination style so the title does not restyle in mid-air.
      Hero(
        tag: 'note-title-${widget.noteId}',
        flightShuttleBuilder: _titleFlightShuttle,
        child: Text(
          _titleText ?? '',
          style: theme.textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: MemSpace.x2),
      Text(
        _metadataLine(),
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      if (_collectionsUnavailable) ...<Widget>[
        const SizedBox(height: MemSpace.x4),
        _buildCollectionsUnavailable(context),
      ],
      if (ids.isNotEmpty) ...<Widget>[
        const SizedBox(height: MemSpace.x4),
        Wrap(
          spacing: MemSpace.chipGap,
          runSpacing: MemSpace.x1,
          children: <Widget>[
            for (final String id in ids)
              CollectionTag(
                collectionId: id,
                title: _collectionTitle(id),
                onTap: () => _openCollectionFilter(id),
              ),
          ],
        ),
      ],
      const SizedBox(height: MemSpace.x4),
      // MarkdownBody (not Markdown): no nested scroll view, so the parent
      // SingleChildScrollView receives drags on mobile.
      MarkdownBody(
        data: _markdown ?? '',
        selectable: true,
        styleSheet: _markdownStyle(context),
      ),
    ];
  }

  List<Widget> _editChildren(BuildContext context) {
    return <Widget>[
      if (_collectionsUnavailable) ...<Widget>[
        _buildCollectionsUnavailable(context),
        const SizedBox(height: MemSpace.x4),
      ],
      if (_collections.isNotEmpty) ...<Widget>[
        const SectionHeader(
          label: 'Collections',
          padding: EdgeInsets.only(bottom: MemSpace.headerGap),
        ),
        Wrap(
          spacing: MemSpace.chipGap,
          runSpacing: MemSpace.x1,
          children: <Widget>[
            for (final MemCollectionItem col in _collections)
              CollectionTag(
                collectionId: col.id,
                title: col.title,
                variant: CollectionTagVariant.chip,
                selected: _assignedCollectionIds.contains(col.id),
                onTap: () => _toggleCollection(
                  col.id,
                  !_assignedCollectionIds.contains(col.id),
                ),
              ),
          ],
        ),
        const SizedBox(height: MemSpace.x5),
      ],
      TextField(
        controller: _editCtrl,
        maxLines: null,
        minLines: 16,
        keyboardType: TextInputType.multiline,
        // 140 dp so the caret clears both the keyboard and the sticky Save bar.
        scrollPadding: const EdgeInsets.only(
          bottom: MemInsets.editorScrollPad,
        ),
        decoration: const InputDecoration(
          // Not a hint: this is how the Mem API derives a note's title, and it
          // stays true (and visible) after the first character is typed.
          helperText: 'The first line becomes the title.',
        ),
      ),
    ];
  }

  /// The quiet, non-fatal face of a swallowed `listCollections` failure.
  Widget _buildCollectionsUnavailable(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.only(left: MemSpace.x3, right: MemSpace.x1),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: MemRadius.controlAll,
        border: Border.all(color: cs.outline, width: hairlineWidth(context)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Collections unavailable',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (_collectionsRetrying)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: MemSpace.x3),
              child: InlineSpinner(),
            )
          else
            TextButton(
              onPressed: _retryCollections,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  Widget _titleFlightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // Render the *destination* style for the whole flight so the glyphs never
    // restyle in mid-air: headlineSmall on the way in, and the note row's
    // titleMedium on the way back out.
    final TextTheme text = Theme.of(flightContext).textTheme;
    return Material(
      type: MaterialType.transparency,
      child: Text(
        _titleText ?? '',
        style: direction == HeroFlightDirection.push
            ? text.headlineSmall
            : text.titleMedium,
      ),
    );
  }

  /// The §2.4 Markdown ramp. Built off `fromTheme` so lists and tables keep
  /// sensible defaults, then every role the spec names is pinned.
  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final double hairline = hairlineWidth(context);
    final TextStyle body = memSansStyle(
      fontSize: 16,
      lineHeight: 26,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: cs.onSurface,
    );
    final TextStyle heading3 = memSansStyle(
      fontSize: 16,
      lineHeight: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: cs.onSurface,
    );
    final TextStyle heading4 = memSansStyle(
      fontSize: 14,
      lineHeight: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: cs.onSurface,
    );

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      pPadding: EdgeInsets.zero,
      listBullet: body,
      blockSpacing: MemSpace.x3,
      h1: memSansStyle(
        fontSize: 22,
        lineHeight: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        color: cs.onSurface,
      ),
      h2: memSansStyle(
        fontSize: 18,
        lineHeight: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: cs.onSurface,
      ),
      h3: heading3,
      h4: heading4,
      h5: heading4,
      h6: heading4,
      a: body.copyWith(color: cs.primary),
      blockquote: body,
      blockquotePadding: const EdgeInsets.fromLTRB(
        MemSpace.x3,
        MemSpace.x1,
        0,
        MemSpace.x1,
      ),
      blockquoteDecoration: BoxDecoration(
        // A 3 dp rule, not a hairline: this one is a deliberate structural mark.
        border: Border(left: BorderSide(color: cs.outline, width: 3)),
      ),
      code: memMonoStyle(
        color: cs.onSurface,
      ).copyWith(backgroundColor: cs.surfaceContainer),
      codeblockPadding: const EdgeInsets.all(MemSpace.x3),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: MemRadius.tagAll,
        border: Border.all(color: cs.outlineVariant, width: hairline),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: hairline),
        ),
      ),
    );
  }
}
