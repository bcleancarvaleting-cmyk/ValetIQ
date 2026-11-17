// Business-only: creates a Stripe Payment Link for the outstanding balance on a booking.
// POST { booking_id }  with the signed-in admin's JWT.
import { createClient } from "npm:@supabase/supabase-js@2";
const URL_ = Deno.env.get("SUPABASE_URL")!;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
async function stripe(path: string, params: Record<string, string>, key: string) {
  const r = await fetch(`https://api.stripe.com/v1/${path}`, { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(params) });
  const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || "Stripe error"); return j;
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("STRIPE_SECRET_KEY");
    if (!key) return json({ error: "Stripe isn't connected yet — add your Stripe key in Supabase first." }, 400);
    const auth = req.headers.get("Authorization") || "";
    const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
    const { booking_id } = await req.json();
    // RLS: only members of the booking's business can read it
    const { data: b, error } = await userDb.from("bookings").select("id,ref,business_id,total,status,service_name,date,customers(email,first_name),businesses(name,slug)").eq("id", booking_id).single();
    if (error || !b) return json({ error: "Booking not found" }, 404);
    if (b.status === "Cancelled") return json({ error: "This booking is cancelled" }, 400);
    const admin = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: pays } = await admin.from("payments").select("amount").eq("booking_id", b.id);
    const paid = (pays || []).reduce((s: number, p: any) => s + Number(p.amount), 0);
    const owed = Math.round((Number(b.total) - paid) * 100);
    if (owed < 30) return json({ error: "Nothing left to pay on this booking" }, 400);
    // reuse an unpaid link for the same amount
    const { data: existing } = await admin.from("payment_links").select("*").eq("booking_id", b.id).is("paid_at", null).eq("amount_pence", owed).order("created_at", { ascending: false }).limit(1);
    if (existing && existing[0]) return json({ url: existing[0].url, amount: owed / 100, reused: true });
    const biz: any = (b as any).businesses || {}; const cust: any = (b as any).customers || {};
    const site = Deno.env.get("SITE_URL") || "https://bcleanvaleting.co.uk";
    const price = await stripe("prices", { currency: "gbp", unit_amount: String(owed), "product_data[name]": `${biz.name || "Valet"} — ${b.service_name} (${b.ref})` }, key);
    const params: Record<string, string> = {
      "line_items[0][price]": price.id, "line_items[0][quantity]": "1",
      "metadata[booking_id]": b.id, "metadata[business_id]": b.business_id, "metadata[ref]": b.ref,
      "payment_intent_data[metadata][booking_id]": b.id, "payment_intent_data[metadata][business_id]": b.business_id,
      "restrictions[completed_sessions][limit]": "1",
      "after_completion[type]": "redirect", "after_completion[redirect][url]": `${site}/?paid=${encodeURIComponent(b.ref)}`,
    };
    const link = await stripe("payment_links", params, key);
    await admin.from("payment_links").insert({ id: link.id, business_id: b.business_id, booking_id: b.id, amount_pence: owed, url: link.url });
    return json({ url: link.url, amount: owed / 100 });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
