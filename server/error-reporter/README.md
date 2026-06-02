# MemDroid error reporter (Cloudflare Worker)

Cheap, minimal telemetry for client-side API/UI errors.

## Deploy (~2 minutes)

```bash
npm i -g wrangler
cd server/error-reporter
wrangler login
wrangler secret put INGEST_SECRET   # optional but recommended
wrangler deploy
```

Note your worker URL, e.g. `https://memdroid-error-reporter.<account>.workers.dev`.

## Wire the Android app

Build with dart-defines:

```bash
flutter build apk --release \
  --dart-define=MEMDROID_ERROR_REPORT_URL=https://memdroid-error-reporter.<account>.workers.dev/report \
  --dart-define=MEMDROID_ERROR_REPORT_SECRET=your-secret
```

## Endpoints

| Path | Method | Purpose |
|------|--------|---------|
| `/health` | GET | Liveness check |
| `/report` | POST | Ingest JSON error payload |

View logs: Cloudflare dashboard → Workers → your worker → Logs.

No database required; payloads are logged only (free-tier friendly).
