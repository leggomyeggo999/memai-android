import 'dart:convert';

import 'package:dio/dio.dart';

import 'mem_tool_definitions.dart';
import 'mem_tool_runner.dart';

/// Runs OpenAI Chat Completions with Mem tool calls (function calling).
class OpenAiMemAgent {
  OpenAiMemAgent({
    required this.apiKey,
    required this.model,
    required this.runner,
  });

  final String apiKey;
  final String model;
  final MemToolRunner runner;

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 120),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// Multi-turn agentic loop with tools (max [maxTurns] completion calls).
  /// Returns the assistant text and the **complete** OpenAI-format history
  /// (including tool messages) so callers can persist context for the next turn.
  Future<({String reply, List<Map<String, dynamic>> openAiHistory})> runConversation({
    required List<Map<String, dynamic>> priorOpenAiMessages,
    required String userText,
    int maxTurns = 8,
  }) async {
    final messages = <Map<String, dynamic>>[
      ...priorOpenAiMessages,
      {'role': 'user', 'content': userText},
    ];

    final tools = memToolSpecifications();

    for (var turn = 0; turn < maxTurns; turn++) {
      final res = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
        data: {
          'model': model,
          'messages': messages,
          'tools': tools,
          'tool_choice': 'auto',
        },
      );

      final choice = res.data?['choices']?[0]?['message'];
      if (choice is! Map<String, dynamic>) {
        throw StateError('OpenAI: missing choices[0].message');
      }

      messages.add(Map<String, dynamic>.from(choice));

      final toolCalls = choice['tool_calls'] as List<dynamic>?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        for (final tc in toolCalls) {
          final m = tc as Map<String, dynamic>;
          final id = m['id'] as String;
          final fn = m['function'] as Map<String, dynamic>;
          final name = fn['name'] as String;
          final rawArgs = fn['arguments'];
          final args = rawArgs is String
              ? jsonDecode(rawArgs) as Map<String, dynamic>
              : Map<String, dynamic>.from(rawArgs as Map);

          final output = await runner.run(name, args);
          messages.add({
            'role': 'tool',
            'tool_call_id': id,
            'content': output,
          });
        }
        continue;
      }

      final text = choice['content'] as String?;
      if (text != null && text.isNotEmpty) {
        return (reply: text, openAiHistory: messages);
      }

      throw StateError('OpenAI: empty assistant message with no tools');
    }

    throw StateError('OpenAI: exceeded max tool turns ($maxTurns)');
  }
}
