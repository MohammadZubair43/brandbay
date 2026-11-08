// BrandBay "send-push" function (Supabase Edge Function).
// The database calls this for every new notification; it pops the message up on the user's devices.
// Secrets to set in Supabase (Edge Functions -> Secrets):
//   PUSH_SECRET        same random text as in private.config 'push_secret'
//   VAPID_PUBLIC_KEY   from `npx web-push generate-vapid-keys`
//   VAPID_PRIVATE_KEY  from the same command (keep private)
//   SITE_URL           optional, defaults to https://brandbay.vercel.app
// In the function's settings, turn OFF "Verify JWT": the PUSH_SECRET check below protects it instead.
import webpush from "npm:web-push@3.6.7";

const SITE = (Deno.env.get("SITE_URL") || "https://brandbay.vercel.app").replace(/\/$/, "");
const PUSH_SECRET = Deno.env.get("PUSH_SECRET");
const PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY");
const PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (PUBLIC_KEY && PRIVATE_KEY) webpush.setVapidDetails(SITE, PUBLIC_KEY, PRIVATE_KEY);

// Devices that were uninstalled or turned off answer 404/410: forget them.
async function forget(endpoint) {
  if (!SUPABASE_URL || !SERVICE_KEY) return;
  await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(endpoint)}`, {
    method: "DELETE",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  }).catch(() => {});
}

export async function handle(req) {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!PUSH_SECRET || req.headers.get("x-push-secret") !== PUSH_SECRET) return new Response("Forbidden", { status: 403 });
  if (!PUBLIC_KEY || !PRIVATE_KEY) return Response.json({ error: "VAPID keys are not set" }, { status: 500 });

  let msg;
  try { msg = await req.json(); } catch { return Response.json({ error: "Bad JSON" }, { status: 400 }); }
  const subs = Array.isArray(msg.subscriptions) ? msg.subscriptions : [];
  const payload = JSON.stringify({
    title: "BrandBay",
    body: String(msg.body || "You have a new update").slice(0, 300),
    url: `${SITE}/#${encodeURIComponent(String(msg.link || "overview")).replace(/%2D/g, "-")}`,
    tag: msg.tag || undefined,
  });

  let sent = 0, removed = 0, failed = 0;
  await Promise.all(subs.map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 });
      sent++;
    } catch (e) {
      if (e && (e.statusCode === 404 || e.statusCode === 410)) { removed++; await forget(s.endpoint); }
      else { failed++; console.error("push failed", e && e.statusCode, e && e.body); }
    }
  }));
  return Response.json({ sent, removed, failed });
}

Deno.serve(handle);
