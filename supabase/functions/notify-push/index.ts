// Sends web-push alerts to the business owner's phone(s) when a notification is created.
// Called by the notifications_push database trigger (x-push-secret header).
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });
let cfg: Record<string, string> | null = null;
const TITLES: Record<string, string> = { registration: "👤 New registration", newBooking: "📅 New booking", newPayment: "💷 Payment received", test: "✅ Notifications are working", referral: "🎁 Referral reward", checkup: "🛡 Coating check-up due", planPurchase: "🎟 Pre-paid plan bought", regularClash: "⚠️ Regular slot clash" };
const DEF: Record<string, { title: string; text: string }> = {
  confirmed: { title: "Booking confirmed", text: "Hi {name}, your {service} with {business} is confirmed for {date} at {time} (ref {ref})." },
  reminder: { title: "See you tomorrow", text: "Hi {name}, just a reminder that we'll be with you {date} at {time} for your {service}." },
  received: { title: "Payment received", text: "Hi {name}, thanks — we've received your payment of {amount} for booking {ref}." },
  review: { title: "How did we do? ⭐", text: "Hi {name}, thanks for choosing {business} today! If you're happy with your {service}, a quick review would mean the world to us." },
  checkup: { title: "Time for your coating check-up 🛡", text: "Hi {name}, your coating is due its check-up. Book a maintenance valet to keep your warranty valid and the protection performing." },
  rebook: { title: "Time for your next clean? 🚗", text: "Hi {name}, it's been a little while since your last clean with {business}. Want to book your next one?" },
  referral: { title: "You've earned {amount} 🎉", text: "Hi {name}, a friend you referred has just used {business} — {amount} has been added to your account and comes off your next booking." },
};
async function customerPush(b: any) {
  const { data: c } = await db.from("customers").select("id,first_name,notify_ok,business_id,businesses(name,settings)").eq("id", b.customer).single();
  if (!c || !c.notify_ok) return { skipped: "no consent" };
  const biz: any = (c as any).businesses || {}; const M = biz.settings?.messages || {};
  const m = { ...(DEF[b.msg] || {}), ...(M[b.msg] || {}), ...(b.text ? { title: b.title || biz.name, text: b.text } : {}) } as any;
  if (!b.text && M[b.msg] && M[b.msg].on === false) return { skipped: "switched off" };
  if (!m.text) return { skipped: "no text" };
  let bk: any = null;
  if (b.booking) { const r = await db.from("bookings").select("id,ref,service_name,date,start_time,days,total").eq("id", b.booking).single(); bk = r.data; }
  const map: Record<string, string> = {
    name: c.first_name || "", business: biz.name || "", service: bk?.service_name || "", ref: bk?.ref || "",
    date: bk ? new Date(`${bk.date}T12:00:00`).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" }) : "",
    time: bk ? (bk.days > 0 ? "all day" : String(bk.start_time).slice(0, 5)) : "",
    amount: "£" + Number(b.amount ?? bk?.total ?? 0).toFixed(2),
  };
  const text = String(m.text).replace(/\{(\w+)\}/g, (x: string, k: string) => map[k] ?? "").split(b.text ? "\u0000" : "\n\n")[0].slice(0, b.text ? 600 : 300);
  const { data: subs } = await db.from("push_subscriptions").select("*").eq("customer_id", c.id);
  const title = String(m.title || biz.name).replace(/\{(\w+)\}/g, (x: string, k: string) => map[k] ?? "");
  const url = b.msg === "review" && biz.settings?.reviewUrl ? biz.settings.reviewUrl : (b.msg === "checkup" || b.msg === "rebook") ? "/?book=1" : "/account/" + (bk ? `#b=${bk.id}` : "");
  const payload = JSON.stringify({ title, body: text, url, tag: `${b.msg}-${b.booking || ""}` });
  let sent = 0;
  for (const s of subs || []) {
    try { await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 }); sent++; }
    catch (e: any) { if (e?.statusCode === 404 || e?.statusCode === 410) await db.from("push_subscriptions").delete().eq("id", s.id); }
  }
  return { sent };
}
Deno.serve(async (req) => {
  try {
    if (!cfg) {
      const { data } = await db.rpc("get_push_config");
      cfg = (data || {}) as Record<string, string>;
      webpush.setVapidDetails("mailto:hello@bcleanvaleting.co.uk", cfg.vapid_public, cfg.vapid_private);
    }
    if (!cfg.push_hook || req.headers.get("x-push-secret") !== cfg.push_hook) return json({ error: "forbidden" }, 403);
    const body = await req.json();
    if (body.customer) return json(await customerPush(body));
    const { id } = body;
    const { data: n } = await db.from("notifications").select("id,kind,text,booking_id,business_id,businesses(name,settings)").eq("id", id).single();
    if (!n) return json({ skipped: "not found" });
    if (!TITLES[n.kind]) return json({ skipped: "kind " + n.kind });
    const alerts = ((n as any).businesses?.settings?.adminAlerts) || {};
    if (n.kind !== "test" && alerts[n.kind] && alerts[n.kind].push === false) return json({ skipped: "switched off" });
    const { data: members } = await db.from("business_members").select("user_id").eq("business_id", n.business_id);
    const ids = (members || []).map((m: any) => m.user_id);
    if (!ids.length) return json({ sent: 0 });
    const { data: subs } = await db.from("push_subscriptions").select("*").in("user_id", ids).eq("role", "admin");
    const payload = JSON.stringify({ title: TITLES[n.kind], body: n.text, url: "/admin/" + (n.booking_id ? `#b=${n.booking_id}` : ""), tag: n.kind + "-" + n.id });
    let sent = 0; const errors: string[] = [];
    for (const s of subs || []) {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400, urgency: "high" });
        sent++;
      } catch (e: any) {
        errors.push(`${e?.statusCode || ""} ${e?.body || e?.message || e}`.slice(0, 200));
        if (e?.statusCode === 404 || e?.statusCode === 410) await db.from("push_subscriptions").delete().eq("id", s.id);
      }
    }
    return json({ sent, errors });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
