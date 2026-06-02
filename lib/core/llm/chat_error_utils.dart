import 'package:dio/dio.dart';

import 'chat_model_profile.dart';
import 'curated_chat_models.dart';
import '../telemetry/mem_error_reporter.dart';

/// User-facing chat/API error text plus optional telemetry.
class ChatErrorDetails {
  const ChatErrorDetails({
    required this.userMessage,
    this.httpStatus,
    this.provider,
  });

  final String userMessage;
  final int? httpStatus;
  final String? provider;
}

ChatErrorDetails formatChatError(
  Object error, {
  required ChatModelProfile profile,
  String context = 'chat',
}) {
  if (error is DioException) {
    final code = error.response?.statusCode;
    MemErrorReporter.report(
      message: error.message ?? 'DioException',
      context: context,
      provider: profile.provider,
      httpStatus: code,
      endpoint: error.requestOptions.uri.path,
      extra: MemErrorReporter.dioDetails(error),
    );

    final bodyMsg = _extractApiMessage(error);
    if (code == 401 || code == 403) {
      return ChatErrorDetails(
        userMessage:
            '${chatProviderBrand(profile.provider)} rejected your API key (HTTP $code). '
            'Check Settings → Chat models.',
        httpStatus: code,
        provider: profile.provider,
      );
    }
    if (code == 404) {
      return ChatErrorDetails(
        userMessage:
            '${chatProviderBrand(profile.provider)} returned 404. '
            'Model "${profile.model}" may be unavailable — pick another in Settings.',
        httpStatus: code,
        provider: profile.provider,
      );
    }
    if (code == 429) {
      return ChatErrorDetails(
        userMessage:
            '${chatProviderBrand(profile.provider)} rate-limited this request (HTTP 429). '
            'Wait a moment and try again.',
        httpStatus: code,
        provider: profile.provider,
      );
    }
    if (bodyMsg != null && bodyMsg.isNotEmpty) {
      return ChatErrorDetails(
        userMessage:
            '${chatProviderBrand(profile.provider)} error (HTTP ${code ?? "?"}): $bodyMsg',
        httpStatus: code,
        provider: profile.provider,
      );
    }
    return ChatErrorDetails(
      userMessage:
          '${chatProviderBrand(profile.provider)} network error: ${error.message ?? "unknown"} '
          '(HTTP ${code ?? "?"})',
      httpStatus: code,
      provider: profile.provider,
    );
  }

  MemErrorReporter.report(
    message: error.toString(),
    context: context,
    provider: profile.provider,
  );

  if (error is StateError) {
    return ChatErrorDetails(
      userMessage: error.message,
      provider: profile.provider,
    );
  }

  return ChatErrorDetails(
    userMessage: error.toString(),
    provider: profile.provider,
  );
}

String? _extractApiMessage(DioException e) {
  final data = e.response?.data;
  if (data == null) return null;
  if (data is Map) {
    final err = data['error'];
    if (err is Map) {
      final m = err['message'];
      if (m is String && m.isNotEmpty) return m;
    }
    final m = data['message'];
    if (m is String && m.isNotEmpty) return m;
  }
  if (data is String && data.length < 500) return data;
  return null;
}
