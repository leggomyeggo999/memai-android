import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/prompts/home_prompt_widget_sync.dart';
import '../../core/prompts/prompt_template.dart';
import '../../theme/mem_metrics.dart';
import '../../ui/app_list_section.dart';
import '../../ui/async_page_mixin.dart';
import '../../ui/confirm_destructive_dialog.dart';
import '../../ui/editor_sheet.dart';
import '../../ui/empty_state.dart';
import '../../ui/feedback.dart';
import '../../ui/hairline.dart';
import '../../ui/search_pill.dart';
import '../../ui/section_header.dart';
import '../../ui/status_tile.dart';

/// Once the list is longer than this, a client-side filter pill appears.
const int _kFilterThreshold = 8;

/// Create, reorder pins, pin to the home widget, edit, and delete reusable
/// chat jobs (§4.8).
///
/// **`pinnedTemplateIds` is the order source of truth** — the pinned list is
/// derived from it via `promptById`, so stale ids are tolerated silently and a
/// reorder persists the *full* id list.
class PromptJobsPage extends StatefulWidget {
  const PromptJobsPage({super.key});

  @override
  State<PromptJobsPage> createState() => _PromptJobsPageState();
}

class _PromptJobsPageState extends State<PromptJobsPage>
    with AsyncPageMixin<PromptJobsPage> {
  /// `null` until the post-frame probe settles — the status tile says so
  /// instead of showing a button that may or may not be real.
  bool? _pinSupported;

  /// The `syncHomePromptWidget` → `requestPinPromptWidget` round-trip.
  bool _pinning = false;

  final TextEditingController _filterCtrl = TextEditingController();
  final FocusNode _filterFocus = FocusNode();
  bool _filterActive = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final supported = await isPinWidgetSupported();
      if (mounted) setState(() => _pinSupported = supported);
    });
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  // --- Editor -------------------------------------------------------------

  Future<void> _upsertPrompt({PromptTemplate? existing}) async {
    // The draft is the bridge between the sheet's fields (which own — and
    // dispose — the controllers) and the page-level `isValid` gate / payload.
    final _PromptDraft draft = _PromptDraft(existing);

    // Captured from the PAGE, before anything async, so the confirmation still
    // lands after the sheet is popped.
    final ScaffoldMessengerState messenger = messengerOf();

    await showEditorSheet<void>(
      context: context,
      title: existing == null ? 'New prompt job' : 'Edit prompt job',
      footerNote: const Text('Sent to the model verbatim.'),
      // Save stays disabled until both fields carry text — the old silent
      // no-op on empty input is gone.
      isValid: () => draft.isComplete,
      fieldsBuilder: (BuildContext sheetContext, EditorSheetState state) =>
          <Widget>[_PromptJobFields(draft: draft, sheet: state)],
      onSave: (BuildContext sheetContext) async {
        final String title = draft.title.trim();
        final String body = draft.body.trim();
        final AppState app = AppScope.of(context);
        // Template ids are a STABLE contract for the home-widget deep link
        // `memai://prompt?templateId=<id>`: an edit reuses the existing id and
        // must never regenerate or rename it.
        final String id = existing?.id ?? const Uuid().v4();
        final PromptTemplate tpl = PromptTemplate(
          id: id,
          title: title,
          body: body,
        );

        if (!sheetContext.mounted) return;
        // Pop the sheet FIRST, then await the write — same ordering as the
        // collections editor. (`EditorSheetState.close()` is the same pop.)
        Navigator.of(sheetContext).pop();
        await app.upsertPromptJob(tpl);
        if (!mounted) return;
        memSnack(messenger, existing == null ? 'Job saved.' : 'Changes saved.');
      },
    );
  }

  // --- Home widget --------------------------------------------------------

  Future<void> _pinWidget() async {
    final app = AppScope.of(context);
    setState(() => _pinning = true);
    try {
      // The widget data must be written BEFORE the launcher is asked to pin
      // it, or the pinned widget renders empty slots.
      await syncHomePromptWidget(
        all: app.promptTemplates,
        pinnedIds: app.pinnedTemplateIds,
      );
      await requestPinPromptWidget();
    } finally {
      setStateIfMounted(() => _pinning = false);
    }
  }

  Widget _homeWidgetTile() {
    final bool? supported = _pinSupported;
    if (supported == null) {
      return const StatusTile(
        icon: Icons.widgets_outlined,
        label: 'Home screen widget',
        level: StatusLevel.pending,
        status: 'Checking…',
        detail: 'Looking for launcher support.',
        busy: true,
      );
    }
    if (!supported) {
      // The explanatory row that replaces the greyed ghost button: state is
      // said in words, not implied by a disabled control.
      return const StatusTile(
        icon: Icons.widgets_outlined,
        label: 'Home screen widget',
        level: StatusLevel.neutral,
        status: 'Not offered',
        detail:
            'Add it from your launcher’s widget picker — automatic pinning '
            'needs Android 8+ and a launcher that supports it.',
      );
    }
    return StatusTile(
      icon: Icons.widgets_outlined,
      label: 'Home screen widget',
      level: StatusLevel.ok,
      status: 'Available',
      detail:
          'A tap runs the pinned job in Chat and notifies you when it ends.',
      actionLabel: 'Add to home',
      onAction: _pinWidget,
      busy: _pinning,
    );
  }

  // --- Pin / unpin --------------------------------------------------------

  Future<void> _togglePin(AppState app, PromptTemplate t) async {
    // The 5th-pin rejection guard, unchanged: the widget has exactly four
    // slots, so pin #5 is refused rather than silently dropping pin #1.
    if (app.pinnedTemplateIds.length >= 4 &&
        !app.pinnedTemplateIds.contains(t.id)) {
      showMessage('Unpin another job first (max 4).');
      return;
    }
    final next = List<String>.from(app.pinnedTemplateIds);
    if (next.contains(t.id)) {
      next.remove(t.id);
    } else {
      next.add(t.id);
    }
    if (!mounted) return;
    await AppScope.of(context).setPinnedTemplateIds(next);
  }

  void _unpin(AppState app, PromptTemplate t) {
    unawaited(
      AppScope.of(context).setPinnedTemplateIds(
        app.pinnedTemplateIds.where((id) => id != t.id).toList(),
      ),
    );
  }

  // --- Delete -------------------------------------------------------------

  Future<void> _deleteJob(PromptTemplate t) async {
    final ScaffoldMessengerState messenger = messengerOf();
    final bool ok = await confirmDestructive(
      context,
      title: 'Delete job?',
      consequence:
          '“${t.title}” will be removed. Any home-screen widget slot using it '
          'goes empty.',
      actionLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    await AppScope.of(context).removePromptJob(t.id);
    if (!mounted) return;
    memSnack(messenger, 'Job deleted.');
  }

  // --- Filter -------------------------------------------------------------

  void _enterFilter() {
    setState(() => _filterActive = true);
    _filterFocus.requestFocus();
  }

  void _clearFilterText() {
    _filterCtrl.clear();
    setState(() => _query = '');
  }

  void _exitFilter() {
    _filterCtrl.clear();
    _filterFocus.unfocus();
    setState(() {
      _query = '';
      _filterActive = false;
    });
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pinned = [
      for (final id in app.pinnedTemplateIds) app.promptById(id),
    ].whereType<PromptTemplate>().toList();

    final List<PromptTemplate> all = app.promptTemplates;
    final bool showFilter = all.length > _kFilterThreshold;
    final String query = showFilter ? _query.trim().toLowerCase() : '';
    final List<PromptTemplate> visible = query.isEmpty
        ? all
        : all
              .where(
                (t) =>
                    t.title.toLowerCase().contains(query) ||
                    t.body.toLowerCase().contains(query),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Prompt jobs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _upsertPrompt(),
        icon: const Icon(Icons.add),
        label: const Text('New job'),
      ),
      body: ListView(
        // The FAB must not occlude the last row's controls.
        padding: const EdgeInsets.only(
          top: MemSpace.x4,
          bottom: MemInsets.listBottomForFab,
        ),
        children: <Widget>[
          AppListSection(
            header: const SectionHeader(
              label: 'Home widget',
              padding: EdgeInsets.zero,
            ),
            children: <Widget>[_homeWidgetTile()],
          ),
          const SizedBox(height: MemSpace.sectionGap),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: MemSpace.x6),
              child: EmptyState(
                icon: Icons.bolt_outlined,
                headline: 'Create your first prompt job',
                body: 'Run it from a home-screen widget with one tap.',
                ctaLabel: 'New job',
                onCta: () => _upsertPrompt(),
                firstRun: true,
              ),
            )
          else ...<Widget>[
            AppListSection(
              header: SectionHeader(
                label: 'Pinned · ${pinned.length}/4',
                padding: EdgeInsets.zero,
              ),
              children: <Widget>[
                if (pinned.isEmpty)
                  const AppRow(
                    leading: Icon(Icons.push_pin_outlined),
                    title: Text('Nothing pinned'),
                    subtitle: Text(
                      'Pin up to four jobs to fill the home-screen widget.',
                    ),
                    subtitleMaxLines: 1,
                    enabled: false,
                  )
                else
                  _pinnedList(app, pinned),
              ],
            ),
            const SizedBox(height: MemSpace.sectionGap),
            SectionHeader(
              label: 'All jobs · ${all.length}',
              padding: const EdgeInsets.fromLTRB(
                MemInsets.pageH,
                0,
                MemInsets.pageH,
                MemSpace.headerGap,
              ),
            ),
            if (showFilter) ...<Widget>[
              Padding(
                padding: MemSpace.pageHorizontal,
                child: SearchPill(
                  hint: 'Filter jobs',
                  active: _filterActive,
                  controller: _filterCtrl,
                  focusNode: _filterFocus,
                  onTap: _enterFilter,
                  onChanged: (String v) => setState(() => _query = v),
                  onClear: _clearFilterText,
                  onCancel: _exitFilter,
                ),
              ),
              const SizedBox(height: MemSpace.headerGap),
            ],
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: MemSpace.x4),
                child: EmptyState(
                  icon: Icons.search_off,
                  headline: 'No jobs match',
                  body: 'Try a different word, or clear the filter.',
                  ctaLabel: 'Clear filter',
                  onCta: _exitFilter,
                ),
              )
            else
              AppListSection(
                children: <Widget>[
                  for (final t in visible)
                    _allJobRow(
                      app,
                      t,
                      pinned: app.pinnedTemplateIds.contains(t.id),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  /// The pinned list, in `pinnedTemplateIds` order.
  ///
  /// `buildDefaultDragHandles: false` is the point of `#10`: the only way to
  /// drag is the handle the user can see, and long-press-anywhere — the
  /// invisible gesture the decorative handle used to lie about — is gone.
  Widget _pinnedList(AppState app, List<PromptTemplate> pinned) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      // The stock decorator animates elevation to 6 and paints a shadow;
      // depth here is a surface step, app-wide (§0.1).
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return Material(
          color: scheme.surfaceContainerHigh,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          child: child,
        );
      },
      itemCount: pinned.length,
      onReorder: (oldI, newI) {
        if (newI > oldI) newI -= 1;
        final next = List<PromptTemplate>.from(pinned);
        final moved = next.removeAt(oldI);
        next.insert(newI, moved);
        unawaited(
          AppScope.of(
            context,
          ).setPinnedTemplateIds(next.map((e) => e.id).toList()),
        );
      },
      itemBuilder: (ctx, i) {
        final t = pinned[i];
        return _pinnedRow(app, pinned, t, i);
      },
    );
  }

  Widget _pinnedRow(
    AppState app,
    List<PromptTemplate> pinned,
    PromptTemplate t,
    int index,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isLast = index == pinned.length - 1;

    return Column(
      // The reorder key contract: one ValueKey per template id.
      key: ValueKey(t.id),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppRow(
          minHeight: MemSize.rowSingleLine,
          leading: SizedBox(
            width: 20,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          title: Text(t.title),
          subtitle: Text(_promptPreview(t.body)),
          subtitleMaxLines: 1,
          onTap: () => _upsertPrompt(existing: t),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // A REAL drag handle: pointer-down on this icon starts the drag.
              ReorderableDragStartListener(
                index: index,
                child: Semantics(
                  label: 'Reorder ${t.title}',
                  child: SizedBox(
                    width: MemSize.touchTarget,
                    height: MemSize.touchTarget,
                    child: Icon(
                      Icons.drag_handle,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Unpin',
                icon: Icon(Icons.push_pin, color: scheme.primary),
                onPressed: () => _unpin(app, t),
              ),
            ],
          ),
        ),
        if (!isLast) const Hairline(indent: MemSpace.dividerIndent),
      ],
    );
  }

  Widget _allJobRow(AppState app, PromptTemplate t, {required bool pinned}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppRow(
      // Row tap edits — the inert row is fixed (`#6`, `#10`).
      onTap: () => _upsertPrompt(existing: t),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(t.title)),
          if (pinned) ...<Widget>[
            const SizedBox(width: MemSpace.x2),
            // The visible pinned indicator (`#11`).
            Semantics(
              label: 'Pinned to the home widget',
              child: Icon(Icons.push_pin, size: 14, color: scheme.primary),
            ),
          ],
        ],
      ),
      subtitle: Text(_promptPreview(t.body)),
      subtitleMaxLines: 1,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The primary secondary-action moves OUT of the kebab (`#6`).
          IconButton(
            tooltip: pinned ? 'Unpin from widget' : 'Pin to widget',
            icon: Icon(
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: pinned ? scheme.primary : scheme.onSurfaceVariant,
            ),
            onPressed: () => _togglePin(app, t),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == 'edit') {
                await _upsertPrompt(existing: t);
              } else if (v == 'delete') {
                await _deleteJob(t);
              }
            },
            itemBuilder: (ctx) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
              PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

