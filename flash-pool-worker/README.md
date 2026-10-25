# Flâsh Hiddify pool — deploy guide (NOT deployed yet)

This Worker is a NEW pool for Flâsh Hiddify only. It is separate from
Flâsh VPN's pool: separate Worker, separate KV namespace, separate
publish password, separate Cloudflare account.

## Deploy (do this once, on a DEDICATED Hiddify account)

1. Create a NEW Cloudflare account dedicated to Flâsh Hiddify (do not
   reuse the Flâsh VPN account — one-account-per-app).
2. In that account: Workers & Pages → create a KV namespace named
   `POOL_KV`, copy its id into `wrangler.toml` (replace
   `REPLACE_WITH_KV_NAMESPACE_ID`).
3. `cd flash-pool-worker && npx wrangler login && npx wrangler deploy`
4. Set the publish password (never commit it anywhere):
   `npx wrangler secret put PUBLISH_PASSWORD`
5. Verify: `GET https://<your-worker>.workers.dev/pool` returns
   `{"ok":true,"entries":[]}` and a wrong-password POST /publish
   returns 401 `bad_password`.

## Use in the app

Settings → 🌍 Flâsh Pool: enter the Worker URL (e.g.
`https://flash-hiddify-pool.<subdomain>.workers.dev`) and the publish
password you set in step 4. The password is stored locally in the app's
preferences (not secure storage — same as the app's other preferences);
it is never logged and never exported with a profile.

Published links are PUBLIC: anyone who knows the pool URL can fetch
and use them. Never publish a private subscription URL unless you
intend it to become public.
