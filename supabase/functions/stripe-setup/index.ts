// Admin-only: connect a business's Stripe account from the admin app.
// POST { business_id, secret_key }  → checks the key with Stripe, creates the webhook automatically, stores both privately.
// POST { business_id, action: "test" } → re-checks the saved key.
import { createClient } from "npm:@supabase/supabase-js@2";
const URL_ = Deno.env.get("SUPABASE_URL")!;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
async function stripe(method: string, path: string, key: string, params?: Record<string, string>) {
  const r = await fetch(`https://api.stripe.com/v1/${path}`, { method, headers: { Authorization: `Bearer ${key}`, ...(params ? { "Content-Type": "application/x-www-form-urlencoded" } : {}) }, body: params ? new URLSearchParams(params) : undefined });
  const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || "Stripe error"); return j;
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
    const { business_id, secret_key, action } = await req.json();
    const { data: member } = await userDb.rpc("is_member", { p_business: business_id });
    if (!member) return json({ error: "Not allowed" }, 403);
    const admin = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    if (action === "test") {
      const { data } = await admin.rpc("get_business_stripe", { p_business: business_id });
      if (!data?.secret) return json({ error: "Not connected" }, 400);
      try { const acct = await stripe("GET", "account", data.secret); return json({ ok: true, account: acct.settings?.dashboard?.display_name || acct.business_profile?.name || acct.id, charges: acct.charges_enabled }); }
      catch (e) { await stripe("GET", "checkout/sessions?limit=1", data.secret); return json({ ok: true, account: "Stripe account", charges: true }); }
    }
    const key = String(secret_key || "").trim();
    if (!/^(sk|rk)_(live|test)_[A-Za-z0-9]+$/.test(key)) return json({ error: "That doesn't look like a Stripe secret key — it should start sk_live_ or rk_live_ (or _test_ for testing)." }, 400);
    const mode = key.includes("_live_") ? "live" : "test";
    // proves the key works. Restricted keys (rk_) may not be allowed to read the account — that's fine.
    let acct: any = {}; let name = "Stripe account";
    try { acct = await stripe("GET", "account", key); name = acct.settings?.dashboard?.display_name || acct.business_profile?.name || acct.email || acct.id; }
    catch (e) { if (!key.startsWith("rk_") || !/permission|restricted/i.test((e as Error).message)) throw e; await stripe("GET", "checkout/sessions?limit=1", key); acct = { charges_enabled: true }; }
    // replace any webhook we created before for this business
    const { data: prev } = await admin.rpc("get_business_stripe", { p_business: business_id });
    if (prev?.webhook_id && prev?.secret) { try { await stripe("DELETE", `webhook_endpoints/${prev.webhook_id}`, prev.secret); } catch (_) { /* already gone */ } }
    const url = `${URL_}/functions/v1/stripe-webhook?b=${business_id}`;
    const existing = await stripe("GET", "webhook_endpoints?limit=100", key);
    for (const w of existing.data || []) if (w.url === url) { try { await stripe("DELETE", `webhook_endpoints/${w.id}`, key); } catch (_) { /* ignore */ } }
    const wh = await stripe("POST", "webhook_endpoints", key, { url, "enabled_events[0]": "checkout.session.completed", "enabled_events[1]": "invoice.paid", description: "valetIQ — records deposits and invoice payments" });
    const { error } = await admin.rpc("save_business_stripe", { p_business: business_id, p_secret: key, p_whsec: wh.secret, p_whid: wh.id, p_mode: mode, p_account: name });
    if (error) throw error;
    return json({ ok: true, mode, account: name, charges: acct.charges_enabled, key: key.slice(0, 8) + "…" + key.slice(-4) });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
