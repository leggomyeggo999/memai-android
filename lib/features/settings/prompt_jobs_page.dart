import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/prompts/home_prompt_widget_sync.dart';
import '../../core/prompts/prompt_template.dart';

/// Create, reorder pins, pin to home widget, edit, and delete reusable chat jobs.
class PromptJobsPage extends StatefulWidget {
  const PromptJobsPage({super.key});

  @override
  State<PromptJobsPage> createState() => _PromptJobsPageState();
}

class _PromptJobsPageState extends State<PromptJobsPage> {
  bool _pinSupported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final supported = await isPinWidgetSupported();
      if (mounted) setState(() => _pinSupported = supported);
    });
  }

  Future<void> _upsertPrompt({PromptTemplate? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PromptJobEditorSheet(existing: existing),
    );
  }

  Future<void> _pinWidget() async {
    final app = AppScope.of(context);
    await syncHomePromptWidget(
      all: app.promptTemplates,
      pinnedIds: app.pinnedTemplateIds,
    );
    await requestPinPromptWidget();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pinned = [
      for (final id in app.pinnedTemplateIds) app.promptById(id),
    ].whereType<PromptTemplate>().toList();
    return Scaffold(
          appBar: AppBar(
            title: const Text('Prompt jobs'),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _upsertPrompt(),
            child: const Icon(Icons.add),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(
                'Home screen',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Pin up to four jobs on the Prompt jobs widget. Tapping opens MemDroid '
                'and runs them in Chat; you\'ll get a notification when finished.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.tonal(
                    onPressed: _pinSupported ? _pinWidget : null,
                    child: const Text('Add widget to home'),
                  ),
                  const SizedBox(width: 12),
                  if (!_pinSupported)
                    Expanded(
                      child: Text(
                        'Pin widgets require Android 8+ with a launcher that supports them.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Pinned for widget (${pinned.length}/4)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (pinned.isEmpty)
                Text(
                  'Open a template’s pin menu below, or reorder here once pinned.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pinned.length,
                  onReorder: (oldI, newI) {
                    if (newI > oldI) newI -= 1;
                    final next = List<PromptTemplate>.from(pinned);
                    final moved = next.removeAt(oldI);
                    next.insert(newI, moved);
                    unawaited(
                      AppScope.of(context).setPinnedTemplateIds(
                        next.map((e) => e.id).toList(),
                      ),
                    );
                  },
                  itemBuilder: (ctx, i) {
                    final t = pinned[i];
                    return ListTile(
                      key: ValueKey(t.id),
                      leading: Icon(
                        Icons.drag_handle,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(t.title),
                      subtitle:
                          Text(t.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: 'Unpin',
                        icon: const Icon(Icons.push_pin_outlined),
                        onPressed: () {
                          AppScope.of(context).setPinnedTemplateIds(
                            app.pinnedTemplateIds
                                .where((id) => id != t.id)
                                .toList(),
                          );
                        },
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),
              Text(
                'All jobs',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (app.promptTemplates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No jobs yet. Tap + to add one.')),
                )
              else
                ...app.promptTemplates.map(
                  (t) => _jobTile(
                    context,
                    app,
                    t,
                    pinned: app.pinnedTemplateIds.contains(t.id),
                  ),
                ),
            ],
          ),
        );
  }

  Widget _jobTile(
    BuildContext context,
    AppState app,
    PromptTemplate t, {
    required bool pinned,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(t.title),
        subtitle: Text(
          t.body,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await _upsertPrompt(existing: t);
            } else if (v == 'delete') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete job?'),
                  content: Text('“${t.title}” will be removed.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                if (!context.mounted) return;
                await AppScope.of(context).removePromptJob(t.id);
              }
            } else if (v == 'pin') {
              if (app.pinnedTemplateIds.length >= 4 &&
                  !app.pinnedTemplateIds.contains(t.id)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unpin another job first (max 4).'),
                    ),
                  );
                }
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
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'pin',
              child: Text(pinned ? 'Unpin from widget' : 'Pin to widget'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _PromptJobEditorSheet extends StatefulWidget {
  const _PromptJobEditorSheet({this.existing});

  final PromptTemplate? existing;

  @override
  State<_PromptJobEditorSheet> createState() => _PromptJobEditorSheetState();
}

class _PromptJobEditorSheetState extends State<_PromptJobEditorSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _bodyCtrl = TextEditingController(text: widget.existing?.body ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext sheetContext) async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) return;

    final app = AppScope.of(context);
    final id = widget.existing?.id ?? const Uuid().v4();
    final tpl = PromptTemplate(id: id, title: title, body: body);
    final messenger = ScaffoldMessenger.of(context);

    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    await app.upsertPromptJob(tpl);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(widget.existing == null ? 'Job saved.' : 'Changes saved.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            existing == null ? 'New prompt job' : 'Edit prompt job',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Categorize untagged notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Prompt sent to Chat (tools enabled)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _save(context),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