/// A prompt body collapsed to one line for the row preview. Presentation only
/// — the stored body is never rewritten.
String _promptPreview(String body) =>
    body.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The live values of the editor sheet's two fields.
///
/// The controllers themselves belong to [_PromptJobFields] — a `State` that
/// lives and dies with the sheet — so nothing can read them after teardown.
/// The page-level `isValid` gate and the save payload read this instead.
class _PromptDraft {
  _PromptDraft(PromptTemplate? existing)
    : title = existing?.title ?? '',
      body = existing?.body ?? '';

  String title;
  String body;

  bool get isComplete => title.trim().isNotEmpty && body.trim().isNotEmpty;
}

/// The editor sheet's fields. Seeds its controllers from the draft and disposes
/// them in its own `dispose`, per the editor-sheet contract.
class _PromptJobFields extends StatefulWidget {
  const _PromptJobFields({required this.draft, required this.sheet});

  final _PromptDraft draft;
  final EditorSheetState sheet;

  @override
  State<_PromptJobFields> createState() => _PromptJobFieldsState();
}

class _PromptJobFieldsState extends State<_PromptJobFields> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.draft.title);
    _bodyCtrl = TextEditingController(text: widget.draft.body);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _titleCtrl,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'e.g. Categorize untagged notes',
          ),
          onChanged: (v) {
            widget.draft.title = v;
            // Re-reads the Save gate.
            widget.sheet.refresh();
          },
        ),
        const SizedBox(height: MemSpace.x3),
        TextField(
          controller: _bodyCtrl,
          minLines: 6,
          maxLines: 12,
          scrollPadding: const EdgeInsets.only(
            bottom: MemInsets.editorScrollPad,
          ),
          decoration: const InputDecoration(
            labelText: 'Prompt sent to Chat (tools enabled)',
            alignLabelWithHint: true,
          ),
          onChanged: (v) {
            widget.draft.body = v;
            widget.sheet.refresh();
          },
        ),
      ],
    );
  }
}
