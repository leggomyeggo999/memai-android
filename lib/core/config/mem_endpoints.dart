/// Canonical Mem platform URLs derived from official docs:
/// - REST: https://docs.mem.ai/api-reference/overview/introduction
/// - MCP: https://docs.mem.ai/mcp/overview
abstract final class MemEndpoints {
  static const apiBase = 'https://api.mem.ai';
  static const mcpEndpoint = 'https://mcp.mem.ai/mcp';
  static const oauthConsent = 'https://mem.ai/oauth/consent';

  /// Per `mcp.mem.ai` WWW-Authenticate and OAuth metadata probes.
  static const tokenEndpoint = 'https://api.mem.ai/api/v2/oauth2/token';
  /// Path-only when [Dio.options.baseUrl] is [apiBase].
  static const oauthRegisterPath = '/oauth2/register';

  /// OAuth protected resource doc for MCP (scopes, issuer).
  static const mcpOAuthProtectedResource =
      'https://mcp.mem.ai/.well-known/oauth-protected-resource';

  /// Align with server responses (see 401 probe headers on `/mcp`).
  static const mcpProtocolVersion = '2025-06-18';

  static const mcpSessionHeader = 'mcp-session-id';
}
