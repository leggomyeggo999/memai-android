import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../widgets/settings_launcher.dart';
import '../../core/mem/mem_api_client.dart';

/// **Fast capture** lane: Mem-it for unstructured drops, or explicit markdown
/// when the user wants a verbatim note.
class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final _bodyCtrl = TextEditingController();
  final _instrCtrl = TextEditingController();
  bool _busy = false;
  String? _feedback;

  MemApiClient? _client(BuildContext context) {
    final app = AppScope.of(context);
    final k = app.memApiKey;
    if (k == null || k.isEmpty) return null;
    return MemApiClient(apiKey: k);
  }

  Future<void> _memIt() async {
    final c = _client(context);
    if (c == null) {
      setState(() => _feedback = 'Add your Mem API key in Settings first.');
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final id = await c.memIt(
        input: _bodyCtrl.text,
        instructions: _instrCtrl.text.trim().isEmpty
            ? null
            : _instrCtrl.text.trim(),
      );
      setState(() {
        _busy = false;
        _feedback = 'Queued for Mem processing (request_id: $id).';
        _bodyCtrl.clear();
        _instrCtrl.clear();
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _feedback = e.toString();
      });
    }
  }

  Future<void> _saveRaw() async {
    final c = _client(context);
    if (c == null) {
      setState(() => _feedback = 'Add your Mem API key in Settings first.');
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final note = await c.createNote(markdown: _bodyCtrl.text);
      setState(() {
        _busy = false;
        _feedback = 'Saved note ${note.id}';
        _bodyCtrl.clear();
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _feedback = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _instrCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture'),
        actions: settingsIconActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Drop text, transcripts, or HTML — Mem-it processes it on the server (see Mem API docs).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyCtrl,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Content',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instrCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Instructions for Mem-it (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _memIt,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Mem-it (smart capture)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _saveRaw,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Save as raw markdown note'),
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 24),
            Text(_feedback!),
          ],
        ],
      ),
    );
  }
}
