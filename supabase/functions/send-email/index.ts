// Branded emails through Resend (key entered in the admin app). Called by database triggers (x-push-secret)
// or by the admin app (signed-in owner). Kinds: welcome, confirmed, reminder, received, invoice, review, rebook, checkup, referral, test.
import { createClient } from "npm:@supabase/supabase-js@2";
const URL_ = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-secret", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const realEmail = (e?: string) => !!e && /^\S+@\S+\.\S+$/.test(e) && !/@no-email\.invalid$/i.test(e);
const DEF: Record<string, { title: string; text: string }> = {
  welcome: { title: "Welcome to {business}", text: "Hi {name}, thanks for creating your {business} account! You can now see your bookings, use pre-paid washes and book again in seconds." },
  confirmed: { title: "Booking confirmed — {date}", text: "Hi {name}, your {service} with {business} is confirmed for {date} at {time} (ref {ref})." },
  reminder: { title: "See you tomorrow", text: "Hi {name}, just a reminder that we'll be with you {date} at {time} for your {service}." },
  received: { title: "Payment received — thank you", text: "Hi {name}, thanks — we've received your payment of {amount} for booking {ref}." },
  invoice: { title: "Invoice {number} from {business}", text: "Hi {billname},\n\nThanks for using {business}.\n\nYour invoice is attached to this email.\n\nThanks\n{business}" },
  invoice_reminder: { title: "Reminder: {amount} due — invoice {number}", text: "Hi {name}, just a friendly reminder that {amount} is still outstanding for your {service} on {date} (ref {ref}). {due_line}\n\nYou can pay by card using the button below, or by bank transfer. Your invoice is attached. If you've already paid, thank you — please ignore this email." },
  review: { title: "How did we do?", text: "Hi {name}, thanks for choosing {business}! If you're happy with your {service}, a quick review would mean the world to us." },
  rebook: { title: "Time for your next clean?", text: "Hi {name}, it's been a little while since your last clean with {business}. Want to book your next one?" },
  checkup: { title: "Time for your coating check-up", text: "Hi {name}, your coating is due its check-up. Book a maintenance valet to keep your warranty valid." },
  referral: { title: "You've earned {amount}", text: "Hi {name}, a friend you referred has just used {business} — {amount} has been added to your account." },
  test: { title: "Emails are working ✅", text: "This is a test email from your {business} booking system. Customer emails will look like this." },
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const b = await req.json();
    const { data: cfg } = await db.rpc("get_push_config");
    const internal = req.headers.get("x-push-secret") && req.headers.get("x-push-secret") === (cfg as any)?.push_hook;
    if (!internal) {
      const userDb = createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
      const { data: ok } = await userDb.rpc("is_member", { b: b.business_id });
      if (!ok) return json({ error: "Not allowed" }, 403);
    }
    const { data: biz } = await db.from("businesses").select("id,name,settings").eq("id", b.business_id).single();
    if (!biz) return json({ error: "Business not found" }, 404);
    const st: any = biz.settings || {}; const M = st.messages || {};
    const kind = b.kind || "custom";
    if (!b.force && kind !== "test" && !kind.startsWith("invoice") && M[kind] && M[kind].on === false) return json({ skipped: "switched off" });
    if (!b.force && st.emails && st.emails[kind] === false) return json({ skipped: "email off" });
    const { data: ek } = await db.rpc("get_business_email", { p_business: biz.id });
    const key = (ek as any)?.key; if (!key) return json({ error: "Emails aren't connected — add your Resend key in Settings → Emails" }, 400);
    let c: any = null, bk: any = null;
    if (b.customer_id) c = (await db.from("customers").select("*").eq("id", b.customer_id).single()).data;
    if (b.booking_id) bk = (await db.from("bookings").select("*").eq("id", b.booking_id).single()).data;
    if (!c && bk) c = (await db.from("customers").select("*").eq("id", bk.customer_id).single()).data;
    const to = kind === "test" ? (b.to || st.email) : (b.to || (c?.business_account && realEmail(c?.invoice_email) ? c.invoice_email : c?.email));
    if (!realEmail(to)) return json({ skipped: "no email address" });
    const site = st.siteUrl || Deno.env.get("SITE_URL") || "https://bcleanvaleting.co.uk";
    const when = bk ? new Date(`${bk.date}T12:00:00`).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" }) : "";
    const map: Record<string, string> = {
      name: c?.first_name || "there", billname: (c?.business_account && String(c?.company_name || "").trim()) || c?.first_name || "there", business: biz.name, service: bk?.service_name || "", ref: bk?.ref || "", date: when,
      time: bk ? (bk.days > 0 ? "all day" : String(bk.start_time).slice(0, 5)) : "", amount: "£" + Number(b.amount ?? bk?.total ?? 0).toFixed(2),
      pay_link: b.pay_link || "", number: b.number || (bk ? "INV-" + bk.ref : ""),
      due_line: b.due ? (new Date(`${b.due}T23:59:00`).getTime() < Date.now() ? `It was due on ${new Date(`${b.due}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "long" })}.` : `It's due by ${new Date(`${b.due}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "long" })}.`) : "", review_link: st.reviewUrl || "", site, calendar_link: bk ? `${site}/cal/${bk.id}` : "", google_link: "", bank_details: "", ref_code: c?.referral_code || "",
    };
    const fill = (s: string) => String(s || "").replace(/\{(\w+)\}/g, (x, k) => map[k] ?? "");
    const m = { ...(DEF[kind] || { title: biz.name, text: "" }), ...(kind === "invoice" ? (st.invoiceEmail || {}) : kind === "invoice_reminder" ? (st.invoiceReminderEmail || {}) : (M[kind] || {})) } as any;
    const subject = fill(b.subject || m.title || biz.name);
    const text = fill(b.text || m.text || "").replace(/\n?(Pay (securely|by card)[^\n]*|Apple\/Outlook:[^\n]*|Google:[^\n]*|Add it to your calendar:)\s*/g, "\n").trim();
    const ac = st.accent || "#2f7bff"; const br = st.brand || {}; const I = st.invoice || {};
    const btns: [string, string][] = [];
    const isInv = kind === "invoice" || kind === "invoice_reminder";
    const payUrl = b.link_id ? `${URL_}/functions/v1/inv?l=${encodeURIComponent(b.link_id)}` : b.pay_link;
    if (kind === "confirmed" && bk) btns.push(["Add to calendar", `${site}/cal/${bk.id}`], ["View my booking", `${site}/account/`]);
    if (isInv && payUrl) btns.push([`Pay ${map.amount} by card`, payUrl]);
    if (kind === "welcome" || kind === "referral") btns.push(["Open my account", `${site}/account/`]);
    if (kind === "review" && st.reviewUrl) btns.push(["Leave a review ⭐", st.reviewUrl]);
    if (kind === "rebook" || kind === "checkup") btns.push(["Book now", `${site}/?book=1`]);
    const bank = isInv && I.sortCode && I.accNo ? `<div style="margin-top:18px;padding:14px 16px;background:#f5f6f8;border-radius:10px;font-size:14px;color:#333"><b>Prefer bank transfer?</b><br>${I.accName ? esc(I.accName) + "<br>" : ""}Sort code <b>${esc(I.sortCode)}</b> · Account <b>${esc(I.accNo)}</b><br>Reference <b>${esc(bk?.ref || "")}</b></div>` : "";
    const details = bk && ["confirmed", "reminder", "invoice", "invoice_reminder", "received"].includes(kind) ? `<table style="width:100%;margin-top:18px;font-size:14px;border-collapse:collapse">${[["Service", bk.service_name], ["Date", when + (bk.days > 0 ? "" : " at " + map.time)], ["Address", [bk.address, bk.postcode].filter(Boolean).join(", ")], ["Ref", bk.ref]].filter((r) => r[1]).map((r) => `<tr><td style="padding:6px 0;color:#777;width:34%">${r[0]}</td><td style="padding:6px 0;font-weight:600;color:#111">${esc(r[1])}</td></tr>`).join("")}</table>` : "";
    const ch = Number(st.cancelHours ?? 48);
    let pol = "";
    if (bk && ["confirmed", "reminder"].includes(kind) && st.cancel) {
      const startMs = new Date(`${bk.date}T${bk.days > 0 ? "08:30" : String(bk.start_time).slice(0, 5)}:00Z`).getTime();
      const until = new Date(startMs - ch * 3600e3);
      const ok = until.getTime() > Date.now();
      pol = `<div style="margin-top:18px;padding:12px 14px;border:1px solid #e5e7eb;border-radius:10px;font-size:13px;color:#555;line-height:1.5"><b style="color:#111">Cancellation policy</b><br>${ok ? `Free to change or cancel until <b>${until.toLocaleString("en-GB", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "UTC" })}</b>.<br>` : ""}${esc(st.cancel)}</div>`;
    }
    const html = `<!doctype html><html><body style="margin:0;background:#f2f3f5;font-family:Arial,Helvetica,sans-serif"><div style="max-width:560px;margin:0 auto;padding:24px 14px">
<div style="background:#0b0d12;border-radius:16px 16px 0 0;padding:22px 26px;text-align:left">${br.logo ? `<img src="${esc(br.logo)}" alt="" style="height:46px;vertical-align:middle;border-radius:8px">` : ""}<span style="color:#fff;font-size:20px;font-weight:700;vertical-align:middle;margin-left:${br.logo ? 10 : 0}px">${esc(biz.name)}</span></div>
<div style="background:#fff;border-radius:0 0 16px 16px;padding:26px">
<h1 style="margin:0 0 12px;font-size:22px;color:#111">${esc(subject)}</h1>
<div style="font-size:15px;line-height:1.6;color:#333;white-space:pre-line">${esc(text)}</div>${details}${bank}
${btns.length ? `<div style="margin-top:22px">${btns.map(([t, u], i) => `<a href="${esc(u)}" style="display:inline-block;margin:0 8px 8px 0;padding:12px 20px;border-radius:999px;text-decoration:none;font-weight:700;font-size:14px;${i ? `border:2px solid ${ac};color:${ac}` : `background:${ac};color:#fff`}">${esc(t)}</a>`).join("")}</div>` : ""}
${pol}
${isInv && kind === "invoice" ? "" : `<p style="margin:24px 0 0;font-size:14px;color:#333">${esc(I.thanks || "Thanks for using " + biz.name)}</p>`}</div>
<p style="text-align:center;font-size:12px;color:#888;margin:14px 0">${esc(biz.name)}${st.phone ? " · " + esc(st.phone) : ""}${st.email ? " · " + esc(st.email) : ""}<br><a href="${site}" style="color:#888">${site.replace(/^https?:\/\//, "")}</a></p></div>${b.link_id ? `<img src="${URL_}/functions/v1/inv?l=${encodeURIComponent(b.link_id)}&px=1" width="1" height="1" alt="" style="display:block;width:1px;height:1px;border:0">` : ""}</body></html>`;
    const from = (ek as any)?.from || `${biz.name} <bookings@${new URL(site).hostname.replace(/^www\./, "")}>`;
    const body: any = { from, to: [to], subject, html, text: `${text}\n\n${btns.map(([t, u]) => `${t}: ${u}`).join("\n")}` };
    if (realEmail(st.email)) body.reply_to = st.email;
    // copy the business in on customer emails so they have a record of what was sent
    const wantCopy = kind !== "test" && st.emailCopy !== false && realEmail(st.email) && String(st.email).toLowerCase() !== String(to).toLowerCase();
    // tracked invoice emails: send the business a separate copy so opening your own copy doesn't count as "opened"
    if (wantCopy && !b.link_id) body.cc = [st.email];
    if (b.pdf) {
      const filename = `${(b.number || "Invoice-" + (bk?.ref || "BC")).replace(/[^\w-]+/g, "-")}.pdf`;
      // download the PDF ourselves (Stripe's link redirects) and attach the file itself
      let content = "";
      for (let i = 0; i < 3 && !content; i++) {
        try {
          const pr = await fetch(b.pdf, { redirect: "follow" });
          const ct = pr.headers.get("content-type") || "";
          if (pr.ok && ct.includes("pdf")) { const buf = new Uint8Array(await pr.arrayBuffer()); let bin = ""; for (let k = 0; k < buf.length; k += 0x8000) bin += String.fromCharCode(...buf.subarray(k, k + 0x8000)); content = btoa(bin); }
          else await new Promise((r) => setTimeout(r, 1500));
        } catch (_) { await new Promise((r) => setTimeout(r, 1500)); }
      }
      body.attachments = [content ? { filename, content } : { filename, path: b.pdf }];
    }
    const send = (x: any) => fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify(x) });
    const r = await send(body);
    const j = await r.json(); if (!r.ok) return json({ error: j?.message || "Email failed" }, 400);
    if (wantCopy && b.link_id) {
      const copyHtml = html.replace(/<img src="[^"]*\/inv\?l=[^"]*&px=1"[^>]*>/, "").split(esc(payUrl)).join(esc(b.pay_link || site));
      try { await send({ ...body, to: [st.email], subject: `Copy: ${subject} (sent to ${to})`, html: copyHtml, reply_to: undefined }); } catch (_) { /* copy is best-effort */ }
    }
    return json({ sent: true, id: j.id, to });
  } catch (e) { return json({ error: (e as Error).message }, 500); }
});
