import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../app_scope.dart';
import '../../core/mem/mem_api_client.dart';

class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  String? _markdown;
  String? _titleText;
  String? _error;
  bool _loading = true;
  DateTime? _trashedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      setState(() {
        _markdown = note.content;
        _titleText = note.title;
        _trashedAt = note.trashedAt;
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

  Future<void> _moveToTrash() async {
    final c = _client();
    final messenger = ScaffoldMessenger.of(context);
    if (c == null) return;
    try {
      await c.trashNote(widget.noteId);
      if (mounted) {
        await _load();
        messenger.showSnackBar(
          const SnackBar(content: Text('Note moved to trash.')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _restore() async {
    final c = _client();
    final messenger = ScaffoldMessenger.of(context);
    if (c == null) return;
    try {
      await c.restoreNote(widget.noteId);
      if (mounted) {
        await _load();
        messenger.showSnackBar(const SnackBar(content: Text('Note restored.')));
      }
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
          'You can restore trashed notes later from search or tools.',
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
    final c = _client();
    if (c == null) return;
    try {
      await c.deleteNoteHard(widget.noteId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note permanently deleted.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inTrash = _trashedAt != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleText ?? 'Note'),
        actions: [
          if (!inTrash)
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
          ? Center(child: Text(_error!))
          : Markdown(
              data: _markdown ?? '',
              selectable: true,
              padding: const EdgeInsets.all(20),
            ),
    );
  }
}
