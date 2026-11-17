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
    if (ev.type === "checkout.session.completed" && o.payment_status === "paid" && o.metadata?.type === "plan") {
      const m = o.metadata; const sid = o.payment_intent || o.id;
      const { data: dup } = await db.from("payments").select("id").eq("stripe_id", sid).limit(1);
      if (!dup || !dup.length) {
        const { data: p } = await db.from("plans").select("*").eq("id", m.plan_id).single();
        const n = Number(m.count); const end = new Date(); end.setMonth(end.getMonth() + Number(p?.months || 12));
        const { data: sub } = await db.from("plan_subscriptions").insert({ business_id: m.business_id, customer_id: m.customer_id, plan_id: m.plan_id, visits: n, credits: n, size: Number(m.size) || 0,
          amount: (o.amount_total || 0) / 100, end_date: end.toISOString().slice(0, 10), eligible: p?.eligible?.length ? p.eligible : (p?.service_id ? [p.service_id] : []), auto_renew: false, status: "active", note: "Bought online" }).select().single();
        await db.from("payments").insert({ business_id: m.business_id, customer_id: m.customer_id, subscription_id: sub?.id, type: "membership", amount: (o.amount_total || 0) / 100, method: "Card (Stripe)", stripe_id: sid });
        if (sub) await db.from("credit_ledger").insert({ business_id: m.business_id, subscription_id: sub.id, delta: n, note: "Bought online" });
        await db.from("customers").update({ maintenance_ok: true }).eq("id", m.customer_id);
        const { data: c } = await db.from("customers").select("first_name,last_name").eq("id", m.customer_id).single();
        await db.from("notifications").insert({ business_id: m.business_id, kind: "newPayment", text: `Pre-paid plan bought — ${p?.name || "plan"} (${n} washes, £${((o.amount_total || 0) / 100).toFixed(2)}) by ${c?.first_name || ""} ${c?.last_name || ""}` });
      }
    } else if (ev.type === "checkout.session.completed" && o.payment_status === "paid") {
      let bookingId = o.metadata?.booking_id; let businessId = o.metadata?.business_id;
      if ((!bookingId || !businessId) && o.payment_link) {
        const { data: l } = await db.from("payment_links").select("booking_id,business_id").eq("id", o.payment_link).single();
        bookingId = l?.booking_id; businessId = l?.business_id;
      }
      if (bookingId && businessId) await record(bookingId, businessId, o.payment_intent || o.id, (o.amount_total || 0) / 100, o.metadata?.type === "deposit" ? "deposit" : o.metadata?.type === "full" ? "full" : "balance", o.payment_link || o.id);
    } else if (ev.type === "invoice.paid" && o.amount_paid > 0 && (o.subscription || o.parent?.subscription_details)) {
      // monthly membership payment → add this month's washes
      const subId = o.subscription || o.parent?.subscription_details?.subscription;
      let meta: any = o.parent?.subscription_details?.metadata || o.subscription_details?.metadata || {};
      if (!meta.membership_id && subId) { const k = (await keysFor(biz)).secret; if (k) { const r = await fetch(`https://api.stripe.com/v1/subscriptions/${subId}`, { headers: { Authorization: `Bearer ${k}` } }); const j = await r.json(); meta = j.metadata || {}; } }
      if (meta.type === "membership" && meta.membership_id) {
        const { data: dup } = await db.from("payments").select("id").eq("stripe_id", o.id).limit(1);
        if (!dup || !dup.length) {
          const { data: m } = await db.from("memberships").select("*").eq("id", meta.membership_id).single();
          const n = Number(m?.washes_per_month || 1); const pe = o.lines?.data?.[0]?.period?.end || o.period_end || Math.floor(Date.now() / 1000) + 31 * 86400;
          const end = new Date((pe + 31 * 86400) * 1000).toISOString().slice(0, 10);
          const { data: ex } = await db.from("plan_subscriptions").select("*").eq("stripe_sub_id", subId).maybeSingle();
          let sid = ex?.id;
          if (ex) await db.from("plan_subscriptions").update({ credits: ex.credits + n, visits: ex.visits + n, end_date: end > ex.end_date ? end : ex.end_date, status: "active", auto_renew: true, amount: Number(ex.amount) + o.amount_paid / 100 }).eq("id", ex.id);
          else { const { data: ns } = await db.from("plan_subscriptions").insert({ business_id: meta.business_id, customer_id: meta.customer_id, membership_id: m?.id, stripe_sub_id: subId, visits: n, credits: n, amount: o.amount_paid / 100, end_date: end, eligible: m?.eligible || [], auto_renew: true, status: "active", note: `Membership: ${m?.name || ""}` }).select().single(); sid = ns?.id; }
          if (sid) await db.from("credit_ledger").insert({ business_id: meta.business_id, subscription_id: sid, delta: n, note: "Monthly membership" });
          await db.from("payments").insert({ business_id: meta.business_id, customer_id: meta.customer_id, subscription_id: sid, type: "membership", amount: o.amount_paid / 100, method: "Stripe (membership)", stripe_id: o.id });
          await db.from("customers").update({ maintenance_ok: true }).eq("id", meta.customer_id);
          const { data: c } = await db.from("customers").select("first_name,last_name").eq("id", meta.customer_id).single();
          await db.from("notifications").insert({ business_id: meta.business_id, kind: "newPayment", text: `Membership ${ex ? "renewed" : "started"} — ${m?.name || ""} £${(o.amount_paid / 100).toFixed(2)} from ${c?.first_name || ""} ${c?.last_name || ""}` });
        }
      }
    } else if (ev.type === "invoice.paid" && o.metadata?.type === "statement" && o.amount_paid > 0) {
      const { data: dup } = await db.from("payments").select("id").like("stripe_id", `${o.id}:%`).limit(1);
      if (!dup || !dup.length) {
        const { data: bks } = await db.from("bookings").select("id,total,customer_id").eq("statement_id", o.id);
        for (const x of bks || []) {
          const { data: pays } = await db.from("payments").select("amount").eq("booking_id", x.id);
          const owed = Number(x.total) - (pays || []).reduce((a: number, p: any) => a + Number(p.amount), 0);
          if (owed > 0) await db.from("payments").insert({ business_id: o.metadata.business_id, booking_id: x.id, customer_id: x.customer_id, type: "balance", amount: owed, method: "Monthly statement", stripe_id: `${o.id}:${x.id}` });
        }
        await db.from("notifications").insert({ business_id: o.metadata.business_id, kind: "newPayment", text: `Monthly statement paid — £${(o.amount_paid / 100).toFixed(2)} (${o.metadata.month})` });
      }
    } else if (ev.type === "customer.subscription.deleted") {
      await db.from("plan_subscriptions").update({ auto_renew: false, note: "Membership cancelled — washes usable until expiry" }).eq("stripe_sub_id", o.id);
      const meta = o.metadata || {};
      if (meta.business_id) { const { data: c } = await db.from("customers").select("first_name,last_name").eq("id", meta.customer_id).single(); await db.from("notifications").insert({ business_id: meta.business_id, kind: "newPayment", text: `Membership cancelled — ${c?.first_name || ""} ${c?.last_name || ""}` }); }
    } else if (ev.type === "invoice.paid" && o.metadata?.booking_id && o.amount_paid > 0) {
      await record(o.metadata.booking_id, o.metadata.business_id, o.id, o.amount_paid / 100, "balance", o.id);
    }
  } catch (e) { console.error(e); return new Response("error", { status: 500 }); }
  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
