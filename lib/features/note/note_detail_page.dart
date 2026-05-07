import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../app_scope.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';

class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  final _editCtrl = TextEditingController();

  String? _markdown;
  String? _titleText;
  String? _error;
  bool _loading = true;
  DateTime? _trashedAt;
  int? _version;
  final Set<String> _assignedCollectionIds = {};
  Set<String> _assignedBackup = {};
  List<MemCollectionItem> _collections = [];

  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Missing Mem API key.';
      });
      return;
    }
    final c = MemApiClient(apiKey: k);
    try {
      final note = await c.readNote(widget.noteId);
      List<MemCollectionItem> cols = [];
      try {
        cols = await c.listCollections(limit: 100);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _markdown = note.content;
        _titleText = note.title;
        _trashedAt = note.trashedAt;
        _version = note.version;
        _assignedCollectionIds
          ..clear()
          ..addAll(note.collectionIds);
        _collections = cols;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  MemApiClient? _client() {
    final k = AppScope.of(context).memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  void _beginEdit() {
    setState(() {
      _assignedBackup = Set.from(_assignedCollectionIds);
      _editing = true;
      _editCtrl.text = _markdown ?? '';
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _assignedCollectionIds
        ..clear()
        ..addAll(_assignedBackup);
      _editCtrl.text = _markdown ?? '';
    });
  }

  Future<void> _save() async {
    final v = _version;
    final app = AppScope.of(context);
    final c = _client();
    if (c == null || v == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
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
        _version = updated.version;
        _assignedCollectionIds
          ..clear()
          ..addAll(updated.collectionIds);
        _trashedAt = updated.trashedAt;
        _editing = false;
        _saving = false;
      });
      app.bumpNotesListRevision();
      messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _moveToTrash() async {
    final app = AppScope.of(context);
    final c = _client();
    final messenger = ScaffoldMessenger.of(context);
    if (c == null) return;
    try {
      await c.trashNote(widget.noteId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      app.bumpNotesListRevision();
      messenger.showSnackBar(
        const SnackBar(content: Text('Note moved to trash.')),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _restore() async {
    final app = AppScope.of(context);
    final c = _client();
    final messenger = ScaffoldMessenger.of(context);
    if (c == null) return;
    try {
      await c.restoreNote(widget.noteId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      app.bumpNotesListRevision();
      messenger.showSnackBar(const SnackBar(content: Text('Note restored.')));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _confirmTrash() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to trash?'),
        content: const Text(
          'You can restore trashed notes later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trash'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _moveToTrash();
  }

  Future<void> _confirmDeleteForever() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
          'This cannot be undone (Mem hard-delete).',
        ),
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
    if (ok != true || !mounted) return;
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final c = _client();
    if (c == null) return;
    try {
      await c.deleteNoteHard(widget.noteId);
      if (!mounted) return;
      app.bumpNotesListRevision();
      messenger.showSnackBar(
        const SnackBar(content: Text('Note permanently deleted.')),
      );
      nav.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  String _collectionTitle(String id) {
    for (final c in _collections) {
      if (c.id == id) return c.title;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final inTrash = _trashedAt != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleText ?? 'Note'),
        actions: [
          if (!inTrash && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _beginEdit,
            ),
          if (_editing)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          if (_editing)
            TextButton(
              onPressed: _saving ? null : _cancelEdit,
              child: const Text('Cancel'),
            ),
          if (!inTrash && !_editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Move to trash',
              onPressed: _confirmTrash,
            ),
          if (inTrash)
            TextButton(
              onPressed: _restore,
              child: const Text('Restore'),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _confirmDeleteForever();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete permanently…'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!),
            ))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!_editing && _assignedCollectionIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Collections',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _assignedCollectionIds
                              .map(
                                (id) => Chip(
                                  label: Text(_collectionTitle(id)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                if (_editing && _collections.isNotEmpty) ...[
                  Text(
                    'Collections',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _collections.map((col) {
                      final on = _assignedCollectionIds.contains(col.id);
                      return FilterChip(
                        label: Text(col.title),
                        selected: on,
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _assignedCollectionIds.add(col.id);
                            } else {
                              _assignedCollectionIds.remove(col.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Markdown',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                ],
                if (_editing)
                  TextField(
                    controller: _editCtrl,
                    maxLines: null,
                    minLines: 16,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'First line becomes the title',
                    ),
                  )
                else
                  Markdown(
                    data: _markdown ?? '',
                    selectable: true,
                    shrinkWrap: true,
                  ),
              ],
            ),
    );
  }
}
