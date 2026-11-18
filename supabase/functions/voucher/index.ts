// Buy a gift voucher online: creates a Stripe Checkout page. The webhook issues the voucher and emails it.
// POST { business_id, amount, to_name, from_name, email, to_email?, message? } → { url }
import { createClient } from "npm:@supabase/supabase-js@2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
const realEmail = (e?: string) => !!e && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e);
async function keyFor(biz: string) {
  const { data } = await db.rpc("get_business_stripe", { p_business: biz }); if ((data as any)?.secret) return (data as any).secret as string;
  const { data: v } = await db.rpc("get_stripe_config"); return (Deno.env.get("STRIPE_SECRET_KEY") || (v as any)?.STRIPE_SECRET_KEY) as string | undefined;
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const b = await req.json();
    const amount = Math.round(Number(b.amount));
    const to_name = String(b.to_name || "").trim().slice(0, 60), from_name = String(b.from_name || "").trim().slice(0, 60);
    const email = String(b.email || "").trim().toLowerCase(), to_email = String(b.to_email || "").trim().toLowerCase();
    const message = String(b.message || "").trim().slice(0, 300);
    if (!(amount >= 10 && amount <= 1000)) return json({ error: "Choose an amount between £10 and £1,000" }, 400);
    if (!to_name || !from_name) return json({ error: "Please add who it's for and who it's from" }, 400);
    if (!realEmail(email)) return json({ error: "Please add your email so we can send you the voucher" }, 400);
    if (to_email && !realEmail(to_email)) return json({ error: "The recipient's email doesn't look right" }, 400);
    const { data: biz } = await db.from("businesses").select("id,name,settings").eq("id", b.business_id).single();
    if (!biz) return json({ error: "Business not found" }, 404);
    const key = await keyFor(biz.id); if (!key) return json({ error: "Online payments aren't switched on yet — please message us" }, 400);
    const site = (biz.settings as any)?.siteUrl || Deno.env.get("SITE_URL") || "https://bcleanvaleting.co.uk";
    const p = new URLSearchParams({
      mode: "payment", customer_email: email,
      "line_items[0][quantity]": "1", "line_items[0][price_data][currency]": "gbp", "line_items[0][price_data][unit_amount]": String(amount * 100),
      "line_items[0][price_data][product_data][name]": `£${amount} ${biz.name} gift voucher`,
      "line_items[0][price_data][product_data][description]": `For ${to_name}, from ${from_name}. Emailed instantly · valid 12 months · use against any service`,
      success_url: `${site}/?gift=bought`, cancel_url: `${site}/?gift=${amount}`,
      "metadata[type]": "voucher", "metadata[business_id]": biz.id, "metadata[amount]": String(amount), "metadata[to_name]": to_name, "metadata[from_name]": from_name,
      "metadata[email]": email, "metadata[to_email]": to_email, "metadata[message]": message,
      "payment_intent_data[description]": `${biz.name} gift voucher £${amount}`,
    });
    const r = await fetch("https://api.stripe.com/v1/checkout/sessions", { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/x-www-form-urlencoded" }, body: p });
    const j = await r.json(); if (!r.ok) return json({ error: j?.error?.message || "Payment page couldn't open" }, 400);
    return json({ url: j.url });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
