// Business-only: creates a Stripe Invoice for the balance on a booking (full price, minus the deposit already paid)
// and returns the hosted invoice page URL. Stripe also emails the invoice when the customer has a real email.
// POST { booking_id }  with the signed-in admin's JWT.
import { createClient } from "npm:@supabase/supabase-js@2";

let _sc: Record<string, string> | null = null;
async function stripeCfg(name: string): Promise<string | undefined> {
  const env = Deno.env.get(name); if (env) return env;
  if (!_sc || !_sc[name]) { const a = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!); const { data } = await a.rpc("get_stripe_config"); _sc = (data || {}) as Record<string, string>; }
  return _sc[name] || undefined;
}
const URL_ = Deno.env.get("SUPABASE_URL")!;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
async function stripe(method: string, path: string, key: string, params?: Record<string, string>, idem?: string) {
  const h: Record<string, string> = { Authorization: `Bearer ${key}` };
  if (params) h["Content-Type"] = "application/x-www-form-urlencoded";
  if (idem) h["Idempotency-Key"] = idem;
  const r = await fetch(`https://api.stripe.com/v1/${path}`, { method, headers: h, body: params ? new URLSearchParams(params) : undefined });
  const j = await r.json(); if (!r.ok) throw new Error(j?.error?.message || "Stripe error"); return j;
}
const realEmail = (e?: string) => !!e && !/@no-email\.invalid$/i.test(e);
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = await stripeCfg("STRIPE_SECRET_KEY");
    if (!key) return json({ error: "Stripe isn't connected yet — add your Stripe key in Supabase first." }, 400);
    const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
    const { booking_id, send } = await req.json();
    // RLS: only members of the booking's business can read it
    const { data: b, error } = await userDb.from("bookings").select("id,ref,business_id,total,status,service_name,date,start_time,customer_id,customers(id,email,first_name,last_name,mobile),businesses(name,settings)").eq("id", booking_id).single();
    if (error || !b) return json({ error: "Booking not found" }, 404);
    if (b.status === "Cancelled") return json({ error: "This booking is cancelled" }, 400);
    const admin = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: pays } = await admin.from("payments").select("amount").eq("booking_id", b.id);
    const paid = (pays || []).reduce((s: number, p: any) => s + Number(p.amount), 0);
    const owed = Math.round((Number(b.total) - paid) * 100);
    if (owed < 30) return json({ error: "Nothing left to pay on this booking" }, 400);
    const c: any = (b as any).customers || {}; const biz: any = (b as any).businesses || {};
    const hasEmail = realEmail(c.email);
    const I: any = biz.settings?.invoice || {};
    const thanks = I.thanks || `Thanks for using ${biz.name || "us"}`;
    const bank = I.sortCode && I.accNo ? `Prefer bank transfer? ${I.accName ? I.accName + " · " : ""}Sort code ${I.sortCode} · Account ${I.accNo} · Reference ${b.ref}` : "";
    const dueDays = Number(I.dueDays ?? 7);
    // reuse an open invoice / recent card page for the same amount
    const { data: existing } = await admin.from("payment_links").select("*").eq("booking_id", b.id).is("paid_at", null).eq("amount_pence", owed).order("created_at", { ascending: false }).limit(1);
    const ex = existing && existing[0];
    if (ex && (ex.id.startsWith("in_") || (ex.id.startsWith("cs_") && Date.now() - new Date(ex.created_at).getTime() < 22 * 3600e3))) return json({ url: ex.url, amount: owed / 100, reused: true });
    const when = new Date(`${b.date}T00:00:00`).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric" });
    if (!hasEmail) {
      // No email on file → Stripe-hosted card payment page for the balance (invoices need an email address)
      const site = Deno.env.get("SITE_URL") || "https://bcleanvaleting.co.uk";
      const desc = `${when} at ${String(b.start_time).slice(0, 5)} · ref ${b.ref}` + (paid > 0 ? ` · £${paid.toFixed(2)} already paid, thank you` : "");
      const s = await stripe("POST", "checkout/sessions", key, {
        mode: "payment", "line_items[0][quantity]": "1", "line_items[0][price_data][currency]": "gbp",
        "line_items[0][price_data][unit_amount]": String(owed),
        "line_items[0][price_data][product_data][name]": `${paid > 0 ? "Balance" : "Payment"} — ${b.service_name}`,
        "line_items[0][price_data][product_data][description]": desc,
        success_url: `${site}/?paid=${encodeURIComponent(b.ref)}`, expires_at: String(Math.floor(Date.now() / 1000) + 23 * 3600),
        "metadata[type]": "balance", "metadata[booking_id]": b.id, "metadata[business_id]": b.business_id, "metadata[ref]": b.ref,
        "payment_intent_data[metadata][booking_id]": b.id, "payment_intent_data[description]": `${biz.name || ""} ${b.ref}`,
        "custom_text[submit][message]": [bank, thanks].filter(Boolean).join("\n\n").slice(0, 1200),
      }, `cs2-${b.id}-${owed}-${Math.floor(Date.now() / 3600e3)}`);
      await admin.from("payment_links").insert({ id: s.id, business_id: b.business_id, booking_id: b.id, amount_pence: owed, url: s.url });
      return json({ url: s.url, amount: owed / 100, kind: "card-page" });
    }
    // find or create the Stripe customer
    let cus: any = null;
    const found = await stripe("GET", `customers/search?query=${encodeURIComponent(`metadata['valetiq_customer']:'${c.id}'`)}`, key);
    cus = found.data?.[0];
    if (!cus) cus = await stripe("POST", "customers", key, {
      name: `${c.first_name || ""} ${c.last_name || ""}`.trim() || "Customer",
      email: c.email, ...(c.mobile ? { phone: c.mobile } : {}),
      "metadata[valetiq_customer]": c.id, "metadata[business_id]": b.business_id,
    }, `cus-${c.id}-${c.email}`);
    else if (cus.email !== c.email) cus = await stripe("POST", `customers/${cus.id}`, key, { email: c.email });
    const meta = { "metadata[booking_id]": b.id, "metadata[business_id]": b.business_id, "metadata[ref]": b.ref };
    const inv = await stripe("POST", "invoices", key, {
      customer: cus.id, collection_method: "send_invoice", days_until_due: String(Math.max(dueDays, 1)), auto_advance: "false",
      pending_invoice_items_behavior: "exclude",
      description: `${b.service_name} on ${when} at ${String(b.start_time).slice(0, 5)}. Pay by card using the button, or by bank transfer using the details below.`.slice(0, 1500),
      footer: [bank ? bank.replace("Prefer bank transfer? ", "Bank transfer: ") : "", thanks].filter(Boolean).join("\n\n").slice(0, 5000),
      "custom_fields[0][name]": "Booking ref", "custom_fields[0][value]": b.ref,
      "custom_fields[1][name]": "Service date", "custom_fields[1][value]": `${when.replace(/ \d{4}$/, "")} ${String(b.start_time).slice(0, 5)}`.slice(0, 140), ...meta,
    }, `inv2-${b.id}-${owed}-${paid}`);
    await stripe("POST", "invoiceitems", key, { customer: cus.id, invoice: inv.id, currency: "gbp", amount: String(Math.round(Number(b.total) * 100)), description: `${b.service_name} — ${when} at ${String(b.start_time).slice(0, 5)}` }, `ii-${inv.id}-svc`);
    if (paid > 0) await stripe("POST", "invoiceitems", key, { customer: cus.id, invoice: inv.id, currency: "gbp", amount: String(-Math.round(paid * 100)), description: "Deposit / payments already received — thank you" }, `ii-${inv.id}-dep`);
    const fin = await stripe("POST", `invoices/${inv.id}/finalize`, key, { auto_advance: "true" });
    if (send) { try { await stripe("POST", `invoices/${inv.id}/send`, key, {}); } catch (_) { /* hosted link still works */ } }
    await admin.from("payment_links").insert({ id: fin.id, business_id: b.business_id, booking_id: b.id, amount_pence: owed, url: fin.hosted_invoice_url });
    return json({ url: fin.hosted_invoice_url, pdf: fin.invoice_pdf, number: fin.number, amount: owed / 100 });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
