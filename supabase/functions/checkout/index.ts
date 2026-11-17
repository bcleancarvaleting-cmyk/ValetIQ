// Public: Stripe-hosted Checkout for a booking deposit (or full amount) right after the customer books online.
// POST { booking_id, return_url? }  → { url }
import { createClient } from "npm:@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("STRIPE_SECRET_KEY");
    if (!key) return json({ error: "Card payments aren't switched on yet." }, 400);
    const { booking_id, full } = await req.json();
    const { data: b } = await db.from("bookings").select("id,ref,business_id,total,status,service_name,date,start_time,created_at,services(deposit_pct),customers(email),businesses(name,settings)").eq("id", booking_id).single();
    if (!b) return json({ error: "Booking not found" }, 404);
    if (b.status !== "Pending") return json({ error: "This booking doesn't need a payment right now." }, 400);
    if (Date.now() - new Date(b.created_at).getTime() > 2 * 3600e3) return json({ error: "This booking has expired — please book again." }, 400);
    const st: any = (b as any).businesses?.settings || {};
    const pct = Number((b as any).services?.deposit_pct ?? st.depositPct ?? 20);
    const amount = full ? Number(b.total) : Math.round(Number(b.total) * pct) / 100;
    const pence = Math.round(amount * 100);
    if (pence < 30) return json({ error: "No payment needed" }, 400);
    const site = Deno.env.get("SITE_URL") || "https://bcleanvaleting.co.uk";
    const email = (b as any).customers?.email;
    const when = new Date(`${b.date}T00:00:00`).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
    const p: Record<string, string> = {
      mode: "payment", "line_items[0][quantity]": "1",
      "line_items[0][price_data][currency]": "gbp", "line_items[0][price_data][unit_amount]": String(pence),
      "line_items[0][price_data][product_data][name]": `${full ? "Payment" : "Deposit"} — ${b.service_name}`,
      "line_items[0][price_data][product_data][description]": `${when} at ${String(b.start_time).slice(0, 5)} · ref ${b.ref}`,
      success_url: `${site}/account/?paid=${encodeURIComponent(b.ref)}`, cancel_url: `${site}/?cancelled=${encodeURIComponent(b.ref)}`,
      expires_at: String(Math.floor(Date.now() / 1000) + 1800),
      "metadata[type]": full ? "full" : "deposit", "metadata[booking_id]": b.id, "metadata[business_id]": b.business_id, "metadata[ref]": b.ref,
      "payment_intent_data[metadata][booking_id]": b.id, "payment_intent_data[description]": `${(b as any).businesses?.name || ""} ${b.ref}`,
      ...(email && !/@no-email\.invalid$/i.test(email) ? { customer_email: email } : {}),
    };
    const r = await fetch("https://api.stripe.com/v1/checkout/sessions", { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/x-www-form-urlencoded", "Idempotency-Key": `co-${b.id}-${pence}-${Math.floor(Date.now() / 600000)}` }, body: new URLSearchParams(p) });
    const s = await r.json(); if (!r.ok) throw new Error(s?.error?.message || "Stripe error");
    return json({ url: s.url });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
