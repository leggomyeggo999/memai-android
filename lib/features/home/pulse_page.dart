import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../widgets/settings_launcher.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mem/mem_models.dart';
import '../note/note_detail_page.dart';

/// Mobile-first **Pulse**: one column, grouped by calendar day, optimized for
/// thumb reach — not a three-column web clone.
class PulsePage extends StatefulWidget {
  const PulsePage({super.key});

  @override
  State<PulsePage> createState() => _PulsePageState();
}

class _PulsePageState extends State<PulsePage> {
  final List<MemNoteListItem> _items = [];
  String? _nextPage;
  bool _loading = false;
  String? _error;

  MemApiClient? _client(BuildContext context) {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  Future<void> _load({bool refresh = false}) async {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(refresh: true));
  }

  Map<String, List<MemNoteListItem>> _group() {
    final map = <String, List<MemNoteListItem>>{};
    for (final n in _items) {
      final key = DateFormat.yMMMEd().format(n.updatedAt.toLocal());
      map.putIfAbsent(key, () => []).add(n);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulse'),
        actions: settingsIconActions(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _body(app),
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
              'Connect Mem with your API key from Mem Settings → API to see your knowledge timeline.',
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
            onPressed: _loading ? null : () => _load(),
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
                  Icons.bubble_chart_outlined,
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
