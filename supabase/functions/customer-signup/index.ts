// Creates a customer login straight away (no confirmation email needed, so the email rate limit can't block sign-ups).
// POST { business_id, email, password, first, last, mobile } → { ok } | { exists: true } | { error }
// The browser then signs in with the same email + password.
import { createClient } from "npm:@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const b = await req.json();
    const email = String(b.email || "").trim().toLowerCase(); const password = String(b.password || "");
    const first = String(b.first || "").trim().slice(0, 60); const last = String(b.last || "").trim().slice(0, 60); const mobile = String(b.mobile || "").trim().slice(0, 30);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 200) return json({ error: "Please add a valid email" }, 400);
    if (password.length < 8 || password.length > 72) return json({ error: "Password must be at least 8 characters" }, 400);
    if (!first) return json({ error: "Please add your first name" }, 400);
    if (mobile.replace(/\D/g, "").length < 10) return json({ error: "Please add your mobile number" }, 400);
    const { data: biz } = await db.from("businesses").select("id").eq("id", b.business_id).maybeSingle();
    if (!biz) return json({ error: "Business not found" }, 404);
    const { error } = await db.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: { first_name: first, last_name: last, mobile },
      app_metadata: { auto_confirmed: true, signup_business: biz.id },
    });
    if (error) {
      if ((error as any).code === "email_exists" || /already|registered|exists/i.test(error.message)) return json({ exists: true });
      return json({ error: error.message }, 400);
    }
    return json({ ok: true });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
