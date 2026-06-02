import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Fire-and-forget client error reports to a tiny HTTP endpoint.
///
/// Configure at build time:
/// `--dart-define=MEMDROID_ERROR_REPORT_URL=https://your-worker.workers.dev/report`
/// `--dart-define=MEMDROID_ERROR_REPORT_SECRET=optional-shared-secret`
class MemErrorReporter {
  MemErrorReporter._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  static const _url = String.fromEnvironment('MEMDROID_ERROR_REPORT_URL');
  static const _secret = String.fromEnvironment('MEMDROID_ERROR_REPORT_SECRET');

  static String? _appVersion;
  static bool _initialized = false;

  static bool get isEnabled => _url.trim().isNotEmpty;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
  }

  /// Hooks [FlutterError.onError] and platform dispatcher errors.
  static void installGlobalHandlers() {
    if (!isEnabled) return;
    unawaited(ensureInitialized());

    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      report(
        message: details.exceptionAsString(),
        stack: details.stack?.toString(),
        context: 'flutter_error',
        fatal: true,
      );
      prevFlutter?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      report(
        message: error.toString(),
        stack: stack.toString(),
        context: 'platform_dispatcher',
        fatal: true,
      );
      return false;
    };
  }

  static void report({
    required String message,
    String? stack,
    String? context,
    String? provider,
    int? httpStatus,
    String? endpoint,
    Map<String, dynamic>? extra,
    bool fatal = false,
  }) {
    if (!isEnabled) return;
    unawaited(_post(
      message: message,
      stack: stack,
      context: context,
      provider: provider,
      httpStatus: httpStatus,
      endpoint: endpoint,
      extra: extra,
      fatal: fatal,
    ));
  }

  static Future<void> _post({
    required String message,
    String? stack,
    String? context,
    String? provider,
    int? httpStatus,
    String? endpoint,
    Map<String, dynamic>? extra,
    bool fatal = false,
  }) async {
    await ensureInitialized();
    try {
      final headers = <String, dynamic>{};
      if (_secret.isNotEmpty) {
        headers['X-MemDroid-Secret'] = _secret;
      }
      await _dio.post<void>(
        _url,
        data: {
          'app': 'memdroid',
          'version': _appVersion,
          'message': _clip(message, 4000),
          if (stack != null) 'stack': _clip(stack, 12000),
          if (context != null) 'context': context,
          if (provider != null) 'provider': provider,
          if (httpStatus != null) 'httpStatus': httpStatus,
          if (endpoint != null) 'endpoint': endpoint,
          if (extra != null && extra.isNotEmpty) 'extra': extra,
          'fatal': fatal,
          'ts': DateTime.now().toUtc().toIso8601String(),
        },
        options: Options(headers: headers),
      );
    } catch (_) {
      // Never crash the app because telemetry failed.
    }
  }

  static String _clip(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  /// Extract safe API error details from [DioException] (no secrets).
  static Map<String, dynamic> dioDetails(DioException e) {
    final data = e.response?.data;
    String? bodySnippet;
    if (data != null) {
      try {
        final encoded = data is String ? data : jsonEncode(data);
        bodySnippet = _clip(encoded, 2000);
      } catch (_) {
        bodySnippet = data.toString();
      }
    }
    return {
      'type': e.type.name,
      'status': e.response?.statusCode,
      'uri': e.requestOptions.uri.toString(),
      if (bodySnippet != null) 'body': bodySnippet,
    };
  }
}
