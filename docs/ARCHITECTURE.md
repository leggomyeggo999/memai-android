# Mem AI Android — developer architecture

This document describes how the Flutter app is structured so you can navigate the codebase and extend it without guesswork. It references Mem’s public documentation where behavior is defined by the platform, not by this repo.

## References

- Mem REST API: [Introduction](https://docs.mem.ai/api-reference/overview/introduction), [Authentication](https://docs.mem.ai/api-reference/overview/authentication)
- Mem MCP (hosted): [Overview](https://docs.mem.ai/mcp/overview), [Supported tools](https://docs.mem.ai/mcp/supported-tools), [Security](https://docs.mem.ai/mcp/security-best-practices)
- Documentation index: [https://docs.mem.ai/llms.txt](https://docs.mem.ai/llms.txt)

## Goals (what this app optimizes for)

1. **REST API** (`https://api.mem.ai`) — primary data and tool path. Bearer auth with the user’s Mem **API key** from Mem Settings → API.
2. **MCP HTTP** (`https://mcp.mem.ai/mcp`) — OAuth-issued access tokens for the same logical tools when the user prefers the **MCP connector** style auth (or does not use an API key). Mem documents that MCP is backed by the same API quotas.
3. **BYO LLM** — chat uses **your** OpenAI or Anthropic keys; the app never proxies LLM traffic through a custom backend.
4. **Secrets on-device** — API keys and OAuth tokens are stored with `flutter_secure_storage` (see `lib/core/security/secure_vault.dart`).

## Directory map

| Path | Role |
|------|------|
| `lib/main.dart` | `WidgetsFlutterBinding`, `AppState.load()`, `MaterialApp`, `MemShell`. |
| `lib/app_state.dart` | `ChangeNotifier` holding non-secret UI state and coordinating vault + MCP OAuth. |
| `lib/app_scope.dart` | `InheritedWidget` exposing `AppState` to the tree. |
| `lib/core/config/mem_endpoints.dart` | Canonical URLs and MCP protocol version string. |
| `lib/core/mem/` | `MemApiClient` + DTOs; maps to documented `/v2/...` routes. |
| `lib/core/mcp/` | Dynamic OAuth client registration, `flutter_appauth` sign-in, JSON-RPC MCP client. |
| `lib/core/llm/` | Tool JSON schemas, `MemToolRunner`, OpenAI and Anthropic agent loops. |
| `lib/features/` | UI: Pulse, Capture, Chat, Library, Settings, Note detail. |
| `lib/theme/` | Material 3 dark theme tuned for OLED-style surfaces. |

## Auth flows

### Mem REST API key

Stored under vault key `mem.rest_api_key`. Used as `Authorization: Bearer <key>` for all `MemApiClient` calls. This is the **recommended** path for in-app tool execution (simple, one secret, documented in Mem’s auth guide).

### MCP OAuth (for `mcp.mem.ai`)

1. **Dynamic client registration** — `POST https://api.mem.ai/oauth2/register` with redirect URI **`com.memai.memai_android://oauth`** (must match `android/app/build.gradle.kts` `appAuthRedirectScheme` + `MemMcpOAuth.redirectUrl` in code). See `McpDynamicRegistration`.
2. **Authorize** — `flutter_appauth` opens Chrome Custom Tabs to `https://mem.ai/oauth/consent` with PKCE, then exchanges at `https://api.mem.ai/api/v2/oauth2/token`.
3. **Use** — `McpSessionClient` sends JSON-RPC to `https://mcp.mem.ai/mcp` with `Authorization: Bearer <access_token>`, `MCP-Protocol-Version: 2025-06-18`, and persists `mcp-session-id` when the server returns it (Streamable HTTP session).

**Important:** Disconnect clears **tokens only**; the registered `client_id` is kept so re-login can reuse the same Mem client where possible.

### Chat model keys (multi-provider)

- Profile list (id, display name, provider, model id) is JSON in vault key `chat.profiles_meta_json`.
- Each profile’s provider API key lives in `chat.llm_key.<profileId>`.
- The active profile id is kept in memory via `AppState.activeModelId` (not secret).

## Chat stack

- **UI:** [flutter_chat_ui](https://pub.dev/packages/flutter_chat_ui) (`Chat` + `InMemoryChatController`).
- **Tools:** Names align with Mem MCP docs (`search_notes`, `get_note`, …). Definitions live in `mem_tool_definitions.dart`.
- **Execution:** `MemToolRunner` prefers **REST** when `MemApiClient` is available; otherwise uses **MCP** JSON-RPC so OAuth-only users still get tools.

## Android-specific configuration

- **Internet:** `android/app/src/main/AndroidManifest.xml` includes `INTERNET` for release builds (not only debug/profile).
- **OAuth redirect:** `manifestPlaceholders["appAuthRedirectScheme"] = "com.memai.memai_android"` in `android/app/build.gradle.kts` for `flutter_appauth`.

## Testing

`test/widget_test.dart` runs a small **unit** check on endpoint constants so CI does not require plugin mocks or timer-heavy chat widgets. Full widget/integration tests should run on a device or emulator with configured credentials if you add them later.

## Known limitations / extension points

- **Streaming LLM replies** — Not implemented; responses appear after full completion. OpenAI and Anthropic streaming APIs can be wired in without changing Mem integration.
- **MCP transport** — If Mem returns non-JSON bodies (e.g. SSE under load), extend `McpSessionClient` to parse stream chunks; today the client expects JSON-RPC-shaped responses after tool calls.
- **Extra Mem endpoints** — Attachments, trash, audio, etc., can be added by extending `MemApiClient` using the same OpenAPI-derived paths in the official docs.
