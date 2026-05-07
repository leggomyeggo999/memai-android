import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';

/// Create, rename, describe, or delete collections (Mem folders).
class CollectionsManagePage extends StatefulWidget {
  const CollectionsManagePage({super.key});

  @override
  State<CollectionsManagePage> createState() => _CollectionsManagePageState();
}

class _CollectionsManagePageState extends State<CollectionsManagePage> {
  List<MemCollectionItem> _items = [];
  String? _error;
  bool _loading = true;

  MemApiClient? _client() {
    final k = AppScope.of(context).memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  Future<void> _load() async {
    final c = _client();
    if (c == null) {
      setState(() {
        _error = 'Missing API key.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await c.listCollections(limit: 100);
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _upsertSheet({MemCollectionItem? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CollectionEditorSheet(
        existing: existing,
        resolveClient: _client,
        onSaved: () async {
          final app = AppScope.of(context);
          await _load();
          if (!mounted) return;
          app.bumpNotesListRevision();
        },
      ),
    );
  }

  Future<void> _confirmDelete(MemCollectionItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete collection?'),
        content: Text(
          '“${item.title}” will be removed. Notes stay in your library; '
          'only the folder is deleted.',
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
    final c = _client();
    if (c == null) return;
    try {
      await c.deleteCollection(item.id);
      await _load();
      if (!mounted) return;
      app.bumpNotesListRevision();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collection deleted.')),
        );
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _upsertSheet(),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final item = _items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Material(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Icon(
                          Icons.folder_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(item.title),
                        subtitle: item.description != null &&
                                item.description!.isNotEmpty
                            ? Text(
                                item.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            : Text(
                                '${item.noteCount} notes',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _upsertSheet(existing: item);
                            if (v == 'delete') _confirmDelete(item);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _CollectionEditorSheet extends StatefulWidget {
  const _CollectionEditorSheet({
    required this.existing,
    required this.resolveClient,
    required this.onSaved,
  });

  final MemCollectionItem? existing;
  final MemApiClient? Function() resolveClient;
  final Future<void> Function() onSaved;

  @override
  State<_CollectionEditorSheet> createState() => _CollectionEditorSheetState();
}

class _CollectionEditorSheetState extends State<_CollectionEditorSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _descCtrl =
        TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext sheetContext) async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _saving) return;
    final desc = _descCtrl.text.trim();
    final c = widget.resolveClient();
    if (c == null) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await c.createCollection(
          title: title,
          description: desc.isEmpty ? null : desc,
        );
      } else {
        await c.updateCollection(
          collectionId: existing.id,
          title: title,
          description: desc,
        );
      }
      if (!sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      await widget.onSaved();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'Collection created.' : 'Saved.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              existing == null ? 'New collection' : 'Edit collection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : () => _save(context),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
