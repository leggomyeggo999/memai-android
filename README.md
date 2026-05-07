# MemDroid (Android, Flutter)

MemDroid is an Android-first companion for Mem with four core surfaces:
- **Notes**: browse, edit, move, trash/restore, and organize notes + collections.
- **Capture**: fast text capture + voice transcription (Whisper/OpenAI).
- **Chat**: bring your own OpenAI / Anthropic / Gemini model with Mem tools.
- **Prompt jobs**: reusable one-tap prompts in Chat and Android home widgets.

Credentials and tokens are stored on-device with `flutter_secure_storage`.

---

## Settings and auth guide (the 4 key sections)

This is the most important setup concept: each settings section powers different features.

| Settings section | What you enter | Used for | Required for |
|---|---|---|---|
| **Mem API key** | Mem REST API key | Direct calls to `api.mem.ai` | Notes, Collections, Capture text save, and Chat tool execution via REST |
| **MCP OAuth** | Browser OAuth sign-in (no manual key) | Token-based MCP session to `mcp.mem.ai` | Chat tools when using MCP path (especially if no Mem API key) |
| **Chat models** | Provider + model + provider API key (OpenAI / Anthropic / Gemini) | LLM generation in Chat | Any AI response in Chat |
| **Voice transcription (OpenAI)** | Whisper model + optional dedicated OpenAI key | Audio transcription for Capture mic workflows | Voice-to-text capture |

### How they combine
- **Best default**: set **Mem API key** + at least one **Chat model**.
- **MCP optional**: enable **MCP OAuth** if you want connector-style auth or a fallback/alternate tool path.
- **Voice optional**: set **Voice transcription** only if you want mic capture.
- **Chat vs Voice keys**: voice can reuse an OpenAI chat key, or use its own dedicated key.

---

## Full feature list

### Notes
- Timeline-style notes list.
- Open/edit note details.
- Move note to trash, restore, or delete permanently.
- Collection management: create, rename, describe, delete.
- Notes list refresh triggers after save/create flows.

### Capture
- Fast text capture into Mem.
- Voice capture with OpenAI transcription:
  - Longform mode (tap start/stop).
  - Push-to-talk mode (hold to record, release to transcribe).
  - Replace vs append transcript toggle.
  - Whisper language mode (auto or forced language).
  - Prompt hints for domain-specific vocabulary.
  - Recording timer + level meter + haptic feedback.

### Chat
- Multi-provider model profiles (OpenAI, Anthropic, Gemini).
- Streaming assistant responses (provider-specific streaming support).
- Mem tool execution (search/read/update flows through REST and/or MCP).
- Prompt jobs strip for quick execution in-chat.
- Long-press copy for message text.

### Prompt jobs + widgets
- Create/edit/delete reusable prompt templates.
- Pin up to 4 jobs for Android home widget use.
- Launch job from widget into Chat.
- Local notification on widget-triggered job success/failure.
- Notification tap routes back to app home.

### Platform / app behavior
- Android launcher + splash branding set to **MemDroid**.
- Release signing support via `android/key.properties` + keystore.
- Split-per-ABI release APK output for smaller installs.

---

## Quick setup

1. Install Flutter + Android SDK, then run:
   - `flutter pub get`
2. Launch app and configure Settings in this order:
   1. **Mem API key**
   2. **Chat model** (provider/model/key)
   3. Optional: **MCP OAuth**
   4. Optional: **Voice transcription (OpenAI)**
3. Run on device/emulator:
   - `flutter run`

---

## Build and test

- Static checks/tests:
  - `flutter analyze`
  - `flutter test`
- Integration smoke test:
  - `flutter test integration_test/app_smoke_test.dart`

GitHub Actions runs analyze + tests + smoke integration test on Android emulator.

---

## Potential roadmap

### Near-term
- Better first-run onboarding with a guided setup wizard for the 4 settings sections.
- In-app diagnostics page (auth state, selected model, backend/tool path, device ABI/build info).
- More robust copy/share UX in Chat (explicit copy buttons and multi-message actions).
- Better offline/loading states for Notes/Capture.

### Mid-term
- Multi-account/profile support (work/personal Mem contexts).
- Richer note operations (bulk edit, smart collection suggestions, merge/dedupe utilities).
- Extended prompt jobs (scheduled runs, history, retries, result logs).
- Improved widget UX (more than 4 slots, configurable layouts).

### Longer-term
- Optional background sync/caching with conflict-aware updates.
- Expanded voice pipeline (speaker segmentation, transcript cleanup presets).
- Export/share workflows (Markdown/PDF bundles, external integrations).
- Additional LLM providers via the existing provider abstraction.

---

## Docs

- Developer architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Mem API docs: [https://docs.mem.ai/api-reference/overview/introduction](https://docs.mem.ai/api-reference/overview/introduction)
- Mem MCP docs: [https://docs.mem.ai/mcp/overview](https://docs.mem.ai/mcp/overview)
