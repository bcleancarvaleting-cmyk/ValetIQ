// Stripe webhook: records deposits (Checkout) and balance payments (Invoices / older Payment Links) against the booking.
// Events: checkout.session.completed, invoice.paid
import { createClient } from "npm:@supabase/supabase-js@2";

// Stripe keys: entered per business in the admin app (Settings → Payments); falls back to the platform Vault keys
async function keysFor(biz?: string): Promise<{ secret?: string; whsec?: string }> {
  const a = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  if (biz) { const { data } = await a.rpc("get_business_stripe", { p_business: biz }); if (data && (data as any).secret) return { secret: (data as any).secret, whsec: (data as any).whsec }; }
  const { data: v } = await a.rpc("get_stripe_config"); const g: any = v || {};
  return { secret: Deno.env.get("STRIPE_SECRET_KEY") || g.STRIPE_SECRET_KEY, whsec: Deno.env.get("STRIPE_WEBHOOK_SECRET") || g.STRIPE_WEBHOOK_SECRET };
}
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const enc = new TextEncoder();
async function verify(payload: string, header: string, secret: string) {
  const t = header.split(",").find((p) => p.startsWith("t="))?.slice(2); const sigs = header.split(",").filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  if (!t || !sigs.length) return false;
  if (Math.abs(Date.now() / 1000 - Number(t)) > 600) return false;
  const k = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(`${t}.${payload}`)));
  const hex = [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
  return sigs.includes(hex);
}
async function record(bookingId: string, businessId: string, stripeId: string, amount: number, type: string, linkId?: string) {
  const { data: dup } = await db.from("payments").select("id").eq("stripe_id", stripeId).limit(1);
  if (dup && dup.length) return;
  const { data: b } = await db.from("bookings").select("ref,status,customer_id,customers(first_name,last_name)").eq("id", bookingId).single();
  if (!b) return;
  await db.from("payments").insert({ business_id: businessId, booking_id: bookingId, customer_id: b.customer_id, type, amount, method: "Card (Stripe)", stripe_id: stripeId });
  if (b.status === "Pending") await db.from("bookings").update({ status: "Booked" }).eq("id", bookingId);
  if (linkId) await db.from("payment_links").update({ paid_at: new Date().toISOString() }).eq("id", linkId);
  const c: any = (b as any).customers || {};
  const label = type === "deposit" ? "Deposit paid" : "Payment received";
  await db.from("notifications").insert({ business_id: businessId, kind: "newPayment", text: `${label} — £${amount.toFixed(2)} from ${c.first_name || ""} ${c.last_name || ""} (${b.ref})`.replace(/\s+/g, " "), booking_id: bookingId });
}
Deno.serve(async (req) => {
  const biz = new URL(req.url).searchParams.get("b") || undefined;
  const payload = await req.text(); const sig = req.headers.get("stripe-signature") || "";
  const k1 = await keysFor(biz); let ok = !!k1.whsec && await verify(payload, sig, k1.whsec!);
  if (!ok && biz) { const k2 = await keysFor(undefined); ok = !!k2.whsec && await verify(payload, sig, k2.whsec!); }
  if (!ok) return new Response("Invalid signature", { status: 400 });
  const ev = JSON.parse(payload); const o = ev.data?.object || {};
  try {
    if (ev.type === "checkout.session.completed" && o.payment_status === "paid") {
      let bookingId = o.metadata?.booking_id; let businessId = o.metadata?.business_id;
      if ((!bookingId || !businessId) && o.payment_link) {
        const { data: l } = await db.from("payment_links").select("booking_id,business_id").eq("id", o.payment_link).single();
        bookingId = l?.booking_id; businessId = l?.business_id;
      }
      if (bookingId && businessId) await record(bookingId, businessId, o.payment_intent || o.id, (o.amount_total || 0) / 100, o.metadata?.type === "deposit" ? "deposit" : o.metadata?.type === "full" ? "full" : "balance", o.payment_link || o.id);
    } else if (ev.type === "invoice.paid" && o.metadata?.booking_id && o.amount_paid > 0) {
      await record(o.metadata.booking_id, o.metadata.business_id, o.id, o.amount_paid / 100, "balance", o.id);
    }
  } catch (e) { console.error(e); return new Response("error", { status: 500 }); }
  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
