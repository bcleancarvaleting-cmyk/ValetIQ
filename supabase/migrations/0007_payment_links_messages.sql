-- Stripe payment links per booking + default customer message templates + app installs
create table if not exists public.payment_links (
  id           text primary key,                     -- Stripe payment link id
  business_id  uuid not null references public.businesses on delete cascade,
  booking_id   uuid not null references public.bookings on delete cascade,
  amount_pence integer not null,
  url          text not null,
  paid_at      timestamptz,
  created_at   timestamptz not null default now()
);
alter table public.payment_links enable row level security;
create policy "members read links" on public.payment_links for select using (public.is_member(business_id));
create index if not exists payment_links_booking on public.payment_links (booking_id);
create index if not exists payments_stripe on public.payments (stripe_id);

create table if not exists public.app_installs (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses on delete cascade,
  customer_id  uuid references public.customers on delete cascade,
  platform     text not null default '',
  installed_at timestamptz not null default now()
);
alter table public.app_installs enable row level security;
create policy "members read installs" on public.app_installs for select using (public.is_member(business_id));
grant select on public.payment_links, public.app_installs to authenticated;

update public.businesses set settings = settings || jsonb_build_object('messages', jsonb_build_object(
  'welcome',   jsonb_build_object('on', true, 'title', 'Thanks for registering', 'text', 'Hi {name}, thanks for creating your {business} account! You can now see your bookings, pay balances and book again in seconds.'),
  'confirmed', jsonb_build_object('on', true, 'title', 'Booking confirmed', 'text', 'Hi {name}, your {service} with {business} is confirmed for {date} at {time} (ref {ref}).' || chr(10) || chr(10) || 'Add it to your calendar:' || chr(10) || 'Apple/Outlook: {calendar_link}' || chr(10) || 'Google: {google_link}'),
  'reminder',  jsonb_build_object('on', true, 'title', 'Reminder — see you tomorrow', 'text', 'Hi {name}, just a reminder that we''ll be with you {date} at {time} for your {service}. Balance due on the day: {amount}.'),
  'received',  jsonb_build_object('on', true, 'title', 'Payment received', 'text', 'Hi {name}, thanks — we''ve received your payment of {amount} for booking {ref}.'),
  'invoice',   jsonb_build_object('on', true, 'title', 'Invoice / balance due', 'text', 'Hi {name}, thanks for choosing {business}. The balance for your {service} ({ref}) is {amount}.' || chr(10) || 'Pay securely here: {pay_link}'),
  'rebook',    jsonb_build_object('on', false, 'title', 'Time for your next clean?', 'text', 'Hi {name}, it''s been a few weeks since your last clean with {business}. Want to book your next one?')
)) where slug = 'bclean' and not (settings ? 'messages');
