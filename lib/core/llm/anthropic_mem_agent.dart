import 'dart:convert';

import 'package:dio/dio.dart';

import 'anthropic_sse_events.dart';
import 'anthropic_stream_round.dart';
import 'mem_tool_definitions.dart';
import 'mem_tool_runner.dart';

/// Anthropic Messages API with Mem tools. Uses SSE streaming (`stream: true`)
/// with non-streaming fallback on transport errors.
///
/// SSE format: https://docs.claude.com/en/api/messages-streaming
class AnthropicMemAgent {
  AnthropicMemAgent({
    required this.apiKey,
    required this.model,
    required this.runner,
  });

  final String apiKey;
  final String model;
  final MemToolRunner runner;
  String? _resolvedModel;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(minutes: 10),
      headers: {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        'x-api-key': apiKey,
      },
    ),
  );

  Future<({String reply, List<Map<String, dynamic>> anthropicHistory})>
  runConversation({
    String? system,
    required List<Map<String, dynamic>> priorAnthropicMessages,
    required String userText,
    int maxTurns = 8,
    Future<void> Function(String accumulated)? onAssistantTextDelta,
  }) async {
    final modelId = await _resolveModelForRequest();
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
      late final List<Map<String, dynamic>> assistantBlocks;
      try {
        assistantBlocks = await _oneRoundStreaming(
          messages,
          tools,
          system,
          modelId,
          onAssistantTextDelta,
        );
      } on DioException catch (_) {
        assistantBlocks =
            await _oneRoundNonStreaming(messages, tools, system, modelId);
      }

      messages.add({'role': 'assistant', 'content': assistantBlocks});

      final toolUses =
          assistantBlocks.where((b) => b['type'] == 'tool_use').toList();

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

  Future<List<Map<String, dynamic>>> _oneRoundStreaming(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
    String? system,
    String modelId,
    Future<void> Function(String accumulated)? onText,
  ) async {
    final acc = AnthropicStreamRoundAccumulator();
    final sse =
        AnthropicSseSink((Map<String, dynamic> m) => acc.ingestEvent(m));

    var lastEmittedVisibleLen = -1;

    Future<void> emitVisible() async {
      if (onText == null) return;
      final visible = acc.userVisibleText();
      if (visible.length <= lastEmittedVisibleLen) return;
      lastEmittedVisibleLen = visible.length;
      await onText(visible.isEmpty ? '…' : visible);
    }

    final res = await _dio.post<ResponseBody>(
      _endpoint,
      options: Options(
        responseType: ResponseType.stream,
      ),
      data: {
        'model': modelId,
        'max_tokens': 4096,
        if (system != null && system.isNotEmpty) 'system': system,
        'messages': messages,
        'tools': tools,
        'stream': true,
      },
    );

    final rb = res.data;
    if (rb == null) {
      throw StateError('Anthropic streaming: empty body');
    }

    await for (
      final line in rb.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
    ) {
      sse.addLine(line);
      await emitVisible();
    }
    sse.close();
    await emitVisible();

    return acc.assistantContentBlocks();
  }

  Future<List<Map<String, dynamic>>> _oneRoundNonStreaming(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
    String? system,
    String modelId,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      _endpoint,
      data: {
        'model': modelId,
        'max_tokens': 4096,
        if (system != null && system.isNotEmpty) 'system': system,
        'messages': messages,
        'tools': tools,
      },
    );

    final content = res.data?['content'] as List<dynamic>? ?? [];
    return [
      for (final b in content) Map<String, dynamic>.from(b as Map),
    ];
  }

  Future<String> _resolveModelForRequest() async {
    if (_resolvedModel != null && _resolvedModel!.isNotEmpty) {
      return _resolvedModel!;
    }
    final requested = model.trim();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://api.anthropic.com/v1/models',
        queryParameters: {'limit': 200},
      );
      final data = res.data?['data'] as List<dynamic>? ?? const [];
      final ids = <String>{
        for (final e in data)
          if (e is Map<String, dynamic>) (e['id'] as String? ?? '').trim(),
      }..remove('');
      if (ids.isEmpty) {
        _resolvedModel = requested;
        return requested;
      }
      if (ids.contains(requested)) {
        _resolvedModel = requested;
        return requested;
      }
      final preferred = <String>[
        'claude-sonnet-4-6',
        'claude-opus-4-7',
        'claude-haiku-4-5-20251001',
        'claude-3-7-sonnet-20250219',
      ];
      for (final p in preferred) {
        if (ids.contains(p)) {
          _resolvedModel = p;
          return p;
        }
      }
      final first = ids.first;
      _resolvedModel = first;
      return first;
    } catch (_) {
      _resolvedModel = requested;
      return requested;
    }
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
