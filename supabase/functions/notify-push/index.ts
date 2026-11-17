// Sends web-push alerts to the business owner's phone(s) when a notification is created.
// Called by the notifications_push database trigger (x-push-secret header).
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });
let cfg: Record<string, string> | null = null;
const TITLES: Record<string, string> = { registration: "👤 New registration", newBooking: "📅 New booking", newPayment: "💷 Payment received", test: "✅ Notifications are working" };
Deno.serve(async (req) => {
  try {
    if (!cfg) {
      const { data } = await db.rpc("get_push_config");
      cfg = (data || {}) as Record<string, string>;
      webpush.setVapidDetails("mailto:hello@bcleanvaleting.co.uk", cfg.vapid_public, cfg.vapid_private);
    }
    if (!cfg.push_hook || req.headers.get("x-push-secret") !== cfg.push_hook) return json({ error: "forbidden" }, 403);
    const { id } = await req.json();
    const { data: n } = await db.from("notifications").select("id,kind,text,booking_id,business_id,businesses(name,settings)").eq("id", id).single();
    if (!n) return json({ skipped: "not found" });
    if (!TITLES[n.kind]) return json({ skipped: "kind " + n.kind });
    const alerts = ((n as any).businesses?.settings?.adminAlerts) || {};
    if (n.kind !== "test" && alerts[n.kind] && alerts[n.kind].push === false) return json({ skipped: "switched off" });
    const { data: members } = await db.from("business_members").select("user_id").eq("business_id", n.business_id);
    const ids = (members || []).map((m: any) => m.user_id);
    if (!ids.length) return json({ sent: 0 });
    const { data: subs } = await db.from("push_subscriptions").select("*").in("user_id", ids);
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
