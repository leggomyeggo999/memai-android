import 'dart:io';

import 'package:dio/dio.dart';

class OpenAiWhisperClient {
  OpenAiWhisperClient({required this.apiKey, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.openai.com',
                headers: {
                  'Authorization': 'Bearer $apiKey',
                  'Accept': 'application/json',
                },
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 120),
              ),
            );

  final String apiKey;
  final Dio _dio;

  Future<String> transcribeFile(
    File file, {
    String model = 'whisper-1',
    String? prompt,
    String? language,
  }) async {
    final form = FormData.fromMap({
      'model': model,
      if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
      if (language != null && language.isNotEmpty) 'language': language,
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.isEmpty
            ? 'capture.m4a'
            : file.uri.pathSegments.last,
      ),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/audio/transcriptions',
      data: form,
    );
    final text = res.data?['text'] as String?;
    if (text == null) {
      throw StateError('Whisper response missing text');
    }
    return text.trim();
  }
}

