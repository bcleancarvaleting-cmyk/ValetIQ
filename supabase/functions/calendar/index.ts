// Public: returns an .ics calendar file for a booking so customers can add it to Apple/Google/Outlook calendars.
// GET /functions/v1/calendar?b=<booking uuid>   (also served as https://<site>/cal/<uuid>)
import { createClient } from "npm:@supabase/supabase-js@2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const pad = (n: number) => String(n).padStart(2, "0");
const esc = (s: string) => (s || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\n/g, "\\n");
Deno.serve(async (req) => {
  const u = new URL(req.url);
  const id = u.searchParams.get("b") || "";
  if (!/^[0-9a-f-]{36}$/i.test(id)) return new Response("Not found", { status: 404 });
  const { data: b } = await db.from("bookings").select("id,ref,date,start_time,duration_mins,days,service_name,address,postcode,status,businesses(name,settings)").eq("id", id).single();
  if (!b || b.status === "Cancelled") return new Response("Booking not found", { status: 404 });
  const biz: any = (b as any).businesses || {};
  const [y, m, d] = b.date.split("-").map(Number);
  let dt: string;
  if (b.days > 0) {
    const end = new Date(Date.UTC(y, m - 1, d + b.days));
    dt = `DTSTART;VALUE=DATE:${y}${pad(m)}${pad(d)}\r\nDTEND;VALUE=DATE:${end.getUTCFullYear()}${pad(end.getUTCMonth() + 1)}${pad(end.getUTCDate())}`;
  } else {
    const [hh, mm] = b.start_time.split(":").map(Number);
    const endMin = hh * 60 + mm + (b.duration_mins || 120);
    dt = `DTSTART;TZID=Europe/London:${y}${pad(m)}${pad(d)}T${pad(hh)}${pad(mm)}00\r\nDTEND;TZID=Europe/London:${y}${pad(m)}${pad(d)}T${pad(Math.floor(endMin / 60) % 24)}${pad(endMin % 60)}00`;
  }
  const phone = biz.settings?.phone ? ` Questions? Call ${biz.settings.phone}.` : "";
  const ics = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//valetIQ//Booking//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    "BEGIN:VTIMEZONE", "TZID:Europe/London",
    "BEGIN:DAYLIGHT", "TZOFFSETFROM:+0000", "TZOFFSETTO:+0100", "TZNAME:BST", "DTSTART:19700329T010000", "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU", "END:DAYLIGHT",
    "BEGIN:STANDARD", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0000", "TZNAME:GMT", "DTSTART:19701025T020000", "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU", "END:STANDARD",
    "END:VTIMEZONE",
    "BEGIN:VEVENT",
    `UID:${b.id}@valetiq`,
    `DTSTAMP:${new Date().toISOString().replace(/[-:]/g, "").slice(0, 15)}Z`,
    dt,
    `SUMMARY:${esc(`${b.service_name} — ${biz.name || "Valet"}`)}`,
    `DESCRIPTION:${esc(`Booking ${b.ref} with ${biz.name || ""}.${phone}`)}`,
    `LOCATION:${esc([b.address, b.postcode].filter(Boolean).join(", "))}`,
    "BEGIN:VALARM", "TRIGGER:-PT12H", "ACTION:DISPLAY", `DESCRIPTION:${esc(`${b.service_name} tomorrow`)}`, "END:VALARM",
    "END:VEVENT", "END:VCALENDAR", "",
  ].join("\r\n");
  return new Response(ics, { headers: { "Content-Type": "text/calendar; charset=utf-8", "Content-Disposition": `inline; filename="${b.ref}.ics"`, "Cache-Control": "no-store" } });
});
