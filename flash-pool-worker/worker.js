// Flâsh Hiddify — public server pool (v0.2, NEW pool for Hiddify only).
// Plain Cloudflare Worker, no build step. KV-backed, free-plan friendly.
//
// This is a SEPARATE pool from Flâsh VPN's pool: different Worker, different
// KV namespace, different secret. Never point it at the Flâsh VPN pool and
// never reuse that pool's password or account (one-account-per-app rule).
//
// Endpoints:
//   GET  /pool    -> public JSON list [{id, name, country, key, kind, publishedAt}]
//                    kind is "node" (a single proxy link) or "subscription"
//                    (a subscription URL — the app labels it as such).
//   POST /publish -> JSON {name, country, key, kind?, password}
//                    password is verified against the Worker secret
//                    PUBLISH_PASSWORD (set at deploy time with
//                    `wrangler secret put PUBLISH_PASSWORD`). The secret
//                    value is NEVER in this source, in tests, or in docs.
//   POST /delete  -> JSON {id?, key?, password} — removes that pool entry
//                    by id or by key. Same password gate as publish.
//   GET  /        -> health text.
//
// WARNING: links published here are PUBLIC by definition — anyone who
// knows the pool URL can fetch and use them. Never publish a private
// subscription URL unless you intend it to become public.
//
// Validation: name 1..60 chars, country 0..12 chars (optional flag emoji),
// key must be a usable proxy link (vless/vmess/trojan/ss/hysteria2/hy2/
// tuic/wireguard) or an http(s) subscription URL (kind forced to
// "subscription"). Re-publishing the same key updates name/country
// instead of duplicating. Per-IP throttle: 5 publishes/deletes per
// 10 minutes (shared bucket). Pool capped at 500 entries.

const POOL_KEY = 'pool:v1';
const MAX_ENTRIES = 500;
const MAX_KEY_LEN = 8192;
const THROTTLE_WINDOW_MS = 10 * 60 * 1000;
const THROTTLE_LIMIT = 5;

function codePoints(s) {
  return [...s].length;
}

function jsonResp(obj, status) {
  return new Response(JSON.stringify(obj), {
    status: status || 200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      'cache-control': 'no-store',
    },
  });
}

function err(code, status) {
  return jsonResp({ ok: false, error: code }, status);
}

