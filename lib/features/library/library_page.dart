import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../widgets/settings_launcher.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';
import '../note/note_detail_page.dart';

/// Collections-first library: tap a folder to see only linked notes.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<MemCollectionItem> _cols = [];
  String? _error;
  bool _loading = false;

  MemApiClient? _client(BuildContext context) {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  Future<void> _load() async {
    final c = _client(context);
    if (c == null) {
      setState(() => _error = 'Add your Mem API key in Settings.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await c.listCollections(limit: 100);
      setState(() {
        _cols = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: settingsIconActions(context),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: !_loading && !app.hasMemRest
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Collections use the same Mem REST API key as Pulse.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : _loading && _cols.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [Center(child: Text(_error!))],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _cols.length,
                itemBuilder: (context, i) {
                  final c = _cols[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Material(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _CollectionNotesScreen(
                                title: c.title,
                                collectionId: c.id,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    if (c.description != null &&
                                        c.description!.isNotEmpty)
                                      Text(
                                        c.description!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              Text('${c.noteCount} notes'),
                            ],
                          ),
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

class _CollectionNotesScreen extends StatefulWidget {
  const _CollectionNotesScreen({
    required this.title,
    required this.collectionId,
  });

  final String title;
  final String collectionId;

  @override
  State<_CollectionNotesScreen> createState() => _CollectionNotesScreenState();
}

class _CollectionNotesScreenState extends State<_CollectionNotesScreen> {
  final List<MemNoteListItem> _items = [];
  String? _next;
  bool _loading = false;

  Future<void> _load({bool first = true}) async {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null) return;
    final c = MemApiClient(apiKey: k);
    setState(() => _loading = true);
    try {
      final raw = await c.rawListNotes(
        limit: 40,
        page: first ? null : _next,
        collectionId: widget.collectionId,
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
      final n = raw['next_page'];
      setState(() {
        if (first) {
          _items
            ..clear()
            ..addAll(parsed);
        } else {
          _items.addAll(parsed);
        }
        _next = n is String ? n : null;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
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
      appBar: AppBar(title: Text(widget.title)),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _items.length + (_next != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return TextButton(
              onPressed: _loading ? null : () => _load(first: false),
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Load more'),
            );
          }
          final n = _items[i];
          final time = DateFormat.jm().format(n.updatedAt.toLocal());
          return ListTile(
            title: Text(n.title),
            subtitle: n.snippet != null ? Text(n.snippet!) : null,
            trailing: Text(time),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NoteDetailPage(noteId: n.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
