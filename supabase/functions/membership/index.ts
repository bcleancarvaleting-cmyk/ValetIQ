// Monthly memberships (Stripe Billing — card or Bacs Direct Debit, whatever is switched on in Stripe),
// the Stripe customer portal (change card / cancel), and monthly statements for business accounts.
// POST { action: "checkout", membership_id }      — signed-in customer → { url }
// POST { action: "portal" }  + business_id         — signed-in customer → { url }
// POST { action: "statement", business_id, customer_id, month: "2026-11" } — business owner → { url }
import { createClient } from "npm:@supabase/supabase-js@2";
const URL_ = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
const realEmail = (e?: string) => !!e && /^\S+@\S+\.\S+$/.test(e) && !/@no-email\.invalid$/i.test(e);
async function keyFor(biz: string) {
  const { data } = await db.rpc("get_business_stripe", { p_business: biz }); if ((data as any)?.secret) return (data as any).secret as string;
  const { data: v } = await db.rpc("get_stripe_config"); return (Deno.env.get("STRIPE_SECRET_KEY") || (v as any)?.STRIPE_SECRET_KEY) as string | undefined;
}
async function stripe(method: string, path: string, key: string, params?: Record<string, string>) {
  const r = await fetch(`https://api.stripe.com/v1/${path}`, { method, headers: { Authorization: `Bearer ${key}`, ...(params ? { "Content-Type": "application/x-www-form-urlencoded" } : {}) }, body: params ? new URLSearchParams(params) : undefined });
  const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || "Stripe error"); return j;
}
async function stripeCustomer(key: string, c: any, email?: string) {
  const found = await stripe("GET", `customers/search?query=${encodeURIComponent(`metadata['valetiq_customer']:'${c.id}'`)}`, key);
  if (found.data?.[0]) return found.data[0];
  return await stripe("POST", "customers", key, { name: (c.company_name || `${c.first_name || ""} ${c.last_name || ""}`).trim() || "Customer", ...(realEmail(email) ? { email: email! } : {}), ...(c.mobile ? { phone: c.mobile } : {}), "metadata[valetiq_customer]": c.id, "metadata[business_id]": c.business_id });
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
    const { data: { user } } = await userDb.auth.getUser();
    if (!user) return json({ error: "Please sign in" }, 401);
    const b = await req.json();
    const site = Deno.env.get("SITE_URL") || "https://bcleanvaleting.co.uk";
    if (b.action === "checkout") {
      const { data: m } = await db.from("memberships").select("*, businesses(name)").eq("id", b.membership_id).eq("active", true).single();
      if (!m) return json({ error: "That membership isn't available" }, 404);
      const { data: c } = await db.from("customers").select("*").eq("business_id", m.business_id).eq("user_id", user.id).maybeSingle();
      if (!c) return json({ error: "Please finish creating your account first" }, 400);
      const { data: ex } = await db.from("plan_subscriptions").select("id").eq("customer_id", c.id).eq("membership_id", m.id).eq("status", "active").eq("auto_renew", true).limit(1);
      if (ex && ex.length) return json({ error: "You're already on this membership — manage it from your account" }, 400);
      const key = await keyFor(m.business_id); if (!key) return json({ error: "Payments aren't switched on yet" }, 400);
      const cus = await stripeCustomer(key, c, user.email || c.email);
      const s = await stripe("POST", "checkout/sessions", key, {
        mode: "subscription", customer: cus.id,
        "line_items[0][quantity]": "1", "line_items[0][price_data][currency]": "gbp", "line_items[0][price_data][unit_amount]": String(Math.round(Number(m.price_monthly) * 100)),
        "line_items[0][price_data][recurring][interval]": "month", "line_items[0][price_data][product_data][name]": `${m.name} — ${m.washes_per_month} wash${m.washes_per_month > 1 ? "es" : ""} a month`,
        "subscription_data[metadata][type]": "membership", "subscription_data[metadata][membership_id]": m.id, "subscription_data[metadata][customer_id]": c.id, "subscription_data[metadata][business_id]": m.business_id,
        "subscription_data[description]": `${(m as any).businesses?.name || ""} ${m.name}`,
        success_url: `${site}/account/?member=joined`, cancel_url: `${site}/account/`,
      });
      return json({ url: s.url });
    }
    if (b.action === "portal") {
      const { data: c } = await db.from("customers").select("*").eq("business_id", b.business_id).eq("user_id", user.id).maybeSingle();
      if (!c) return json({ error: "Account not found" }, 404);
      const key = await keyFor(c.business_id); if (!key) return json({ error: "Payments aren't switched on yet" }, 400);
      const cus = await stripeCustomer(key, c, user.email || c.email);
      const p = await stripe("POST", "billing_portal/sessions", key, { customer: cus.id, return_url: `${site}/account/` });
      return json({ url: p.url });
    }
    if (b.action === "statement") {
      const { data: ok } = await userDb.rpc("is_member", { b: b.business_id }); if (!ok) return json({ error: "Not allowed" }, 403);
      const { data: c } = await db.from("customers").select("*").eq("id", b.customer_id).eq("business_id", b.business_id).single();
      if (!c) return json({ error: "Customer not found" }, 404);
      const to = realEmail(c.invoice_email) ? c.invoice_email : c.email; if (!realEmail(to)) return json({ error: "Add an invoice email for this customer first" }, 400);
      const [y, mo] = String(b.month).split("-").map(Number); const from = `${y}-${String(mo).padStart(2, "0")}-01`; const to_ = new Date(Date.UTC(y, mo, 0)).toISOString().slice(0, 10);
      const { data: bks } = await db.from("bookings").select("id,ref,date,service_name,total,cars,status").eq("customer_id", c.id).gte("date", from).lte("date", to_).neq("status", "Cancelled").is("statement_id", null).order("date");
      const { data: pays } = await db.from("payments").select("booking_id,amount").in("booking_id", (bks || []).map((x: any) => x.id).concat(["00000000-0000-0000-0000-000000000000"]));
      const rows = (bks || []).map((x: any) => ({ ...x, owed: Math.round((Number(x.total) - (pays || []).filter((p: any) => p.booking_id === x.id).reduce((a: number, p: any) => a + Number(p.amount), 0)) * 100) })).filter((x: any) => x.owed > 0);
      if (!rows.length) return json({ error: "Nothing unpaid for that month" }, 400);
      const key = await keyFor(c.business_id); if (!key) return json({ error: "Payments aren't switched on yet" }, 400);
      const cus = await stripeCustomer(key, c, to); if (cus.email !== to) await stripe("POST", `customers/${cus.id}`, key, { email: to });
      const { data: biz } = await db.from("businesses").select("name,settings").eq("id", c.business_id).single(); const I: any = (biz as any)?.settings?.invoice || {};
      const monthName = new Date(`${from}T12:00:00`).toLocaleDateString("en-GB", { month: "long", year: "numeric" });
      const inv = await stripe("POST", "invoices", key, { customer: cus.id, collection_method: "send_invoice", days_until_due: String(Math.max(Number(I.dueDays ?? 30), 7)), auto_advance: "false", pending_invoice_items_behavior: "exclude",
        description: `${c.company_name || c.first_name} — valeting for ${monthName}`, footer: [I.sortCode && I.accNo ? `Bank transfer: ${I.accName ? I.accName + " · " : ""}Sort code ${I.sortCode} · Account ${I.accNo}` : "", I.thanks || `Thanks for using ${(biz as any)?.name}`].filter(Boolean).join("\n\n"),
        "metadata[type]": "statement", "metadata[business_id]": c.business_id, "metadata[customer_id]": c.id, "metadata[month]": b.month });
      for (const x of rows) {
        const reg = (x.cars || []).map((v: any) => v.reg).filter(Boolean).join(", ");
        await stripe("POST", "invoiceitems", key, { customer: cus.id, invoice: inv.id, currency: "gbp", amount: String(x.owed), description: `${new Date(`${x.date}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short" })} · ${x.service_name}${reg ? " · " + reg : ""} · ${x.ref}` });
      }
      const fin = await stripe("POST", `invoices/${inv.id}/finalize`, key, { auto_advance: "true" });
      try { await stripe("POST", `invoices/${inv.id}/send`, key, {}); } catch (_) { /* link still works */ }
      await db.from("bookings").update({ statement_id: fin.id }).in("id", rows.map((x: any) => x.id));
      return json({ url: fin.hosted_invoice_url, pdf: fin.invoice_pdf, total: fin.amount_due / 100, count: rows.length });
    }
    return json({ error: "Unknown action" }, 400);
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
