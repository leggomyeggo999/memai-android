# MemDroid Android — developer architecture

This document describes how the Flutter app is structured so you can navigate the codebase and extend it without guesswork. It references Mem’s public documentation where behavior is defined by the platform, not by this repo.

## References

- Mem REST API: [Introduction](https://docs.mem.ai/api-reference/overview/introduction), [Authentication](https://docs.mem.ai/api-reference/overview/authentication)
- Mem MCP (hosted): [Overview](https://docs.mem.ai/mcp/overview), [Supported tools](https://docs.mem.ai/mcp/supported-tools), [Security](https://docs.mem.ai/mcp/security-best-practices)
- Documentation index: [https://docs.mem.ai/llms.txt](https://docs.mem.ai/llms.txt)

## Goals (what this app optimizes for)

1. **REST API** (`https://api.mem.ai`) — primary data and tool path. Bearer auth with the user’s Mem **API key** from Mem Settings → API.
2. **MCP HTTP** (`https://mcp.mem.ai/mcp`) — OAuth-issued access tokens for the same logical tools when the user prefers the **MCP connector** style auth (or does not use an API key). Mem documents that MCP is backed by the same API quotas.
3. **BYO LLM** — chat uses **your** OpenAI, Anthropic, or Gemini keys; the app never proxies LLM traffic through a custom backend.
4. **Secrets on-device** — API keys and OAuth tokens are stored with `flutter_secure_storage` (see `lib/core/security/secure_vault.dart`).

## Directory map

| Path | Role |
|------|------|
| `lib/main.dart` | `WidgetsFlutterBinding`, `AppState.load()`, `MaterialApp`, `MemShell`. |
| `lib/app_state.dart` | `ChangeNotifier` holding non-secret UI state and coordinating vault + MCP OAuth. |
| `lib/app_scope.dart` | `InheritedWidget` exposing `AppState` to the tree. |
| `lib/core/config/mem_endpoints.dart` | Canonical URLs and MCP protocol version string. |
| `lib/core/mem/` | `MemApiClient` + DTOs; maps to documented `/v2/...` routes. |
| `lib/core/mcp/` | Dynamic OAuth registration, `flutter_appauth` (Custom Tabs — not WebView), JSON-RPC MCP client. |
| `lib/core/llm/` | Tool JSON schemas, `MemToolRunner`, OpenAI and Anthropic agent loops. |
| `lib/features/` | UI: Notes (timeline + collections), Capture, Chat, Settings, note detail, collections manager. |
| `lib/theme/` | Material 3 dark theme tuned for OLED-style surfaces. |

## Auth flows

### Mem REST API key

Stored under vault key `mem.rest_api_key`. Used as `Authorization: Bearer <key>` for all `MemApiClient` calls. This is the **recommended** path for in-app tool execution (simple, one secret, documented in Mem’s auth guide).

### MCP OAuth (for `mcp.mem.ai`)

1. **Dynamic client registration** — `POST https://api.mem.ai/oauth2/register` with redirect URI **`com.memai.memaiandroid://oauth`** (must match `MemMcpOAuth.redirectUrl`; underscores are invalid in URI schemes). See `McpDynamicRegistration`.
2. **Authorize** — **`flutter_appauth`** opens **Chrome Custom Tabs** to `https://mem.ai/oauth/consent` with PKCE. Do **not** use an embedded **WebView** for this step — Google rejects it with **`403 disallowed_useragent`**. Redirect URI **`com.memai.memaiandroid://oauth`** matches `manifestPlaceholders["appAuthRedirectScheme"]` plus AppAuth’s **`RedirectUriReceiverActivity`**; tokens are persisted in the vault.
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
- **OAuth / MCP:** `manifestPlaceholders["appAuthRedirectScheme"] = "com.memai.memaiandroid"` in `android/app/build.gradle.kts`. **Do not set `android:taskAffinity=""` on `MainActivity`** — it breaks returning from Custom Tabs ([flutter_appauth #503](https://github.com/MaikuB/flutter_appauth/issues/503#issuecomment-2165906205)).

## Testing

- `test/widget_test.dart` — endpoint constants.
- `test/openai_stream_accumulator_test.dart` — OpenAI SSE delta parsing.
- `test/anthropic_sse_events_test.dart` — Claude SSE `data:` frame merging (`AnthropicSseSink`).
- `test/gemini_stream_round_test.dart` — Gemini streamed JSON chunks + tool slots.
- **`integration_test/app_smoke_test.dart`** — run on a **device or emulator**:
  `flutter test integration_test/app_smoke_test.dart`

Unit tests avoid plugin-backed vault loads and full **Chat** mounting (empty-chat UI schedules timers that fail `pumpAndSettle` in the VM harness).

## Chat streaming (OpenAI)

`OpenAiMemAgent` requests **`stream: true`** (SSE) for each completion round. `MemChatPage` wires `onAssistantTextDelta` to update the assistant bubble incrementally. Tool calls are merged from stream chunks (`openai_stream_accumulator.dart`); tool execution between rounds is unchanged. If the stream request fails (`DioException`), one **non-streaming** fallback runs for that round.

## Chat streaming (Anthropic)

`AnthropicMemAgent` uses **`stream: true`** on Messages with **Claude SSE** (`AnthropicSseSink` + `AnthropicStreamRoundAccumulator`): `content_block_start` / `_delta` / `_stop` reconstruct the same `assistant` `content` array a non-streaming call would return (text, `tool_use`, optional `thinking`). `onAssistantTextDelta` only reflects **text** blocks so thinking stays server-side. **`DioException`** falls back to a normal JSON `messages` call for that round.

## Chat streaming (Gemini)

`GeminiMemAgent` hits **`models/{id}:streamGenerateContent?alt=sse`** (Google AI Studio / `generativelanguage.googleapis.com` with **`x-goog-api-key`**). Lines are parsed with `GeminiSseSink`; each JSON chunk updates `GeminiStreamRoundAccumulator` (text + streamed `functionCall` merging). **`DioException`** falls back to **`generateContent`**. Blocking `promptFeedback` aborts the round with an error.

## CI

GitHub Actions (`.github/workflows/flutter_ci.yml`): **`flutter analyze`**, **`flutter test`**, and **`integration_test/app_smoke_test.dart`** on an API 34 x86_64 emulator via `ReactiveCircus/android-emulator-runner`.

## Manual device verification

After changing LLM plumbing, spot-check **on hardware or emulator** (CI does not substitute for real keys):

1. Settings → Mem API key and/or MCP; confirm Notes list loads.
2. Add an OpenAI model: chat streams tokens; invoke a Mem tool (`search_notes`); reply completes.
3. Repeat for Anthropic; kill network briefly to confirm streaming falls back once, then restores.
4. Add Gemini (`gemini-2.0-flash` or your account’s id): streaming + tool round-trip.

## Note lifecycle (REST)

`MemApiClient`: `trashNote`, `restoreNote`, `deleteNoteHard` map to Mem’s `POST .../trash`, `POST .../restore`, and `DELETE /v2/notes/{note_id}`. Note detail exposes trash / restore / delete permanently; tools add `trash_note` and `restore_note`.

## Known limitations / backlog

- **Other providers** — Same pattern as OpenAI/Anthropic/Gemini; add a profile `provider` + agent class.
- **Notes list caching** — No offline cache yet; refresh-only.
- **Biometric lock / screen security** — `flutter_secure_storage` only; add `local_auth` overlay if desired.
- **MCP over SSE / long streams** — `McpSessionClient` is JSON POST–oriented; extend if Mem adds streaming MCP transport.
- **MCP transport** — If Mem returns non-JSON bodies (e.g. SSE under load), extend `McpSessionClient` to parse stream chunks; today the client expects JSON-RPC-shaped responses after tool calls.
- **Extra Mem endpoints** — Attachments, audio, etc., can be added by extending `MemApiClient` using documented paths / OpenAPI.
