import 'dart:io';

import 'package:flutter_appauth/flutter_appauth.dart';

import '../config/mem_endpoints.dart';
import '../security/secure_vault.dart';
import 'mcp_dynamic_registration.dart';

/// Thrown when the MCP sign-in flow is invoked on a platform that has no
/// `flutter_appauth` implementation.
///
/// It is deliberately **not** a `PlatformException` and not a
/// `FlutterAppAuthUserCancelledException`, so it falls to the generic branch of
/// the Settings OAuth error taxonomy (CONSTRAINTS.md), which reports
/// `toString()` verbatim — hence [toString] is written as user-facing copy
/// rather than as a debug string.
class McpOAuthUnsupportedPlatformException implements Exception {
  const McpOAuthUnsupportedPlatformException();

  @override
  String toString() => MemMcpOAuth.unsupportedMessage;
}

/// Mem-hosted OAuth for MCP using **Chrome Custom Tabs** (`flutter_appauth`).
///
/// Google blocks sign-in inside embedded **WebViews** (`403 disallowed_useragent`);
/// Custom Tabs use a real browser profile and comply with Google’s policy.
///
/// **Redirect scheme must be RFC 3986–legal** (no `_` in the scheme; use
/// `com.memai.memaiandroid`, not `com.memai.memai_android`).
///
/// **Platform support.** `flutter_appauth` ships android, ios and macos
/// implementations only. Flutter omits an unsupported plugin from the generated
/// registrant rather than failing the build, so on windows and linux the calls
/// below would reach a dead method channel and throw a raw
/// `MissingPluginException` at runtime. [isSupported] is the one place that
/// fact is encoded; every entry point that touches the plugin consults it.
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

  /// The one sentence shown wherever MCP sign-in cannot run. It names the
  /// working alternative — the Mem REST API key — because the app is fully
  /// usable without MCP.
  static const unsupportedMessage =
      'Mem MCP sign-in is not available on this platform. '
      'Use your Mem API key instead.';

  /// Whether this platform can run the OAuth flow at all.
  ///
  /// The single capability check for the whole MCP OAuth path — callers ask
  /// this rather than testing [Platform] themselves.
  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

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
    // Checked before the dynamic registration round-trip, so an unsupported
    // platform never registers a client it could not use anyway.
    if (!isSupported) throw const McpOAuthUnsupportedPlatformException();

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
    // A silent no-op, not a throw: this runs on every chat send, and a platform
    // that cannot sign in has no token to refresh. Chat already falls back to
    // the REST path when `mcpConnected` is false.
    if (!isSupported) return;

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
