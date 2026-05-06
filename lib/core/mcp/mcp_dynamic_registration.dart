import 'package:dio/dio.dart';

import '../config/mem_endpoints.dart';

/// RFC 7591 dynamic client registration against Mem (`/oauth2/register`).
///
/// The redirect URI **must** stay in sync with:
/// - `android/app/build.gradle.kts` `appAuthRedirectScheme`
/// - The `redirectUrl` passed to `flutter_appauth`
///
/// Format: `{scheme}://oauth` — e.g. `com.memai.memai_android://oauth`
class McpDynamicRegistration {
  McpDynamicRegistration({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: MemEndpoints.apiBase,
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;

  /// Returns the `client_id` issued by Mem for this install.
  Future<String> registerPublicClient({
    required String redirectUri,
    String clientName = 'Mem AI Android',
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      MemEndpoints.oauthRegisterPath,
      data: {
        'redirect_uris': [redirectUri],
        'client_name': clientName,
        'token_endpoint_auth_method': 'none',
        'grant_types': ['authorization_code'],
        'response_types': ['code'],
      },
    );
    final id = res.data?['client_id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('register response missing client_id');
    }
    return id;
  }
}
