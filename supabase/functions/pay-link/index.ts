// Business-only: creates a Stripe Invoice for the balance on a booking (full price, minus the deposit already paid)
// and returns the hosted invoice page URL. Stripe also emails the invoice when the customer has a real email.
// POST { booking_id }  with the signed-in admin's JWT.
import { createClient } from "npm:@supabase/supabase-js@2";

// Stripe keys: entered per business in the admin app (Settings → Payments); falls back to the platform Vault keys
async function keysFor(biz?: string): Promise<{ secret?: string; whsec?: string }> {
  const a = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  if (biz) { const { data } = await a.rpc("get_business_stripe", { p_business: biz }); if (data && (data as any).secret) return { secret: (data as any).secret, whsec: (data as any).whsec }; }
  const { data: v } = await a.rpc("get_stripe_config"); const g: any = v || {};
  return { secret: Deno.env.get("STRIPE_SECRET_KEY") || g.STRIPE_SECRET_KEY, whsec: Deno.env.get("STRIPE_WEBHOOK_SECRET") || g.STRIPE_WEBHOOK_SECRET };
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
    const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
    const { booking_id, send, action } = await req.json();
    // RLS: only members of the booking's business can read it
    const { data: b, error } = await userDb.from("bookings").select("id,ref,business_id,total,status,service_name,date,start_time,customer_id,customers(id,email,first_name,last_name,mobile,business_account,company_name,invoice_email,company_address,house,address,postcode),businesses(name,settings)").eq("id", booking_id).single();
    if (error || !b) return json({ error: "Booking not found" }, 404);
    if (b.status === "Cancelled") return json({ error: "This booking is cancelled" }, 400);
    const key = (await keysFor(b.business_id)).secret;
    if (!key) return json({ error: "Card payments aren't connected yet — add your Stripe key in Settings → Payments." }, 400);
    const admin = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const emailInvoice = async (kind: string, l: any, amount: number) => {
      const { data: ek } = await admin.rpc("get_business_email", { p_business: b.business_id });
      if (!(ek as any)?.key) return false;
      const { data: cfg } = await admin.rpc("get_push_config");
      const r = await fetch(`${URL_}/functions/v1/send-email`, { method: "POST", headers: { "Content-Type": "application/json", "x-push-secret": (cfg as any)?.push_hook || "" },
        body: JSON.stringify({ business_id: b.business_id, kind, booking_id: b.id, customer_id: (b as any).customer_id, amount, pay_link: l.url, link_id: l.id, pdf: l.pdf, number: l.number, due: l.due_date, force: kind === "invoice_reminder" }) });
      return r.ok && !!(await r.json().catch(() => ({})))?.sent;
    };
    if (action === "remind") {
      const { data: ls } = await admin.from("payment_links").select("*").eq("booking_id", b.id).is("paid_at", null).like("id", "in_%").order("created_at", { ascending: false }).limit(1);
      const l: any = ls && ls[0];
      if (!l) return json({ error: "Send the invoice first — then you can send reminders" }, 400);
      const inv = await stripe("GET", `invoices/${l.id}`, key);
      if (inv.status === "paid") { await admin.from("payment_links").update({ paid_at: new Date().toISOString() }).eq("id", l.id); return json({ error: "Stripe says this invoice is already paid 🎉" }, 400); }
      if (inv.status === "void" || inv.status === "uncollectible") return json({ error: "That invoice was cancelled in Stripe — create a new one" }, 400);
      const upd: any = { pdf: l.pdf || inv.invoice_pdf, number: l.number || inv.number, due_date: l.due_date || (inv.due_date ? new Date(inv.due_date * 1000).toISOString().slice(0, 10) : null) };
      Object.assign(l, upd);
      let how = "email";
      if (!(await emailInvoice("invoice_reminder", l, inv.amount_remaining / 100))) { await stripe("POST", `invoices/${l.id}/send`, key, {}); how = "stripe"; }
      await admin.from("payment_links").update({ ...upd, reminder_count: (l.reminder_count || 0) + 1, last_reminder_at: new Date().toISOString(), sent_at: l.sent_at || new Date().toISOString() }).eq("id", l.id);
      return json({ ok: true, how, amount: inv.amount_remaining / 100 });
    }
    const { data: pays } = await admin.from("payments").select("amount").eq("booking_id", b.id);
    const paid = (pays || []).reduce((s: number, p: any) => s + Number(p.amount), 0);
    const owed = Math.round((Number(b.total) - paid) * 100);
    if (owed < 30) return json({ error: "Nothing left to pay on this booking" }, 400);
    const c: any = (b as any).customers || {}; const biz: any = (b as any).businesses || {};
    const isB = !!(c.business_account && String(c.company_name || "").trim());
    const person = `${c.first_name || ""} ${c.last_name || ""}`.trim();
    const billName = isB ? String(c.company_name).trim() : person || "Customer";
    const billEmail = isB && realEmail(c.invoice_email) ? c.invoice_email : c.email;
    const hasEmail = realEmail(billEmail);
    const addrLines = (isB && String(c.company_address || "").trim() ? String(c.company_address).split(/\n+/) : [[c.house, c.address].filter(Boolean).join(" "), c.postcode || ""]).map((x: string) => x.trim()).filter(Boolean);
    const addr: Record<string, string> = {};
    if (addrLines.length) {
      const pc = addrLines.find((x: string) => /^[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}$/i.test(x)) || (isB ? "" : c.postcode || "");
      const rest = addrLines.filter((x: string) => x !== pc);
      addr["address[line1]"] = (rest[0] || "").slice(0, 200); if (rest[1]) addr["address[line2]"] = rest.slice(1, rest.length > 2 ? -1 : undefined).join(", ").slice(0, 200);
      if (rest.length > 2) addr["address[city]"] = rest[rest.length - 1].slice(0, 100);
      if (pc) addr["address[postal_code]"] = pc.toUpperCase(); addr["address[country]"] = "GB";
    }
    const I: any = biz.settings?.invoice || {};
    const thanks = I.thanks || `Thanks for using ${biz.name || "us"}`;
    const bank = I.sortCode && I.accNo ? `Prefer bank transfer? ${I.accName ? I.accName + " · " : ""}Sort code ${I.sortCode} · Account ${I.accNo} · Reference ${b.ref}` : "";
    const dueDays = Number(I.dueDays ?? 7);
    // reuse an open invoice / recent card page for the same amount
    const { data: existing } = await admin.from("payment_links").select("*").eq("booking_id", b.id).is("paid_at", null).eq("amount_pence", owed).order("created_at", { ascending: false }).limit(1);
    let ex: any = existing && existing[0];
    // an open invoice with the old name/details (e.g. customer switched to a business) is voided and recreated
    if (ex && ex.id.startsWith("in_")) {
      try {
        const old = await stripe("GET", `invoices/${ex.id}`, key);
        if (old.status === "open" && (old.customer_name || "") !== billName) {
          await stripe("POST", `invoices/${ex.id}/void`, key, {});
          await admin.from("payment_links").delete().eq("id", ex.id); ex = null;
        } else if (old.status === "paid") { return json({ error: "Stripe shows this invoice as already paid — it will update shortly, or record the payment" }, 400); }
        else if (old.status !== "open") { await admin.from("payment_links").delete().eq("id", ex.id); ex = null; }
      } catch (e) { if (/already paid/.test(String((e as Error).message))) throw e; }
    }
    if (ex && ex.id.startsWith("in_")) {
      let emailed = false, sent = false;
      if (send) {
        const inv = await stripe("GET", `invoices/${ex.id}`, key);
        if (inv.status === "open") {
          Object.assign(ex, { pdf: ex.pdf || inv.invoice_pdf, number: ex.number || inv.number, due_date: ex.due_date || (inv.due_date ? new Date(inv.due_date * 1000).toISOString().slice(0, 10) : null) });
          emailed = await emailInvoice("invoice", ex, owed / 100);
          if (!emailed) { try { await stripe("POST", `invoices/${ex.id}/send`, key, {}); sent = true; } catch (_) { /* ignore */ } }
          await admin.from("payment_links").update({ pdf: ex.pdf, number: ex.number, due_date: ex.due_date, ...(emailed || sent ? { sent_at: new Date().toISOString() } : {}) }).eq("id", ex.id);
        }
      }
      return json({ url: ex.url, pdf: ex.pdf, amount: owed / 100, reused: true, emailed, sent });
    }
    if (ex && ex.id.startsWith("cs_") && Date.now() - new Date(ex.created_at).getTime() < 22 * 3600e3) return json({ url: ex.url, amount: owed / 100, reused: true });
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
    const cusData = { name: billName, email: billEmail, ...(c.mobile ? { phone: c.mobile } : {}), ...addr };
    if (!cus) cus = await stripe("POST", "customers", key, { ...cusData, "metadata[valetiq_customer]": c.id, "metadata[business_id]": b.business_id }, `cus-${c.id}-${billEmail}-${billName}`.slice(0, 250));
    else cus = await stripe("POST", `customers/${cus.id}`, key, cusData);
    const meta = { "metadata[booking_id]": b.id, "metadata[business_id]": b.business_id, "metadata[ref]": b.ref };
    const inv = await stripe("POST", "invoices", key, {
      customer: cus.id, collection_method: "send_invoice", days_until_due: String(Math.max(dueDays, 1)), auto_advance: "false",
      pending_invoice_items_behavior: "exclude",
      description: `${b.service_name} on ${when} at ${String(b.start_time).slice(0, 5)}. Pay by card using the button, or by bank transfer using the details below.`.slice(0, 1500),
      footer: [bank ? bank.replace("Prefer bank transfer? ", "Bank transfer: ") : "", thanks].filter(Boolean).join("\n\n").slice(0, 5000),
      "custom_fields[0][name]": "Booking ref", "custom_fields[0][value]": b.ref,
      "custom_fields[1][name]": "Service date", "custom_fields[1][value]": `${when.replace(/ \d{4}$/, "")} ${String(b.start_time).slice(0, 5)}`.slice(0, 140), ...meta,
      ...(isB && person ? { "custom_fields[2][name]": "Attn", "custom_fields[2][value]": person.slice(0, 140) } : {}),
    }, `inv3-${b.id}-${owed}-${paid}-${billName}-${Date.now() >> 16}`.slice(0, 250));
    await stripe("POST", "invoiceitems", key, { customer: cus.id, invoice: inv.id, currency: "gbp", amount: String(Math.round(Number(b.total) * 100)), description: `${b.service_name} — ${when} at ${String(b.start_time).slice(0, 5)}` }, `ii-${inv.id}-svc`);
    if (paid > 0) await stripe("POST", "invoiceitems", key, { customer: cus.id, invoice: inv.id, currency: "gbp", amount: String(-Math.round(paid * 100)), description: "Deposit / payments already received — thank you" }, `ii-${inv.id}-dep`);
    const fin = await stripe("POST", `invoices/${inv.id}/finalize`, key, { auto_advance: "true" });
    const row: any = { id: fin.id, business_id: b.business_id, booking_id: b.id, amount_pence: owed, url: fin.hosted_invoice_url, pdf: fin.invoice_pdf, number: fin.number,
      due_date: fin.due_date ? new Date(fin.due_date * 1000).toISOString().slice(0, 10) : null };
    await admin.from("payment_links").insert(row);
    let emailed = false, sent = false;
    if (send) {
      emailed = await emailInvoice("invoice", row, owed / 100);
      if (!emailed) { try { await stripe("POST", `invoices/${inv.id}/send`, key, {}); sent = true; } catch (_) { /* hosted link still works */ } }
      if (emailed || sent) await admin.from("payment_links").update({ sent_at: new Date().toISOString() }).eq("id", fin.id);
    }
    return json({ url: fin.hosted_invoice_url, pdf: fin.invoice_pdf, number: fin.number, amount: owed / 100, emailed, sent });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
