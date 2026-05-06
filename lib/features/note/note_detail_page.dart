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
  String? _error;
  bool _loading = true;

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Note')),
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
