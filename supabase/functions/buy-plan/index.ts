// Signed-in customer buys a pre-paid plan (e.g. 12 maintenance valets at 20% off) through Stripe Checkout.
// POST { plan_id, count, size } → { url }. The stripe-webhook adds the washes to their account once paid.
import { createClient } from "npm:@supabase/supabase-js@2";
const URL_ = Deno.env.get("SUPABASE_URL")!;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
async function keysFor(biz: string): Promise<string | undefined> {
  const a = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data } = await a.rpc("get_business_stripe", { p_business: biz }); if (data && (data as any).secret) return (data as any).secret;
  const { data: v } = await a.rpc("get_stripe_config"); return Deno.env.get("STRIPE_SECRET_KEY") || (v as any)?.STRIPE_SECRET_KEY;
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
    const { data: { user } } = await userDb.auth.getUser();
    if (!user) return json({ error: "Please sign in to your account first" }, 401);
    const { plan_id, count, size } = await req.json();
    const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: p } = await db.from("plans").select("*, services:service_id(*), businesses(name,settings)").eq("id", plan_id).eq("active", true).single();
    if (!p) return json({ error: "That plan isn't available" }, 404);
    const n = Number(count); if (!(p.counts || [12]).includes(n)) return json({ error: "Choose a valid number of valets" }, 400);
    const z = Math.max(0, Math.min(2, Number(size) || 0)); const s: any = p.services || {};
    const unit = Number(z === 2 ? (s.price_large ?? s.price_medium ?? s.price_small) : z === 1 ? (s.price_medium ?? s.price_small) : s.price_small) || 0;
    const st: any = (p as any).businesses?.settings || {};
    const off = Number(p.discount_pct ?? st.prepaidOff ?? 20);
    const pence = Math.round(unit * n * (1 - off / 100) * 100);
    if (pence < 100) return json({ error: "Plan price not set" }, 400);
    const { data: c } = await db.from("customers").select("id,email").eq("business_id", p.business_id).eq("user_id", user.id).maybeSingle();
    if (!c) return json({ error: "Please finish creating your account first" }, 400);
    const key = await keysFor(p.business_id); if (!key) return json({ error: "Card payments aren't switched on yet" }, 400);
    const site = Deno.env.get("SITE_URL") || "https://bcleanvaleting.co.uk";
    const sizes = ["Small", "Medium", "Large"];
    const params: Record<string, string> = {
      mode: "payment", "line_items[0][quantity]": "1", "line_items[0][price_data][currency]": "gbp", "line_items[0][price_data][unit_amount]": String(pence),
      "line_items[0][price_data][product_data][name]": `${p.name} — ${n} × ${s.name || "valet"}`,
      "line_items[0][price_data][product_data][description]": `${sizes[z]} vehicle · ${off}% off · use within ${p.months || 12} months`,
      success_url: `${site}/account/?plan=bought`, cancel_url: `${site}/account/`, customer_email: user.email || c.email,
      "metadata[type]": "plan", "metadata[plan_id]": p.id, "metadata[count]": String(n), "metadata[size]": String(z),
      "metadata[customer_id]": c.id, "metadata[business_id]": p.business_id,
      "payment_intent_data[description]": `${(p as any).businesses?.name || ""} ${p.name}`,
    };
    const r = await fetch("https://api.stripe.com/v1/checkout/sessions", { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(params) });
    const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || "Stripe error");
    return json({ url: j.url, amount: pence / 100 });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
