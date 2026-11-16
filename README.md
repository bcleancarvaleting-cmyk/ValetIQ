# valetIQ

Booking, diary, payments and website platform for valeting & detailing businesses.
**B Clean Valeting** (Kent) is tenant #1.

## What's here

| Path | What it is |
|---|---|
| `index.html` | **Stage 1 live site** for B Clean — homepage, services, pre-paid plans, FAQ, contact dock. "Book now" opens a booking-request form sent via WhatsApp or email. No backend needed. |
| `prototype/` | Full clickable platform prototype (website, booking flow, customer app, admin, valetIQ HQ). Demo data only, stored in the browser. Not indexed. |
| `docs/build_live.py` | Script that generates the Stage 1 site from the prototype. |
| `vercel.json` | Hosting config for Vercel. |

## Before going live
Edit the `CFG` block near the bottom of `index.html`: phone, WhatsApp, email, social links, Google review link.

## Roadmap
- **Stage 1 (now):** static homepage on bcleanvaleting.co.uk with WhatsApp/email booking requests.
- **Stage 2:** Supabase (database, auth, row-level security per business) + Stripe deposits/full payments + Resend emails. Real online booking, admin diary, customer accounts.
- **Stage 3:** pre-paid plans & stamp book, live chat, offers, vouchers, referrals, push notifications (PWA), SMS.
- **Stage 4:** multi-business onboarding (valetIQ HQ), staff, route planning, reporting.
