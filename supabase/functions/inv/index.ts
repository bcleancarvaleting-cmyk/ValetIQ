// Invoice tracking links used in invoice emails.
// GET ?l=<invoice id>        → records "viewed" and forwards to the Stripe invoice page
// GET ?l=<invoice id>&px=1   → records "opened" (tiny image in the email)
import { createClient } from "npm:@supabase/supabase-js@2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const GIF = Uint8Array.from(atob("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"), (c) => c.charCodeAt(0));
const BOTS = /(bot|crawler|spider|preview|scanner|safelinks|proofpoint|mimecast|barracuda|facebookexternalhit|slackbot|whatsapp)/i;
Deno.serve(async (req) => {
  const u = new URL(req.url); const id = u.searchParams.get("l") || ""; const px = u.searchParams.get("px");
  const pixel = () => new Response(GIF, { headers: { "Content-Type": "image/gif", "Cache-Control": "no-store, max-age=0" } });
  if (!/^(in|cs)_[A-Za-z0-9_]+$/.test(id)) return px ? pixel() : new Response("Not found", { status: 404 });
  const { data: l } = await db.from("payment_links").select("id,url,opened_at,viewed_at,view_count").eq("id", id).maybeSingle();
  if (!l) return px ? pixel() : new Response("Not found", { status: 404 });
  const now = new Date().toISOString(); const bot = BOTS.test(req.headers.get("user-agent") || "");
  if (px) { if (!l.opened_at && !bot) await db.from("payment_links").update({ opened_at: now }).eq("id", id); return pixel(); }
  if (!bot) await db.from("payment_links").update({ viewed_at: l.viewed_at || now, opened_at: l.opened_at || now, view_count: (l.view_count || 0) + 1 }).eq("id", id);
  return new Response(null, { status: 302, headers: { Location: l.url, "Cache-Control": "no-store" } });
});
