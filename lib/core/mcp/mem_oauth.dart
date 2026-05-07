import 'package:flutter_appauth/flutter_appauth.dart';

import '../config/mem_endpoints.dart';
import '../security/secure_vault.dart';
import 'mcp_dynamic_registration.dart';

/// Mem-hosted OAuth for MCP using **Chrome Custom Tabs** (`flutter_appauth`).
///
/// Google blocks sign-in inside embedded **WebViews** (`403 disallowed_useragent`);
/// Custom Tabs use a real browser profile and comply with Google’s policy.
///
/// **Redirect scheme must be RFC 3986–legal** (no `_` in the scheme; use
/// `com.memai.memaiandroid`, not `com.memai.memai_android`).
class MemMcpOAuth {
  MemMcpOAuth({
    required SecureVault vault,
    FlutterAppAuth? appAuth,
    McpDynamicRegistration? registration,
  }) : _vault = vault,
       _appAuth = appAuth ?? FlutterAppAuth(),
       _registration = registration ?? McpDynamicRegistration();

  static const redirectUrl = 'com.memai.memaiandroid://oauth';
  static const scopes = ['content.read', 'content.write'];

  final SecureVault _vault;
  final FlutterAppAuth _appAuth;
  final McpDynamicRegistration _registration;

  /// Ensures a `client_id` exists (persists in the vault).
  Future<String> ensureRegisteredClientId() async {
    await _vault.ensureMcpRedirectMatchesOrReset(redirectUrl);

    final existing = await _vault.getMcpClientId();
    if (existing != null && existing.isNotEmpty) return existing;

    final id = await _registration.registerPublicClient(
      redirectUri: redirectUrl,
    );
    await _vault.setMcpClientId(id);
    await _vault.setMcpRegisteredRedirectUri(redirectUrl);
    return id;
  }

  Future<void> signInWithMcp() async {
    final clientId = await ensureRegisteredClientId();

    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        redirectUrl,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: MemEndpoints.oauthConsent,
          tokenEndpoint: MemEndpoints.tokenEndpoint,
        ),
        scopes: scopes,
        promptValues: const ['consent'],
      ),
    );

    final access = result.accessToken;
    final refresh = result.refreshToken;
    if (access == null || refresh == null) {
      throw StateError('OAuth result missing access or refresh token');
    }
    final expiry = result.accessTokenExpirationDateTime ?? DateTime.now().add(
      const Duration(minutes: 50),
    );
    await _vault.setMcpOAuthBundle(
      clientId: clientId,
      accessToken: access,
      refreshToken: refresh,
      accessExpiry: expiry,
    );
    await _vault.setMcpRegisteredRedirectUri(redirectUrl);
  }

  Future<void> signOutMcp() => _vault.clearMcpOAuth();

  Future<void> refreshIfNeeded() async {
    await _vault.ensureMcpRedirectMatchesOrReset(redirectUrl);
    final refresh = await _vault.getMcpRefreshToken();
    final clientId = await _vault.getMcpClientId();
    if (refresh == null || clientId == null) return;

    final exp = await _vault.getMcpAccessExpiry();
    if (exp != null && exp.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return;
    }

    final res = await _appAuth.token(
      TokenRequest(
        clientId,
        redirectUrl,
        refreshToken: refresh,
        scopes: scopes,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: MemEndpoints.oauthConsent,
          tokenEndpoint: MemEndpoints.tokenEndpoint,
        ),
      ),
    );
    final access = res.accessToken;
    final newRefresh = res.refreshToken ?? refresh;
    if (access == null) {
      throw StateError('Token refresh failed');
    }
    final expiry = res.accessTokenExpirationDateTime ?? DateTime.now().add(
      const Duration(minutes: 50),
    );
    await _vault.setMcpOAuthBundle(
      clientId: clientId,
      accessToken: access,
      refreshToken: newRefresh,
      accessExpiry: expiry,
    );
    await _vault.setMcpRegisteredRedirectUri(redirectUrl);
  }
}
