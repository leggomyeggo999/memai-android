import 'package:dio/dio.dart';

import 'mem_tool_definitions.dart';
import 'mem_tool_runner.dart';

/// Anthropic Messages API with Mem tool use (tool_use / tool_result blocks).
class AnthropicMemAgent {
  AnthropicMemAgent({
    required this.apiKey,
    required this.model,
    required this.runner,
  });

  final String apiKey;
  final String model;
  final MemToolRunner runner;


  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 120),
      headers: {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        'x-api-key': apiKey,
      },
    ),
  );

  Future<({String reply, List<Map<String, dynamic>> anthropicHistory})> runConversation({
    String? system,
    required List<Map<String, dynamic>> priorAnthropicMessages,
    required String userText,
    int maxTurns = 8,
  }) async {
    final messages = <Map<String, dynamic>>[
      ...priorAnthropicMessages,
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': userText},
        ],
      },
    ];

    final tools = _anthropicTools();

    for (var turn = 0; turn < maxTurns; turn++) {
      final res = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: {
          'model': model,
          'max_tokens': 4096,
          if (system != null && system.isNotEmpty) 'system': system,
          'messages': messages,
          'tools': tools,
        },
      );

      final content = res.data?['content'] as List<dynamic>? ?? [];
      final assistantBlocks = <Map<String, dynamic>>[];
      for (final b in content) {
        assistantBlocks.add(Map<String, dynamic>.from(b as Map));
      }

      messages.add({'role': 'assistant', 'content': assistantBlocks});

      final toolUses = assistantBlocks
          .where((b) => b['type'] == 'tool_use')
          .toList();

      if (toolUses.isNotEmpty) {
        final results = <Map<String, dynamic>>[];
        for (final tu in toolUses) {
          final id = tu['id'] as String;
          final name = tu['name'] as String;
          final input = Map<String, dynamic>.from(tu['input'] as Map);
          final out = await runner.run(name, input);
          results.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'content': out,
          });
        }
        messages.add({'role': 'user', 'content': results});
        continue;
      }

      String? textOut;
      for (final b in assistantBlocks) {
        if (b['type'] == 'text') {
          textOut = (textOut ?? '') + (b['text'] as String? ?? '');
        }
      }
      if (textOut != null && textOut.isNotEmpty) {
        return (reply: textOut, anthropicHistory: messages);
      }
      throw StateError('Anthropic: no text and no tools in response');
    }
    throw StateError('Anthropic: exceeded max tool turns ($maxTurns)');
  }

  List<Map<String, dynamic>> _anthropicTools() {
    final openai = memToolSpecifications();
    return [
      for (final t in openai)
        {
          'name': t['function']['name'],
          'description': t['function']['description'],
          'input_schema': t['function']['parameters'],
        },
    ];
  }
}
