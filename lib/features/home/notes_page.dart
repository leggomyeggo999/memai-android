import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../widgets/settings_launcher.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';
import '../note/note_detail_page.dart';
import 'collections_manage_page.dart';

/// All notes in a scannable timeline, with optional **collection** filter and
/// entry to collection management.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final List<MemNoteListItem> _items = [];
  List<MemCollectionItem> _collections = [];
  String? _nextPage;
  bool _loading = false;
  bool _loadingCols = false;
  String? _error;
  String? _filterCollectionId;

  AppState? _app;

  MemApiClient? _client(BuildContext context) {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  void _onNotesRevision() {
    if (!mounted) return;
    _loadNotes(refresh: true);
    _loadCollections();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (!identical(_app, app)) {
      _app?.notesListRevision.removeListener(_onNotesRevision);
      _app = app;
      _app!.notesListRevision.addListener(_onNotesRevision);
    }
  }

  @override
  void dispose() {
    _app?.notesListRevision.removeListener(_onNotesRevision);
    super.dispose();
  }

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
        if (_filterCollectionId != null &&
            !_collections.any((x) => x.id == _filterCollectionId)) {
          _filterCollectionId = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCols = false);
    }
  }

  Future<void> _loadNotes({bool refresh = false}) async {
    final c = _client(context);
    if (c == null) {
      setState(() => _error = 'Add your Mem API key in Settings.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) {
        _items.clear();
        _nextPage = null;
      }
    });
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
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotes(refresh: true);
      _loadCollections();
    });
  }

  Map<String, List<MemNoteListItem>> _group() {
    final map = <String, List<MemNoteListItem>>{};
    for (final n in _items) {
      final key = DateFormat.yMMMEd().format(n.updatedAt.toLocal());
      map.putIfAbsent(key, () => []).add(n);
    }
    return map;
  }

  void _setFilter(String? collectionId) {
    setState(() => _filterCollectionId = collectionId);
    _loadNotes(refresh: true);
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

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: settingsIconActions(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (app.hasMemRest) _buildFilterBar(context),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadCollections();
                await _loadNotes(refresh: true);
              },
              child: _body(app),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _filterCollectionId == null,
                        onSelected: (_) => _setFilter(null),
                      ),
                    ),
                    ..._collections.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(
                            c.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: _filterCollectionId == c.id,
                          onSelected: (_) => _setFilter(c.id),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loadingCols)
              const SizedBox(
                height: 20,
                width: 20,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: 'Manage collections',
                icon: const Icon(Icons.collections_bookmark_outlined),
                onPressed: _openManageCollections,
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(AppState app) {
    if (!app.hasMemRest) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Add your Mem API key in Settings to see and edit your notes.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
        ],
      );
    }
    final groups = _group();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        if (_loading && _items.isEmpty) const LinearProgressIndicator(),
        ...groups.entries.expand((e) {
          return [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                e.key.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...e.value.map((n) => _NoteCard(note: n)),
          ];
        }),
        if (_nextPage != null)
          TextButton(
            onPressed: _loading ? null : () => _loadNotes(),
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Load more'),
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final MemNoteListItem note;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.jm().format(note.updatedAt.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NoteDetailPage(noteId: note.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.article_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (note.snippet != null && note.snippet!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            note.snippet!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  time,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
