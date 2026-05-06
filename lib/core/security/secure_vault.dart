import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android: keys are stored in the encrypted shared preferences / Keystore-backed
/// implementation provided by [FlutterSecureStorage] (see package docs).
///
/// **Do not log secret values.** The app only exposes booleans like
/// "hasApiKey" in the UI layer.
class SecureVault {
  SecureVault({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // --- Mem REST API (user copies from Mem settings → API)
  static const _memApiKey = 'mem.rest_api_key';

  // --- Dynamic OAuth client (RFC 7591 register at Mem `oauth2/register`)
  static const _mcpClientId = 'mem.mcp.client_id';

  // --- OAuth tokens for MCP HTTP transport (`Authorization: Bearer`)
  static const _mcpAccess = 'mem.mcp.access_token';
  static const _mcpRefresh = 'mem.mcp.refresh_token';
  static const _mcpExpiry =
      'mem.mcp.access_expiry_epoch_ms'; // parsed as int string

  // --- Chat model profiles (JSON list, no secrets)
  static const _chatProfilesMeta = 'chat.profiles_meta_json';

  // --- Per-profile API keys for external LLMs
  static String _llmKeySlot(String profileId) => 'chat.llm_key.$profileId';

  Future<void> setMemApiKey(String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _memApiKey);
    } else {
      await _storage.write(key: _memApiKey, value: value);
    }
  }

  Future<String?> getMemApiKey() => _storage.read(key: _memApiKey);

  Future<void> setMcpOAuthBundle({
    required String clientId,
    required String accessToken,
    required String refreshToken,
    required DateTime accessExpiry,
  }) async {
    await _storage.write(key: _mcpClientId, value: clientId);
    await _storage.write(key: _mcpAccess, value: accessToken);
    await _storage.write(key: _mcpRefresh, value: refreshToken);
    await _storage.write(
      key: _mcpExpiry,
      value: accessExpiry.millisecondsSinceEpoch.toString(),
    );
  }

  /// Clears OAuth tokens only; keeps dynamically registered `client_id` so the
  /// next sign-in reuses the same Mem client registration when possible.
  Future<void> clearMcpOAuth() async {
    await _storage.delete(key: _mcpAccess);
    await _storage.delete(key: _mcpRefresh);
    await _storage.delete(key: _mcpExpiry);
  }

  Future<void> setMcpClientId(String clientId) async {
    await _storage.write(key: _mcpClientId, value: clientId);
  }

  Future<String?> getMcpClientId() => _storage.read(key: _mcpClientId);
  Future<String?> getMcpAccessToken() => _storage.read(key: _mcpAccess);
  Future<String?> getMcpRefreshToken() => _storage.read(key: _mcpRefresh);

  Future<DateTime?> getMcpAccessExpiry() async {
    final raw = await _storage.read(key: _mcpExpiry);
    if (raw == null) return null;
    final ms = int.tryParse(raw);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setChatProfilesMetaJson(String json) async {
    await _storage.write(key: _chatProfilesMeta, value: json);
  }

  Future<String?> getChatProfilesMetaJson() =>
      _storage.read(key: _chatProfilesMeta);

  Future<void> setLlmApiKey(String profileId, String? key) async {
    final k = _llmKeySlot(profileId);
    if (key == null || key.isEmpty) {
      await _storage.delete(key: k);
    } else {
      await _storage.write(key: k, value: key);
    }
  }

  Future<String?> getLlmApiKey(String profileId) =>
      _storage.read(key: _llmKeySlot(profileId));
}
