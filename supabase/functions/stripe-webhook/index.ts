// Stripe webhook: records payments made through payment links / checkout against the booking.
import { createClient } from "npm:@supabase/supabase-js@2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const enc = new TextEncoder();
async function verify(payload: string, header: string, secret: string) {
  const parts = Object.fromEntries(header.split(",").map((p) => p.split("=") as [string, string]));
  const t = parts["t"]; const sigs = header.split(",").filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  if (!t || !sigs.length) return false;
  if (Math.abs(Date.now() / 1000 - Number(t)) > 600) return false;
  const k = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(`${t}.${payload}`)));
  const hex = [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
  return sigs.includes(hex);
}
Deno.serve(async (req) => {
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const payload = await req.text();
  if (!secret || !(await verify(payload, req.headers.get("stripe-signature") || "", secret))) return new Response("Invalid signature", { status: 400 });
  const ev = JSON.parse(payload);
  if (ev.type === "checkout.session.completed" && ev.data?.object?.payment_status === "paid") {
    const s = ev.data.object;
    let bookingId = s.metadata?.booking_id; let businessId = s.metadata?.business_id;
    if ((!bookingId || !businessId) && s.payment_link) {
      const { data: l } = await db.from("payment_links").select("booking_id,business_id").eq("id", s.payment_link).single();
      bookingId = l?.booking_id; businessId = l?.business_id;
    }
    if (bookingId && businessId) {
      const stripeId = s.payment_intent || s.id;
      const { data: dup } = await db.from("payments").select("id").eq("stripe_id", stripeId).limit(1);
      if (!dup || !dup.length) {
        const { data: b } = await db.from("bookings").select("ref,customer_id,customers(first_name,last_name)").eq("id", bookingId).single();
        const amount = (s.amount_total || 0) / 100;
        await db.from("payments").insert({ business_id: businessId, booking_id: bookingId, customer_id: b?.customer_id, type: "balance", amount, method: "Card (Stripe)", stripe_id: stripeId });
        if (s.payment_link) await db.from("payment_links").update({ paid_at: new Date().toISOString() }).eq("id", s.payment_link);
        const c: any = (b as any)?.customers || {};
        await db.from("notifications").insert({ business_id: businessId, kind: "newPayment", text: `Payment received — £${amount.toFixed(2)} from ${c.first_name || ""} ${c.last_name || ""} (${b?.ref || ""})`, booking_id: bookingId });
      }
    }
  }
  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
