import 'dart:convert';

import 'package:dio/dio.dart';

import 'mem_tool_definitions.dart';
import 'mem_tool_runner.dart';
import 'openai_stream_accumulator.dart';

/// Runs OpenAI Chat Completions with Mem tool calls.
///
/// Uses **SSE streaming** (`stream: true`) so the UI can render assistant
/// tokens as they arrive. Tool rounds still run full server-side tool execution
/// between streamed completions.
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
      receiveTimeout: const Duration(seconds: 180),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// Multi-turn loop; [onAssistantTextDelta] receives growing text for the
  /// **final assistant reply** segments that are plain text (no tools).
  Future<({String reply, List<Map<String, dynamic>> openAiHistory})> runConversation({
    required List<Map<String, dynamic>> priorOpenAiMessages,
    required String userText,
    int maxTurns = 8,
    Future<void> Function(String accumulated)? onAssistantTextDelta,
  }) async {
    final messages = <Map<String, dynamic>>[
      ...priorOpenAiMessages,
      {'role': 'user', 'content': userText},
    ];

    final tools = memToolSpecifications();

    for (var turn = 0; turn < maxTurns; turn++) {
      Map<String, dynamic> choice;
      try {
        choice = await _completeOneRound(
          messages,
          tools,
          textTurnCallback: onAssistantTextDelta,
        );
      } on DioException catch (_) {
        choice = await _completeOneRoundNonStreaming(messages, tools);
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

  Future<Map<String, dynamic>> _completeOneRound(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools, {
    Future<void> Function(String accumulated)? textTurnCallback,
  }) async {
    final res = await _dio.post<ResponseBody>(
      _endpoint,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'text/event-stream',
        },
      ),
      data: {
        'model': model,
        'messages': messages,
        'tools': tools,
        'tool_choice': 'auto',
        'stream': true,
      },
    );

    final body = res.data;
    if (body == null) {
      throw StateError('OpenAI: empty stream body');
    }

    final acc = OpenAiStreamAccumulator();
    var lastEmittedLen = 0;

    await for (final line in body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      acc.acceptLine(line);
      if (textTurnCallback != null &&
          !acc.sawToolDelta &&
          acc.textSoFar.length > lastEmittedLen) {
        lastEmittedLen = acc.textSoFar.length;
        await textTurnCallback(acc.textSoFar);
      }
    }

    return acc.buildAssistantMessage();
  }

  /// Non-streaming fallback if the SSE request fails (network / proxy).
  Future<Map<String, dynamic>> _completeOneRoundNonStreaming(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _endpoint,
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
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
    return Map<String, dynamic>.from(choice);
  }
}
