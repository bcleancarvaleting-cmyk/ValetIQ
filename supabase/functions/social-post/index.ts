// Writes an Instagram/Facebook caption for a before & after. Uses Claude when an AI key is saved
// in the admin app (Settings → ✨ AI captions); otherwise a built-in writer so it always works.
// POST { business_id, gallery_id, tone? } with the owner's JWT → { text, ai }
import { createClient } from "npm:@supabase/supabase-js@2";
const URL_ = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
const pick = <T,>(a: T[]) => a[Math.floor(Math.random() * a.length)];
const tag = (s: string) => "#" + s.replace(/[^A-Za-z0-9]/g, "");
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
    const b = await req.json();
    const { data: ok } = await userDb.rpc("is_member", { b: b.business_id }); if (!ok) return json({ error: "Not allowed" }, 403);
    const { data: g } = await db.from("gallery_items").select("*").eq("id", b.gallery_id).eq("business_id", b.business_id).single();
    if (!g) return json({ error: "Gallery item not found" }, 404);
    const { data: biz } = await db.from("businesses").select("name,settings").eq("id", b.business_id).single();
    const st: any = biz?.settings || {}; const so = st.social || {};
    let bk: any = null; if (g.booking_id) bk = (await db.from("bookings").select("service_name,cars,notes").eq("id", g.booking_id).maybeSingle()).data;
    const car = ((bk?.cars || [])[0]) || {}; const carName = [car.make, car.model].filter(Boolean).join(" ");
    const service = (bk?.service_name || "").replace(/ ×\d+$/, "").replace(/ — .*/, "");
    const site = (st.siteUrl || "https://bcleanvaleting.co.uk").replace(/^https?:\/\//, "").replace(/\/$/, "");
    const when = g.done_on ? new Date(`${g.done_on}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "long" }) : "";
    const contact = [`📲 Book online: ${site}`, st.phone ? `📞 ${st.phone}` : "", st.whatsapp && st.whatsapp !== st.phone ? `💬 WhatsApp ${st.whatsapp}` : ""].filter(Boolean).join("\n");
    const town = (g.location || "").split(",")[0].trim();
    const tags = [...new Set([tag(biz?.name || "valeting"), "#carvaleting", "#cardetailing", "#mobilevaleting", "#beforeandafter", town ? tag(town) : "", "#kent", service ? tag(service) : "", carName ? tag(car.make || "") : ""].filter((t) => t && t.length > 2))].slice(0, 10).join(" ");
    const facts = { business: biz?.name, title: g.title, service, car: carName, location: g.location, date: when, website: site, phone: st.phone || "", tone: b.tone || "friendly, confident, local" };
    const key = (await db.rpc("get_business_ai", { p_business: b.business_id })).data as string | null;
    if (key) {
      try {
        const r = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
          body: JSON.stringify({ model: "claude-haiku-5-5", max_tokens: 500, messages: [{ role: "user", content:
`Write an Instagram/Facebook caption for a UK mobile car valeting business posting a before & after photo.
Facts (only use these, never invent prices, products or claims): ${JSON.stringify(facts)}
Style: ${facts.tone}. British English. 2 short paragraphs, 3-5 tasteful emojis, a hook first line, a clear call to book. Mention the area and date naturally if given. No hashtags and no contact details — I add those. Plain text only.` }] }) });
        const j = await r.json();
        const text = (j?.content || []).map((c: any) => c.text || "").join("").trim();
        if (r.ok && text) return json({ ai: true, text: `${text}\n\n${contact}\n\n${tags}` });
      } catch (_) { /* fall back */ }
    }
    const hook = pick([`From tired to showroom ✨`, `Swipe-worthy results 👀`, `The difference a proper clean makes 🔥`, `Before ➡️ after. Need we say more? 😍`, `Another one transformed 💦`]);
    const it = carName ? `this ${carName}` : "this one"; const svc = service ? `our ${service}` : "the full treatment";
    const where = [town ? `in ${town}` : "", when ? `on ${when}` : ""].filter(Boolean).join(" ");
    const W = where ? " " + where : "";
    const up = (x: string) => x[0].toUpperCase() + x.slice(1);
    const mid = pick([`${up(it)} got ${svc}${W} — fully mobile, so we came to them with our own water on board.`, `We gave ${it} ${svc}${W}. Showroom finish, right on the driveway.`, `${up(it)}${W} after ${svc} — looking brand new again.`]);
    const cta = pick([`Want yours looking like this? Book online in seconds 👇`, `Spaces fill up fast — grab your slot online 👇`, `Treat your car — book your clean today 👇`]);
    return json({ ai: false, text: `${hook}\n\n${mid}\n\n${cta}\n${contact}\n\n${tags}` });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
