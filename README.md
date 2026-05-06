# Mem AI (Android, Flutter)

Native Mem companion for Android: **Pulse** (timeline), **Capture** (Mem-it + raw notes), **Chat** (BYO OpenAI/Anthropic with Mem tools), and **Library** (collections). Credentials stay on-device via `flutter_secure_storage`.

## Docs

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — module map, OAuth/MCP flow, and security notes for developers.

## Quick setup

1. Install Flutter and an Android SDK; from this directory run `flutter pub get`.
2. Open **Settings** in the app:
   - Paste your **Mem API key** (Mem web → Settings → API). Enables REST-backed Pulse, Capture, Library, and Chat tools.
   - Optionally **Connect MCP (OAuth)** for JSON-RPC access to `https://mcp.mem.ai/mcp` when you want connector-style auth instead of (or in addition to) the API key.
   - **Add chat model** — choose OpenAI or Anthropic, enter the **model id** your account supports, and the **provider API key**.
3. `flutter run` on a device or emulator.

**Integration smoke test (device/emulator):** from this directory,
`flutter test integration_test/app_smoke_test.dart`

## Mem platform references

- API: [https://docs.mem.ai/api-reference/overview/introduction](https://docs.mem.ai/api-reference/overview/introduction)
- MCP: [https://docs.mem.ai/mcp/overview](https://docs.mem.ai/mcp/overview)
