import 'dart:convert';

import 'package:dio/dio.dart';

import 'gemini_stream_round.dart';
import 'mem_tool_definitions.dart';
import 'mem_tool_runner.dart';

/// Google AI Studio / Gemini `generateContent` with Mem tools, SSE streaming
/// (`streamGenerateContent?alt=sse`) and JSON fallback on transport errors.
class GeminiMemAgent {
  GeminiMemAgent({
    required this.apiKey,
    required this.model,
    required this.runner,
  });

  final String apiKey;
  final String model;
  final MemToolRunner runner;

  static const _host = 'https://generativelanguage.googleapis.com';

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(minutes: 10),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
    ),
  );

  String get _modelId {
    var m = model.trim();
    if (m.startsWith('models/')) {
      m = m.substring('models/'.length);
    }
    return m;
  }

  /// Multi-turn loop; Gemini uses `contents` alternating `user` / `model`.
  Future<({String reply, List<Map<String, dynamic>> geminiContents})>
      runConversation({
    required String system,
    required List<Map<String, dynamic>> priorGeminiContents,
    required String userText,
    int maxTurns = 8,
    Future<void> Function(String accumulated)? onAssistantTextDelta,
  }) async {
    final contents = <Map<String, dynamic>>[
      ...priorGeminiContents,
      {
        'role': 'user',
        'parts': [
          {'text': userText},
        ],
      },
    ];

    final tools = [
      {'functionDeclarations': memToolGeminiDeclarations()},
    ];
    final toolConfig = {
      'functionCallingConfig': {
        'mode': 'AUTO',
      },
    };

    for (var turn = 0; turn < maxTurns; turn++) {
      GeminiStreamRoundAccumulator acc;
      try {
        acc = await _completeOneStreamingRound(
          contents,
          system,
          tools,
          toolConfig,
          onAssistantTextDelta,
        );
      } on DioException catch (_) {
        acc = await _completeOneRoundNonStreaming(
          contents,
          system,
          tools,
          toolConfig,
        );
      }

      contents.add(acc.buildModelContentMessage());

      if (acc.hasToolCalls) {
        final responseParts = <Map<String, dynamic>>[];
        for (final inv in acc.toolInvocationsSync()) {
          final out = await runner.run(inv.name, inv.args);
          responseParts.add({
            'functionResponse': {
              'name': inv.name,
              'response': {'result': out},
            },
          });
        }
        contents.add({'role': 'user', 'parts': responseParts});
        continue;
      }

      final text = acc.textSoFar.trim();
      if (text.isNotEmpty) {
        return (reply: text, geminiContents: contents);
      }

      throw StateError('Gemini: empty assistant text with no tools');
    }
    throw StateError('Gemini: exceeded max tool turns ($maxTurns)');
  }

  Future<GeminiStreamRoundAccumulator> _completeOneStreamingRound(
    List<Map<String, dynamic>> contents,
    String system,
    List<Map<String, dynamic>> tools,
    Map<String, dynamic> toolConfig,
    Future<void> Function(String accumulated)? onText,
  ) async {
    final acc = GeminiStreamRoundAccumulator();
    final sse = GeminiSseSink(acc.ingestResponseJson);

    var lastLen = -1;

    Future<void> emit() async {
      if (onText == null || acc.sawFunction) return;
      final s = acc.textSoFar;
      if (s.length <= lastLen) return;
      lastLen = s.length;
      await onText(s.isEmpty ? '…' : s);
    }

    final url =
        '$_host/v1beta/models/$_modelId:streamGenerateContent?alt=sse';

    final res = await _dio.post<ResponseBody>(
      url,
      options: Options(responseType: ResponseType.stream),
      data: {
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': contents,
        'tools': tools,
        'toolConfig': toolConfig,
      },
    );

    final body = res.data;
    if (body == null) throw StateError('Gemini streaming: empty body');

    await for (
      final line in body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
    ) {
      sse.acceptLine(line);
      if (acc.blockReason != null) {
        throw StateError('Gemini blocked: ${acc.blockReason}');
      }
      await emit();
    }
    await emit();

    if (acc.blockReason != null) {
      throw StateError('Gemini blocked: ${acc.blockReason}');
    }

    return acc;
  }

  Future<GeminiStreamRoundAccumulator> _completeOneRoundNonStreaming(
    List<Map<String, dynamic>> contents,
    String system,
    List<Map<String, dynamic>> tools,
    Map<String, dynamic> toolConfig,
  ) async {
    final url = '$_host/v1beta/models/$_modelId:generateContent';
    final map = await _dio.post<Map<String, dynamic>>(
      url,
      data: {
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': contents,
        'tools': tools,
        'toolConfig': toolConfig,
      },
    );
    final json = map.data;
    if (json == null) throw StateError('Gemini: empty JSON response');

    final acc = GeminiStreamRoundAccumulator();
    acc.ingestResponseJson(json);
    if (acc.blockReason != null) {
      throw StateError('Gemini blocked: ${acc.blockReason}');
    }
    return acc;
  }
}
