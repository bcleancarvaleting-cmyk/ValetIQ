// Pulls the latest Google + Facebook reviews into ext_reviews and saves the official star ratings/counts
// into businesses.settings.reviewStats. Runs daily from pg_cron (x-push-secret) or from the admin app (owner JWT).
// POST { business_id }  →  { google: {...}|null, facebook: {...}|null, errors: [] }
import { createClient } from "npm:@supabase/supabase-js@2";
const URL_ = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-secret", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function google(biz: string, key: string, placeId: string) {
  const r = await fetch(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?languageCode=en`, {
    headers: { "X-Goog-Api-Key": key, "X-Goog-FieldMask": "displayName,rating,userRatingCount,reviews,googleMapsUri" },
  });
  const j: any = await r.json();
  if (!r.ok) throw new Error("Google: " + (j?.error?.message || r.status));
  const rows = (j.reviews || []).map((v: any) => ({
    business_id: biz, source: "google", ext_id: v.name || `${v.authorAttribution?.displayName}-${v.publishTime}`,
    author: v.authorAttribution?.displayName || "Google user", avatar: v.authorAttribution?.photoUri || null,
    rating: Math.min(5, Math.max(1, Math.round(v.rating || 5))), text: (v.text?.text || v.originalText?.text || "").trim(),
    posted_at: v.publishTime || null, url: v.authorAttribution?.uri || j.googleMapsUri || null, synced_at: new Date().toISOString(),
  }));
  if (rows.length) { const { error } = await db.from("ext_reviews").upsert(rows, { onConflict: "business_id,source,ext_id", ignoreDuplicates: false }); if (error) throw error; }
  // Google only allows short-term caching of review content: drop anything not refreshed for 30 days
  await db.from("ext_reviews").delete().eq("business_id", biz).eq("source", "google").lt("synced_at", new Date(Date.now() - 30 * 864e5).toISOString());
  return { rating: j.rating ?? null, count: j.userRatingCount ?? 0, url: j.googleMapsUri || null, name: j.displayName?.text || "", fetched: rows.length };
}

async function facebook(biz: string, token: string) {
  const G = "https://graph.facebook.com/v21.0";
  const pr = await fetch(`${G}/me?fields=id,name,link,overall_star_rating,rating_count&access_token=${encodeURIComponent(token)}`);
  const p: any = await pr.json();
  if (!pr.ok) throw new Error("Facebook: " + (p?.error?.message || pr.status));
  const rr = await fetch(`${G}/${p.id}/ratings?fields=created_time,recommendation_type,rating,review_text,reviewer{name,picture}&limit=100&access_token=${encodeURIComponent(token)}`);
  const rj: any = await rr.json();
  if (!rr.ok) throw new Error("Facebook reviews: " + (rj?.error?.message || rr.status));
  const rows = (rj.data || []).filter((v: any) => (v.review_text || "").trim()).map((v: any, i: number) => ({
    business_id: biz, source: "facebook", ext_id: `${v.reviewer?.id || v.reviewer?.name || "fb"}-${v.created_time || i}`,
    author: v.reviewer?.name || "Facebook user", avatar: v.reviewer?.picture?.data?.url || null,
    rating: v.rating ? Math.min(5, Math.max(1, +v.rating)) : (v.recommendation_type === "negative" ? 1 : 5),
    text: (v.review_text || "").trim(), posted_at: v.created_time || null, url: p.link || null, synced_at: new Date().toISOString(),
  }));
  if (rows.length) { const { error } = await db.from("ext_reviews").upsert(rows, { onConflict: "business_id,source,ext_id", ignoreDuplicates: false }); if (error) throw error; }
  return { rating: p.overall_star_rating ?? null, count: p.rating_count ?? (rj.data || []).length, url: p.link || null, name: p.name || "", fetched: rows.length };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const b = await req.json();
    const biz = b.business_id;
    if (!biz) return json({ error: "business_id required" }, 400);
    const secret = req.headers.get("x-push-secret");
    let allowed = false;
    if (secret) { const { data: h } = await db.rpc("get_push_config"); allowed = !!h && (h as any).push_hook === secret; }
    if (!allowed) {
      const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
      const { data: ok } = await userDb.rpc("is_member", { b: biz }); allowed = !!ok;
    }
    if (!allowed) return json({ error: "Not allowed" }, 403);

    const { data: keys } = await db.rpc("get_review_keys", { p_business: biz });
    const { data: row } = await db.from("businesses").select("settings").eq("id", biz).single();
    const st: any = row?.settings || {};
    const cfg = st.reviewLinks || {};
    const k: any = keys || {};
    const errors: string[] = [];
    const prev = st.reviewStats || {};
    let g = prev.google || null, f = prev.facebook || null;
    if (k.google_key && cfg.googlePlaceId) { try { g = await google(biz, k.google_key, cfg.googlePlaceId); } catch (e) { errors.push(String((e as Error).message || e)); } }
    else if (k.google_key) errors.push("Google: add your Place ID");
    if (k.fb_token) { try { f = await facebook(biz, k.fb_token); } catch (e) { errors.push(String((e as Error).message || e)); } }
    const stats = { google: g, facebook: f, synced_at: new Date().toISOString(), errors };
    // merge into settings without clobbering anything else
    const { data: fresh } = await db.from("businesses").select("settings").eq("id", biz).single();
    await db.from("businesses").update({ settings: { ...(fresh?.settings || {}), reviewStats: stats } }).eq("id", biz);
    return json(stats);
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
