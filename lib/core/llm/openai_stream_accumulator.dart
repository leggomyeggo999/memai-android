import 'dart:convert';

/// Accumulates OpenAI Chat Completions **streaming** chunks into either plain
/// assistant text or a `tool_calls` payload matching the non-streaming
/// `choices[0].message` shape.
///
/// See: https://platform.openai.com/docs/api-reference/chat/streaming
class OpenAiStreamAccumulator {
  OpenAiStreamAccumulator();

  final StringBuffer _content = StringBuffer();
  final Map<int, _ToolFrag> _tools = {};
  bool _sawToolDelta = false;

  bool get sawToolDelta => _sawToolDelta;

  String get textSoFar => _content.toString();

  void acceptLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith(':')) return;
    if (!trimmed.startsWith('data:')) return;
    final payload = trimmed.substring(5).trim();
    if (payload == '[DONE]') return;

    final dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return;
    final c0 = choices[0] as Map<String, dynamic>;
    final delta = c0['delta'] as Map<String, dynamic>?;
    if (delta == null) return;

    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      _content.write(content);
    }

    final tcs = delta['tool_calls'] as List<dynamic>?;
    if (tcs != null) {
      _sawToolDelta = true;
      for (final raw in tcs) {
        if (raw is! Map<String, dynamic>) continue;
        final idx = raw['index'] as int? ?? 0;
        final slot = _tools.putIfAbsent(idx, _ToolFrag.new);
        final id = raw['id'];
        if (id is String && id.isNotEmpty) slot.id = id;
        final fn = raw['function'];
        if (fn is Map<String, dynamic>) {
          final name = fn['name'];
          if (name is String && name.isNotEmpty) slot.name = name;
          final arg = fn['arguments'];
          if (arg is String) slot.args.write(arg);
        }
      }
    }
  }

  /// Maps to the JSON-RPC message object OpenAI would return in non-streaming mode.
  Map<String, dynamic> buildAssistantMessage() {
    if (_tools.isNotEmpty) {
      final entries = _tools.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          for (final e in entries)
            {
              'id': e.value.id ?? 'call_missing_id_${e.key}',
              'type': 'function',
              'function': {
                'name': e.value.name ?? '',
                'arguments': e.value.args.toString(),
              },
            },
        ],
      };
    }
    return {
      'role': 'assistant',
      'content': _content.toString(),
    };
  }
}

class _ToolFrag {
  _ToolFrag();

  String? id;
  String? name;
  final StringBuffer args = StringBuffer();
}
