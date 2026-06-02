/**
 * Minimal MemDroid error ingest (Cloudflare Workers — free tier friendly).
 *
 * Deploy:
 *   npm i -g wrangler
 *   cd server/error-reporter
 *   wrangler secret put INGEST_SECRET   # optional shared secret
 *   wrangler deploy
 *
 * App build:
 *   flutter build apk --release \
 *     --dart-define=MEMDROID_ERROR_REPORT_URL=https://<worker>.workers.dev/report \
 *     --dart-define=MEMDROID_ERROR_REPORT_SECRET=<same-secret-if-set>
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return cors(new Response(null, { status: 204 }));
    }

    if (url.pathname === '/health') {
      return cors(json({ ok: true }));
    }

    if (url.pathname !== '/report' || request.method !== 'POST') {
      return cors(json({ error: 'not_found' }, 404));
    }

    if (env.INGEST_SECRET) {
      const got = request.headers.get('X-MemDroid-Secret');
      if (got !== env.INGEST_SECRET) {
        return cors(json({ error: 'unauthorized' }, 401));
      }
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return cors(json({ error: 'invalid_json' }, 400));
    }

  const entry = {
      receivedAt: new Date().toISOString(),
      ...sanitize(body),
    };

    console.log('[memdroid-error]', JSON.stringify(entry));

    return cors(json({ ok: true }, 204));
  },
};

function sanitize(obj) {
  if (!obj || typeof obj !== 'object') return {};
  const out = { ...obj };
  for (const k of Object.keys(out)) {
    const lower = k.toLowerCase();
    if (
      lower.includes('key') ||
      lower.includes('token') ||
      lower.includes('secret') ||
      lower.includes('password')
    ) {
      out[k] = '[redacted]';
    }
  }
  return out;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function cors(res) {
  const headers = new Headers(res.headers);
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, X-MemDroid-Secret');
  return new Response(res.body, { status: res.status, headers });
}