function parseKey(key) {
  if (typeof key !== 'string') return null;
  const k = key.trim();
  if (!k || k.length > MAX_KEY_LEN) return null;
  const low = k.toLowerCase();
  if (low.startsWith('nm-') || low.startsWith('zivpn://')) return { vendorLocked: true };
  if (low.startsWith('http://') || low.startsWith('https://')) {
    return { type: 'subscription', host: low.split('/')[2] || '' };
  }
  const m = /^([a-z0-9]+):\/\/(.+)$/.exec(low);
  if (!m) return null;
  const scheme = m[1];
  const nodeSchemes = ['vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic', 'wireguard'];
  if (!nodeSchemes.includes(scheme)) return null;
  let body = k.slice(k.indexOf('://') + 3);
  const at = body.lastIndexOf('@');
  if (at >= 0) body = body.slice(at + 1);
  let host = '';
  if (body.startsWith('[')) {
    const rb = body.indexOf(']');
    if (rb <= 0) return null;
    host = body.slice(1, rb);
  } else {
    host = body.split(/[/:?#]/)[0];
  }
  if (!host) return null;
  return { type: scheme, host };
}

async function sha256Hex(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function checkPassword(provided, env) {
  const secret = env.PUBLISH_PASSWORD;
  if (typeof secret !== 'string' || secret.length === 0) return 'unconfigured';
  if (typeof provided !== 'string') return 'bad';
  return timingSafeEqual(new TextEncoder().encode(provided), new TextEncoder().encode(secret)) ? 'ok' : 'bad';
}

async function readPool(env) {
  const raw = await env.POOL_KV.get(POOL_KEY);
  if (!raw) return [];
  try {
    const arr = JSON.parse(raw);
    return Array.isArray(arr) ? arr : [];
  } catch (e) {
    return [];
  }
}

function clientIp(request) {
  return request.headers.get('CF-Connecting-IP') || 'unknown';
}

async function checkThrottle(env, ip) {
  const tkey = 'throttle:' + ip;
  const now = Date.now();
  let stamps = [];
  try {
    const raw = await env.POOL_KV.get(tkey);
    if (raw) stamps = JSON.parse(raw);
  } catch (e) { stamps = []; }
  if (!Array.isArray(stamps)) stamps = [];
  stamps = stamps.filter((t) => typeof t === 'number' && now - t < THROTTLE_WINDOW_MS);
  if (stamps.length >= THROTTLE_LIMIT) return false;
  stamps.push(now);
  await env.POOL_KV.put(tkey, JSON.stringify(stamps), { expirationTtl: 600 });
  return true;
}

async function handlePublish(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (e) {
    return err('bad_json', 400);
  }
  const pw = await checkPassword(body.password, env);
  if (pw === 'unconfigured') return err('server_not_configured', 500);
  if (pw !== 'ok') return err('bad_password', 401);
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  const country = typeof body.country === 'string' ? body.country.trim() : '';
  const key = typeof body.key === 'string' ? body.key.trim() : '';
  if (!name || codePoints(name) > 60) return err('invalid_name', 400);
  if (country && codePoints(country) > 12) return err('invalid_country', 400);
  const parsed = parseKey(key);
  if (!parsed) return err('invalid_key', 400);
  if (parsed.vendorLocked) return err('vendor_locked', 400);
  const kind = parsed.type === 'subscription' ? 'subscription' : 'node';
  const ip = clientIp(request);
  if (!(await checkThrottle(env, ip))) return err('too_many', 429);
  const pool = await readPool(env);
  const id = (await sha256Hex(key)).slice(0, 24);
  const existing = pool.find((e) => e.key === key);
  if (existing) {
    // Only overwrite fields the publisher actually sent, so a re-publish
    // without a country does not wipe the stored country.
    if (name) existing.name = name;
    if (country) existing.country = country;
    existing.kind = kind;
  } else {
    if (pool.length >= MAX_ENTRIES) return err('pool_full', 400);
    pool.push({ id, name, country, key, kind, publishedAt: Date.now() });
  }
  await env.POOL_KV.put(POOL_KEY, JSON.stringify(pool));
  return jsonResp({ ok: true, id });
}

async function handleDelete(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (e) {
    return err('bad_json', 400);
  }
  const pw = await checkPassword(body.password, env);
  if (pw === 'unconfigured') return err('server_not_configured', 500);
  if (pw !== 'ok') return err('bad_password', 401);
  const id = typeof body.id === 'string' ? body.id.trim() : '';
  const key = typeof body.key === 'string' ? body.key.trim() : '';
  if (!id && !key) return err('unknown_id', 404);
  const pool = await readPool(env);
  const idx = pool.findIndex((e) => (id && e.id === id) || (key && e.key === key));
  if (idx < 0) return err('unknown_id', 404);
  const ip = clientIp(request);
  if (!(await checkThrottle(env, ip))) return err('too_many', 429);
  pool.splice(idx, 1);
  await env.POOL_KV.put(POOL_KEY, JSON.stringify(pool));
  return jsonResp({ ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-methods': 'GET, POST, OPTIONS',
          'access-control-allow-headers': 'content-type',
        },
      });
    }
    if (url.pathname === '/pool' && request.method === 'GET') {
      return jsonResp({ ok: true, entries: await readPool(env) });
    }
    if (url.pathname === '/publish' && request.method === 'POST') return handlePublish(request, env);
    if (url.pathname === '/delete' && request.method === 'POST') return handleDelete(request, env);
    if (url.pathname === '/' && request.method === 'GET') {
      return new Response('Flâsh Hiddify pool OK', { headers: { 'content-type': 'text/plain; charset=utf-8' } });
    }
    return err('not_found', 404);
  },
};
