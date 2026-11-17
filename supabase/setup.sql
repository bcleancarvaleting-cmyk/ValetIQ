-- =====================================================================
-- valetIQ — initial schema (multi-business, row-level security)
-- Applied to project tigznsqtesgofvoflmem on 16 Nov 2026 (via Supabase connector)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- businesses & access ----------
create table public.businesses (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,
  name        text not null,
  plan        text not null default 'full',
  status      text not null default 'active' check (status in ('active','trial','suspended')),
  settings    jsonb not null default '{}'::jsonb,   -- public website & booking settings
  ref_prefix  text not null default 'BK',
  ref_seq     integer not null default 1000,
  created_at  timestamptz not null default now()
);

create table public.business_members (
  business_id uuid not null references public.businesses on delete cascade,
  user_id     uuid not null references auth.users on delete cascade,
  role        text not null default 'owner' check (role in ('owner','staff')),
  created_at  timestamptz not null default now(),
  primary key (business_id, user_id)
);

create table public.platform_admins (
  user_id uuid primary key references auth.users on delete cascade
);

create or replace function public.is_member(b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.business_members where business_id = b and user_id = auth.uid())
      or exists (select 1 from public.platform_admins where user_id = auth.uid());
$$;

-- ---------- catalogue & availability ----------
create table public.services (
  id               uuid primary key default gen_random_uuid(),
  business_id      uuid not null references public.businesses on delete cascade,
  category         text not null default 'Valeting' check (category in ('Valeting','Detailing','Additional Services')),
  name             text not null,
  description      text not null default '',
  includes         text[] not null default '{}',
  price_small      numeric(10,2),
  price_medium     numeric(10,2),          -- null = same as small
  price_large      numeric(10,2),          -- null = same as medium/small
  price_on_request boolean not null default false,
  duration_mins    integer not null default 120 check (duration_mins > 0),
  days             integer not null default 0 check (days >= 0),   -- >0 = full-day job(s)
  day_label        text,
  redeemable       boolean not null default false,                  -- can be paid with plan credits
  image_url        text,
  active           boolean not null default true,
  sort             integer not null default 0,
  created_at       timestamptz not null default now()
);
create index on public.services (business_id, sort);

create table public.time_slots (
  business_id uuid not null references public.businesses on delete cascade,
  start_time  time not null,
  enabled     boolean not null default true,
  primary key (business_id, start_time)
);

create table public.slot_closures (               -- a set time switched off for one day
  business_id uuid not null references public.businesses on delete cascade,
  date        date not null,
  start_time  time not null,
  primary key (business_id, date, start_time)
);

create table public.blocked_dates (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  from_date   date not null,
  to_date     date not null,
  reason      text not null default 'Unavailable',
  check (to_date >= from_date)
);
create index on public.blocked_dates (business_id, from_date);

-- ---------- customers ----------
create table public.customers (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses on delete cascade,
  user_id       uuid references auth.users on delete set null,
  first_name    text not null,
  last_name     text not null default '',
  email         text not null,
  mobile        text not null default '',
  house         text not null default '',
  address       text not null default '',
  postcode      text not null default '',
  notes         text not null default '',
  vip           boolean not null default false,
  wallet        numeric(10,2) not null default 0,
  referral_code text,
  created_at    timestamptz not null default now()
);
create unique index customers_business_email on public.customers (business_id, lower(email));
create index on public.customers (user_id);

create table public.vehicles (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  customer_id uuid not null references public.customers on delete cascade,
  reg         text not null,
  make        text not null default '',
  model       text not null default '',
  colour      text not null default '',
  size        smallint not null default 0 check (size between 0 and 2),
  created_at  timestamptz not null default now()
);
create index on public.vehicles (customer_id);

-- ---------- plans (pre-paid credits) ----------
create table public.plans (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses on delete cascade,
  name         text not null,
  description  text not null default '',
  service_id   uuid references public.services on delete set null,   -- priced on
  eligible     uuid[] not null default '{}',                          -- services credits can be used on
  counts       integer[] not null default '{12,24}',
  months       integer not null default 12,
  discount_pct numeric(5,2),                                          -- null = business default
  featured     boolean not null default false,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.plan_subscriptions (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses on delete cascade,
  customer_id  uuid not null references public.customers on delete cascade,
  plan_id      uuid references public.plans on delete set null,
  visits       integer not null,
  size         smallint not null default 0,
  amount       numeric(10,2) not null,
  credits      integer not null default 0,
  start_date   date not null default current_date,
  end_date     date not null,
  status       text not null default 'active' check (status in ('active','past_due','paused','cancelled','expired')),
  auto_renew   boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.credit_ledger (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses on delete cascade,
  subscription_id uuid not null references public.plan_subscriptions on delete cascade,
  delta           integer not null,
  note            text not null default '',
  booking_id      uuid,
  created_at      timestamptz not null default now()
);

-- ---------- bookings & payments ----------
create type public.booking_status as enum ('Pending','Booked','Confirmed','In Progress','Completed','Cancelled');

create table public.bookings (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses on delete cascade,
  ref             text not null,
  customer_id     uuid not null references public.customers on delete cascade,
  vehicle_id      uuid references public.vehicles on delete set null,
  service_id      uuid references public.services on delete set null,
  service_name    text not null,
  size            smallint not null default 0,
  date            date not null,
  start_time      time not null,
  duration_mins   integer not null default 0,
  days            integer not null default 0,
  price           numeric(10,2) not null default 0,
  callout         numeric(10,2) not null default 0,
  discount        numeric(10,2) not null default 0,
  discount_code   text,
  total           numeric(10,2) not null default 0,
  status          public.booking_status not null default 'Booked',
  source          text not null default 'website',
  notes           text not null default '',
  postcode        text not null default '',
  address         text not null default '',
  credit          boolean not null default false,
  subscription_id uuid references public.plan_subscriptions on delete set null,
  repeat_group    uuid,
  inspection      jsonb,
  change_request  text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (business_id, ref)
);
create index on public.bookings (business_id, date);
create index on public.bookings (customer_id);

create table public.payments (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses on delete cascade,
  booking_id      uuid references public.bookings on delete set null,
  customer_id     uuid references public.customers on delete set null,
  subscription_id uuid references public.plan_subscriptions on delete set null,
  type            text not null check (type in ('deposit','balance','full','membership','voucher','refund')),
  amount          numeric(10,2) not null,
  method          text not null default 'card',
  stripe_id       text,
  created_at      timestamptz not null default now()
);
create index on public.payments (business_id, created_at);
create index on public.payments (booking_id);

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  kind        text not null,
  text        text not null,
  booking_id  uuid,
  read        boolean not null default false,
  created_at  timestamptz not null default now()
);
create index on public.notifications (business_id, created_at desc);

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger bookings_touch before update on public.bookings for each row execute function public.touch_updated_at();

-- =====================================================================
-- Row-level security
-- =====================================================================
alter table public.businesses         enable row level security;
alter table public.business_members   enable row level security;
alter table public.platform_admins    enable row level security;
alter table public.services           enable row level security;
alter table public.time_slots         enable row level security;
alter table public.slot_closures      enable row level security;
alter table public.blocked_dates      enable row level security;
alter table public.customers          enable row level security;
alter table public.vehicles           enable row level security;
alter table public.plans              enable row level security;
alter table public.plan_subscriptions enable row level security;
alter table public.credit_ledger      enable row level security;
alter table public.bookings           enable row level security;
alter table public.payments           enable row level security;
alter table public.notifications      enable row level security;

-- public (website visitors): business info, catalogue, availability rules
create policy "public read businesses" on public.businesses for select using (status <> 'suspended');
create policy "members update business" on public.businesses for update using (public.is_member(id)) with check (public.is_member(id));

create policy "own membership" on public.business_members for select using (user_id = auth.uid() or public.is_member(business_id));
create policy "own admin row" on public.platform_admins for select using (user_id = auth.uid());

create policy "public read services" on public.services for select using (true);
create policy "members manage services" on public.services for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "public read slots" on public.time_slots for select using (true);
create policy "members manage slots" on public.time_slots for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "public read closures" on public.slot_closures for select using (true);
create policy "members manage closures" on public.slot_closures for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "public read blocked" on public.blocked_dates for select using (true);
create policy "members manage blocked" on public.blocked_dates for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "public read plans" on public.plans for select using (true);
create policy "members manage plans" on public.plans for all using (public.is_member(business_id)) with check (public.is_member(business_id));

-- private data: business members see everything for their business; customers see only their own
create policy "members manage customers" on public.customers for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "customer reads self" on public.customers for select using (user_id = auth.uid());
create policy "customer updates self" on public.customers for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "members manage vehicles" on public.vehicles for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "customer reads own vehicles" on public.vehicles for select using (exists (select 1 from public.customers c where c.id = customer_id and c.user_id = auth.uid()));

create policy "members manage bookings" on public.bookings for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "customer reads own bookings" on public.bookings for select using (exists (select 1 from public.customers c where c.id = customer_id and c.user_id = auth.uid()));

create policy "members manage payments" on public.payments for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "customer reads own payments" on public.payments for select using (exists (select 1 from public.customers c where c.id = customer_id and c.user_id = auth.uid()));

create policy "members manage subs" on public.plan_subscriptions for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "customer reads own subs" on public.plan_subscriptions for select using (exists (select 1 from public.customers c where c.id = customer_id and c.user_id = auth.uid()));
create policy "members manage ledger" on public.credit_ledger for all using (public.is_member(business_id)) with check (public.is_member(business_id));
create policy "customer reads own ledger" on public.credit_ledger for select using (exists (select 1 from public.plan_subscriptions s join public.customers c on c.id = s.customer_id where s.id = subscription_id and c.user_id = auth.uid()));

create policy "members manage notifications" on public.notifications for all using (public.is_member(business_id)) with check (public.is_member(business_id));

grant usage on schema public to anon, authenticated;
grant select on public.businesses, public.services, public.time_slots, public.slot_closures, public.blocked_dates, public.plans to anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- =====================================================================
-- Functions used by the public website
-- =====================================================================

-- Busy times only (no customer details) so the website can show availability
create or replace function public.busy_times(p_business uuid, p_from date, p_to date)
returns table (date date, start_time time, duration_mins integer, days integer)
language sql stable security definer set search_path = public as $$
  select b.date, b.start_time, b.duration_mins, b.days
  from public.bookings b
  where b.business_id = p_business and b.status <> 'Cancelled'
    and b.date between p_from - 7 and p_to;
$$;

create or replace function public.service_price(s public.services, p_size smallint)
returns numeric language sql immutable as $$
  select case p_size
    when 2 then coalesce(s.price_large, s.price_medium, s.price_small)
    when 1 then coalesce(s.price_medium, s.price_small)
    else s.price_small end;
$$;

-- Creates a booking safely: re-checks the slot, prices it on the server, finds/creates the customer & vehicle.
create or replace function public.create_booking(p_business uuid, p jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  biz        public.businesses;
  svc        public.services;
  cust_id    uuid;
  veh_id     uuid;
  v_date     date := (p->>'date')::date;
  v_start    time := (p->>'start_time')::time;
  v_size     smallint := coalesce((p->>'size')::smallint, 0);
  v_email    text := lower(trim(p->>'email'));
  v_buffer   integer;
  v_hstart   time; v_hend time;
  v_mins     integer; v_s integer; v_e integer;
  v_price    numeric; v_callout numeric := 0; v_total numeric; v_dep numeric;
  v_out      text; sc jsonb;
  v_ref      text; v_id uuid; v_pay text := coalesce(p->>'pay','deposit');
  i          integer;
begin
  select * into biz from public.businesses where id = p_business and status <> 'suspended' for update;
  if not found then raise exception 'Business not found'; end if;
  select * into svc from public.services where id = (p->>'service_id')::uuid and business_id = p_business and active;
  if not found then raise exception 'Service not available'; end if;
  if svc.price_on_request then raise exception 'This service is priced on request — please contact us'; end if;
  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'A valid email is required'; end if;
  if coalesce(trim(p->>'first_name'),'') = '' or coalesce(trim(p->>'mobile'),'') = '' then raise exception 'Name and mobile are required'; end if;
  if v_date < current_date then raise exception 'That date has passed'; end if;

  v_buffer := coalesce((biz.settings->>'buffer')::int, 30);
  v_hstart := coalesce((biz.settings->'hours'->>'start')::time, '08:30');
  v_hend   := coalesce((biz.settings->'hours'->>'end')::time, '18:00');

  -- closed days
  for i in 0 .. greatest(svc.days,1) - 1 loop
    if not ((biz.settings->'workDays') @> to_jsonb(extract(dow from v_date + i)::int))
       or exists (select 1 from public.blocked_dates bd where bd.business_id = p_business and v_date + i between bd.from_date and bd.to_date) then
      raise exception 'Sorry, that day is not available';
    end if;
  end loop;

  if svc.days > 0 then
    v_start := v_hstart; v_mins := 0;
    for i in 0 .. svc.days - 1 loop
      if exists (select 1 from public.bookings b where b.business_id = p_business and b.status <> 'Cancelled'
                 and (b.date = v_date + i or (b.days > 0 and v_date + i between b.date and b.date + b.days - 1))) then
        raise exception 'Sorry, that day has just been booked';
      end if;
    end loop;
  else
    v_mins := svc.duration_mins;
    if coalesce(biz.settings->>'slotMode','fixed') = 'fixed' then
      if not exists (select 1 from public.time_slots t where t.business_id = p_business and t.start_time = v_start and t.enabled)
         or exists (select 1 from public.slot_closures c where c.business_id = p_business and c.date = v_date and c.start_time = v_start) then
        raise exception 'That start time is not available';
      end if;
    end if;
    v_s := extract(epoch from v_start)::int / 60; v_e := v_s + v_mins;
    if exists (
      select 1 from public.bookings b
      where b.business_id = p_business and b.status <> 'Cancelled'
        and (
          (b.days > 0 and v_date between b.date and b.date + b.days - 1)
          or (b.days = 0 and b.date = v_date
              and v_s < extract(epoch from b.start_time)::int / 60 + b.duration_mins + v_buffer
              and v_e + v_buffer > extract(epoch from b.start_time)::int / 60)
        )) then
      raise exception 'Sorry, that time has just been booked — please pick another';
    end if;
  end if;

  -- price (server side) + call-out charge by postcode district
  v_price := public.service_price(svc, v_size);
  v_out := upper(regexp_replace(coalesce(p->>'postcode',''), '\s+', '', 'g'));
  v_out := case when length(v_out) > 3 then left(v_out, length(v_out) - 3) else v_out end;
  for sc in select * from jsonb_array_elements(coalesce(biz.settings->'area'->'surcharges','[]'::jsonb)) loop
    if (sc->>'match') ~ '\d' then
      if v_out = upper(sc->>'match') then v_callout := (sc->>'fee')::numeric; exit; end if;
    elsif regexp_replace(v_out, '\d.*$', '') = upper(sc->>'match') then
      v_callout := (sc->>'fee')::numeric; exit;
    end if;
  end loop;
  v_total := v_price + v_callout;
  v_dep := round(v_total * coalesce((biz.settings->>'depositPct')::numeric, 20) / 100, 2);

  -- customer (match on email) & vehicle (match on reg)
  select id into cust_id from public.customers where business_id = p_business and lower(email) = v_email;
  if cust_id is null then
    insert into public.customers (business_id, first_name, last_name, email, mobile, house, address, postcode, user_id)
    values (p_business, trim(p->>'first_name'), coalesce(trim(p->>'last_name'),''), v_email, trim(p->>'mobile'),
            coalesce(p->>'house',''), coalesce(p->>'address',''), upper(coalesce(p->>'postcode','')),
            case when auth.uid() is not null and lower(auth.email()) = v_email then auth.uid() end)
    returning id into cust_id;
  else
    update public.customers set first_name = trim(p->>'first_name'), last_name = coalesce(trim(p->>'last_name'), last_name),
      mobile = trim(p->>'mobile'), house = coalesce(p->>'house', house), address = coalesce(p->>'address', address),
      postcode = upper(coalesce(p->>'postcode', postcode))
    where id = cust_id;
  end if;

  select id into veh_id from public.vehicles
   where customer_id = cust_id and upper(replace(reg,' ','')) = upper(replace(coalesce(p->>'reg',''),' ',''));
  if veh_id is null then
    insert into public.vehicles (business_id, customer_id, reg, make, model, colour, size)
    values (p_business, cust_id, upper(coalesce(p->>'reg','')), coalesce(p->>'make',''), coalesce(p->>'model',''), coalesce(p->>'colour',''), v_size)
    returning id into veh_id;
  else
    update public.vehicles set make = coalesce(p->>'make', make), model = coalesce(p->>'model', model), size = v_size where id = veh_id;
  end if;

  update public.businesses set ref_seq = ref_seq + 1 where id = p_business returning ref_prefix || '-' || ref_seq into v_ref;

  insert into public.bookings (business_id, ref, customer_id, vehicle_id, service_id, service_name, size, date, start_time,
     duration_mins, days, price, callout, total, status, source, notes, postcode, address)
  values (p_business, v_ref, cust_id, veh_id, svc.id, svc.name, v_size, v_date, v_start, v_mins, svc.days,
     v_price, v_callout, v_total,
     case when v_pay in ('deposit','full') and coalesce((biz.settings->>'paymentsLive')::boolean, false) then 'Pending'::public.booking_status else 'Booked'::public.booking_status end,
     'website', coalesce(p->>'notes',''), upper(coalesce(p->>'postcode','')), trim(coalesce(p->>'house','') || ' ' || coalesce(p->>'address','')))
  returning id into v_id;

  insert into public.notifications (business_id, kind, text, booking_id)
  values (p_business, 'newBooking',
          format('New booking — %s %s, %s on %s at %s', trim(p->>'first_name'), coalesce(trim(p->>'last_name'),''), svc.name, to_char(v_date,'Dy DD Mon'), to_char(v_start,'HH24:MI')),
          v_id);

  return jsonb_build_object('id', v_id, 'ref', v_ref, 'total', v_total, 'deposit', v_dep, 'callout', v_callout,
                            'status', (select status from public.bookings where id = v_id));
end $$;

-- After a customer signs up / logs in, attach their existing customer record(s) by email
create or replace function public.link_my_customer_records()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if auth.uid() is null then return 0; end if;
  update public.customers set user_id = auth.uid()
   where user_id is null and lower(email) = lower(auth.email());
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.create_booking(uuid, jsonb) from public;
grant execute on function public.busy_times(uuid, date, date) to anon, authenticated;
grant execute on function public.create_booking(uuid, jsonb) to anon, authenticated;
grant execute on function public.link_my_customer_records() to authenticated;
grant execute on function public.is_member(uuid) to anon, authenticated;
-- =====================================================================
-- B Clean Valeting — first business, services, start times
-- Prices are B Clean's own small-vehicle prices. Medium/large are left
-- blank (= same as small) until set in the admin.
-- =====================================================================
with b as (
  insert into public.businesses (slug, name, ref_prefix, settings) values (
    'bclean', 'B Clean', 'BC',
    jsonb_build_object(
      'tagline', 'Premium mobile valeting & detailing',
      'heroWhite', 'B Clean', 'heroBlue', 'Valeting',
      'heroDesc', 'Showroom finish, on your drive. Premium mobile valeting & detailing — fully insured and self-sufficient, with our own water and power.',
      'accent', '#2f7bff',
      'phone', '', 'whatsapp', '', 'email', '',
      'hours', jsonb_build_object('start','08:30','end','18:00'),
      'workDays', jsonb_build_array(1,2,3,4,5,6),
      'slotMode', 'fixed', 'buffer', 30, 'minNoticeHours', 24,
      'depositPct', 20, 'cancelHours', 48, 'prepaidOff', 20,
      'paymentsLive', false,
      'area', jsonb_build_object('mode','county','county','Kent','extra','[]'::jsonb,'excluded','[]'::jsonb,'surcharges','[]'::jsonb)
    )
  ) returning id
),
svc as (
  insert into public.services (business_id, category, name, description, includes, price_small, duration_mins, days, day_label, redeemable, price_on_request, sort)
  select b.id, x.cat, x.name, x.descr, x.inc, x.price, x.mins, x.days, x.lbl, x.redeem, x.poa, x.sort from b, (values
    ('Valeting','Maintenance Valet','A regular wash and interior tidy to keep a well-kept car looking its best between deeper cleans.', array['Snow foam pre-wash & two-bucket hand wash','Wheels, tyres & arches','Interior hoover & wipe down','Glass inside & out','Tyre dressing'], 80::numeric, 120, 0, null::text, true, false, 1),
    ('Valeting','Full Valet','Our complete inside-and-out refresh.', array['Everything in Maintenance','Door shuts & jambs','Dash, console & plastics dressed','Spray sealant','Mats cleaned'], 100, 180, 0, null, true, false, 2),
    ('Valeting','Intensive Deep Clean','For neglected vehicles — heavy soiling, pet hair and stains.', array['Full decontamination wash','Seat & carpet extraction','Pet hair removal','Leather cleaned & conditioned'], 200, 300, 0, null, false, false, 3),
    ('Valeting','Interior Deep Clean','An intensive clean focused on the cabin.', array['Hot-water extraction','Headlining spot clean','Steam clean of vents & plastics','Leather treatment'], 120, 210, 0, null, true, false, 4),
    ('Valeting','Exterior Deep Clean','Full exterior decontamination and protection.', array['Iron fallout & tar removal','Clay bar','Wheels deep cleaned','6-month sealant'], 120, 180, 0, null, true, false, 5),
    ('Detailing','Enhancement Detail + 2yr Ceramic','Single-stage machine polish to lift gloss, sealed with a 2-year ceramic coating.', array['Full decontamination','Single-stage machine polish','2-year ceramic coating','Wheel faces coated','Warranty certificate'], 500, 480, 1, '1 day', false, false, 6),
    ('Detailing','Enhancement + Ceramic + Interior','The enhancement package plus a full interior deep clean.', array['Everything in Enhancement','Interior deep clean','Fabric / leather protection'], 600, 480, 2, '1.5 days', false, false, 7),
    ('Detailing','2-Stage Correction + Ceramic + Interior','Two-stage paint correction removing most swirls, ceramic coated, plus interior deep clean.', array['Paint depth readings','2-stage compound & refine','2-year ceramic coating','Interior deep clean','Warranty certificate'], 800, 480, 2, null, false, false, 8),
    ('Additional Services','Pet Hair Removal','Specialist removal of embedded pet hair from carpets, seats and boot.', array['Rubber & pumice hair removal','High-power extraction','Boot liner clean'], null, 60, 0, null, false, true, 9),
    ('Additional Services','Engine Bay Clean','Safe degrease and dressing of the engine bay.', array['Electrics protected','Low-pressure degrease','Plastics dressed'], null, 60, 0, null, false, true, 10),
    ('Additional Services','Headlight Restoration','Removes yellowing and haze, then seals the lenses with UV protection.', array['Wet sand & machine polish','UV-resistant sealant','Both headlights'], null, 90, 0, null, false, true, 11),
    ('Additional Services','Odour Removal (Ozone)','Ozone treatment to neutralise smoke, pet and damp smells at the source.', array['Ozone generator treatment','Air-con vent treatment','Cabin aired & freshened'], null, 60, 0, null, false, true, 12),
    ('Additional Services','Glass Ceramic Coating','Hydrophobic coating for all exterior glass — rain beads straight off.', array['Glass decontamination','Ceramic glass coating','12-month durability'], null, 60, 0, null, false, true, 13)
  ) as x(cat, name, descr, inc, price, mins, days, lbl, redeem, poa, sort)
  returning id, name, business_id
),
slots as (
  insert into public.time_slots (business_id, start_time)
  select b.id, t::time from b, unnest(array['08:30','09:00','12:00','12:30','14:30','15:00','17:30','18:00']) t
  returning 1
)
insert into public.plans (business_id, name, description, service_id, eligible, counts, months, featured)
select s.business_id, p.name, p.descr, s.id,
       (select array_agg(id) from svc where name = any(p.elig)), p.counts, 12, p.featured
from svc s
join (values
  ('Maintenance Plan','12 visits for a monthly clean, or 24 for fortnightly.','Maintenance Valet', array['Maintenance Valet'], array[12,24], true),
  ('Full Valet Plan','Full inside-and-out valets through the year. Credits can also be used on maintenance valets.','Full Valet', array['Full Valet','Maintenance Valet'], array[6,12], false)
) as p(name, descr, svc_name, elig, counts, featured) on p.svc_name = s.name;
revoke execute on function public.link_my_customer_records() from public, anon;
grant execute on function public.link_my_customer_records() to authenticated;
revoke execute on function public.busy_times(uuid, date, date) from public;
grant execute on function public.busy_times(uuid, date, date) to anon, authenticated;
-- Online booking switch: website visitors can only book when settings.onlineBooking = true.
-- Business admins can always add bookings (any time, past dates for transfers, custom price).
update public.businesses set settings = settings || '{"onlineBooking": false}'::jsonb where slug = 'bclean';

create or replace function public.create_booking(p_business uuid, p jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  biz        public.businesses;
  svc        public.services;
  cust_id    uuid;
  veh_id     uuid;
  v_date     date := (p->>'date')::date;
  v_start    time := (p->>'start_time')::time;
  v_size     smallint := coalesce((p->>'size')::smallint, 0);
  v_email    text := lower(trim(p->>'email'));
  v_buffer   integer;
  v_hstart   time; v_hend time;
  v_mins     integer; v_s integer; v_e integer;
  v_price    numeric; v_callout numeric := 0; v_total numeric; v_dep numeric;
  v_out      text; sc jsonb;
  v_ref      text; v_id uuid; v_pay text := coalesce(p->>'pay','deposit');
  i          integer;
  v_admin    boolean := false;
begin
  select * into biz from public.businesses where id = p_business and status <> 'suspended' for update;
  if not found then raise exception 'Business not found'; end if;
  v_admin := public.is_member(p_business);
  if not v_admin and not coalesce((biz.settings->>'onlineBooking')::boolean, false) then
    raise exception 'Online booking is not open yet — please contact us to book';
  end if;
  select * into svc from public.services where id = (p->>'service_id')::uuid and business_id = p_business and active;
  if not found then raise exception 'Service not available'; end if;
  if svc.price_on_request and not v_admin then raise exception 'This service is priced on request — please contact us'; end if;
  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'A valid email is required'; end if;
  if coalesce(trim(p->>'first_name'),'') = '' or coalesce(trim(p->>'mobile'),'') = '' then raise exception 'Name and mobile are required'; end if;
  if v_date < current_date and not v_admin then raise exception 'That date has passed'; end if;

  v_buffer := coalesce((biz.settings->>'buffer')::int, 30);
  v_hstart := coalesce((biz.settings->'hours'->>'start')::time, '08:30');
  v_hend   := coalesce((biz.settings->'hours'->>'end')::time, '18:00');

  if not v_admin then
    for i in 0 .. greatest(svc.days,1) - 1 loop
      if not ((biz.settings->'workDays') @> to_jsonb(extract(dow from v_date + i)::int))
         or exists (select 1 from public.blocked_dates bd where bd.business_id = p_business and v_date + i between bd.from_date and bd.to_date) then
        raise exception 'Sorry, that day is not available';
      end if;
    end loop;
  end if;

  if svc.days > 0 then
    v_start := v_hstart; v_mins := 0;
    for i in 0 .. svc.days - 1 loop
      if exists (select 1 from public.bookings b where b.business_id = p_business and b.status <> 'Cancelled'
                 and (b.date = v_date + i or (b.days > 0 and v_date + i between b.date and b.date + b.days - 1))) then
        raise exception 'Sorry, that day has just been booked';
      end if;
    end loop;
  else
    v_mins := svc.duration_mins;
    if coalesce(biz.settings->>'slotMode','fixed') = 'fixed' and not v_admin then
      if not exists (select 1 from public.time_slots t where t.business_id = p_business and t.start_time = v_start and t.enabled)
         or exists (select 1 from public.slot_closures c where c.business_id = p_business and c.date = v_date and c.start_time = v_start) then
        raise exception 'That start time is not available';
      end if;
    end if;
    v_s := extract(epoch from v_start)::int / 60; v_e := v_s + v_mins;
    if exists (
      select 1 from public.bookings b
      where b.business_id = p_business and b.status <> 'Cancelled'
        and (
          (b.days > 0 and v_date between b.date and b.date + b.days - 1)
          or (b.days = 0 and b.date = v_date
              and v_s < extract(epoch from b.start_time)::int / 60 + b.duration_mins + v_buffer
              and v_e + v_buffer > extract(epoch from b.start_time)::int / 60)
        )) then
      raise exception 'Sorry, that time has just been booked — please pick another';
    end if;
  end if;

  -- price (server side) + call-out charge by postcode district
  v_price := case when v_admin and p ? 'price' then (p->>'price')::numeric else coalesce(public.service_price(svc, v_size), 0) end;
  v_out := upper(regexp_replace(coalesce(p->>'postcode',''), '\s+', '', 'g'));
  v_out := case when length(v_out) > 3 then left(v_out, length(v_out) - 3) else v_out end;
  for sc in select * from jsonb_array_elements(coalesce(biz.settings->'area'->'surcharges','[]'::jsonb)) loop
    if (sc->>'match') ~ '\d' then
      if v_out = upper(sc->>'match') then v_callout := (sc->>'fee')::numeric; exit; end if;
    elsif regexp_replace(v_out, '\d.*$', '') = upper(sc->>'match') then
      v_callout := (sc->>'fee')::numeric; exit;
    end if;
  end loop;
  v_total := v_price + v_callout;
  v_dep := round(v_total * coalesce((biz.settings->>'depositPct')::numeric, 20) / 100, 2);

  -- customer (match on email) & vehicle (match on reg)
  select id into cust_id from public.customers where business_id = p_business and lower(email) = v_email;
  if cust_id is null then
    insert into public.customers (business_id, first_name, last_name, email, mobile, house, address, postcode, user_id)
    values (p_business, trim(p->>'first_name'), coalesce(trim(p->>'last_name'),''), v_email, trim(p->>'mobile'),
            coalesce(p->>'house',''), coalesce(p->>'address',''), upper(coalesce(p->>'postcode','')),
            case when auth.uid() is not null and lower(auth.email()) = v_email then auth.uid() end)
    returning id into cust_id;
  else
    update public.customers set first_name = trim(p->>'first_name'), last_name = coalesce(trim(p->>'last_name'), last_name),
      mobile = trim(p->>'mobile'), house = coalesce(p->>'house', house), address = coalesce(p->>'address', address),
      postcode = upper(coalesce(p->>'postcode', postcode))
    where id = cust_id;
  end if;

  select id into veh_id from public.vehicles
   where customer_id = cust_id and upper(replace(reg,' ','')) = upper(replace(coalesce(p->>'reg',''),' ',''));
  if veh_id is null then
    insert into public.vehicles (business_id, customer_id, reg, make, model, colour, size)
    values (p_business, cust_id, upper(coalesce(p->>'reg','')), coalesce(p->>'make',''), coalesce(p->>'model',''), coalesce(p->>'colour',''), v_size)
    returning id into veh_id;
  else
    update public.vehicles set make = coalesce(p->>'make', make), model = coalesce(p->>'model', model), size = v_size where id = veh_id;
  end if;

  update public.businesses set ref_seq = ref_seq + 1 where id = p_business returning ref_prefix || '-' || ref_seq into v_ref;

  insert into public.bookings (business_id, ref, customer_id, vehicle_id, service_id, service_name, size, date, start_time,
     duration_mins, days, price, callout, total, status, source, notes, postcode, address)
  values (p_business, v_ref, cust_id, veh_id, svc.id, svc.name, v_size, v_date, v_start, v_mins, svc.days,
     v_price, v_callout, v_total,
     case when v_pay in ('deposit','full') and coalesce((biz.settings->>'paymentsLive')::boolean, false) and not v_admin then 'Pending'::public.booking_status else 'Booked'::public.booking_status end,
     case when v_admin then 'manual' else 'website' end, coalesce(p->>'notes',''), upper(coalesce(p->>'postcode','')), trim(coalesce(p->>'house','') || ' ' || coalesce(p->>'address','')))
  returning id into v_id;

  if not v_admin then
  insert into public.notifications (business_id, kind, text, booking_id)
  values (p_business, 'newBooking',
          format('New booking — %s %s, %s on %s at %s', trim(p->>'first_name'), coalesce(trim(p->>'last_name'),''), svc.name, to_char(v_date,'Dy DD Mon'), to_char(v_start,'HH24:MI')),
          v_id);
  end if;

  return jsonb_build_object('id', v_id, 'ref', v_ref, 'total', v_total, 'deposit', v_dep, 'callout', v_callout,
                            'status', (select status from public.bookings where id = v_id));
end $$;

revoke all on function public.create_booking(uuid, jsonb) from public;
grant execute on function public.create_booking(uuid, jsonb) to anon, authenticated;
-- Website content managed from admin + image storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 8388608, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "members upload media" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "members update media" on storage.objects for update to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "members delete media" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "members list media" on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));

update public.businesses set settings = settings || '{"terms": "Bookings are confirmed once the deposit is received. We need access to water and electricity, or we will bring our own (please let us know). Vehicles must be accessible at the booked time. Prices may vary on inspection where condition is significantly worse than described.", "cancel": "You can cancel or reschedule free of charge up to 48 hours before your appointment and your deposit will be refunded. Within 48 hours the deposit is non-refundable but can be moved to a new date once.", "refund": "If you are unhappy with any part of the service, tell us within 48 hours and we will return to put it right. Refunds of balances are issued to the original payment method within 5\u201310 working days.", "faq": [["Do I need to provide water and power?", "No \u2014 we are fully self-sufficient, though access to an outside tap is always helpful."], ["How long does a valet take?", "Maintenance valets take around 2 hours; full valets around 3. Detailing packages are full-day or multi-day bookings."], ["How does the deposit work?", "A 20% deposit secures your slot. The balance is paid on the day by card, cash or bank transfer."], ["What areas do you cover?", "We cover the whole of Kent. Enter your postcode when booking to check instantly."], ["How do pre-paid plans work?", "Pay once for 12 or 24 valets at 20% off, then book them whenever suits you \u2014 no paying each time."], ["Can I buy a gift voucher?", "Yes \u2014 message us on WhatsApp and we''ll arrange a voucher for any amount or service."]], "heroSlides": [], "offers": [], "stats": [{"v": "Kent", "l": "fully mobile service"}, {"v": "100%", "l": "fully insured"}, {"v": "20%", "l": "off pre-paid plans"}, {"v": "7 days", "l": "online enquiries"}], "social": {"facebook": "https://www.facebook.com/share/192dtBBr77/?mibextid=wwXIfr", "instagram": "", "tiktok": "", "google": ""}}'::jsonb
where slug = 'bclean' and not (settings ? 'faq');
-- Admin bookings: mobile number optional (existing maintenance clients)
create or replace function public.create_booking(p_business uuid, p jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  biz        public.businesses;
  svc        public.services;
  cust_id    uuid;
  veh_id     uuid;
  v_date     date := (p->>'date')::date;
  v_start    time := (p->>'start_time')::time;
  v_size     smallint := coalesce((p->>'size')::smallint, 0);
  v_email    text := lower(trim(p->>'email'));
  v_buffer   integer;
  v_hstart   time; v_hend time;
  v_mins     integer; v_s integer; v_e integer;
  v_price    numeric; v_callout numeric := 0; v_total numeric; v_dep numeric;
  v_out      text; sc jsonb;
  v_ref      text; v_id uuid; v_pay text := coalesce(p->>'pay','deposit');
  i          integer;
  v_admin    boolean := false;
begin
  select * into biz from public.businesses where id = p_business and status <> 'suspended' for update;
  if not found then raise exception 'Business not found'; end if;
  v_admin := public.is_member(p_business);
  if not v_admin and not coalesce((biz.settings->>'onlineBooking')::boolean, false) then
    raise exception 'Online booking is not open yet — please contact us to book';
  end if;
  select * into svc from public.services where id = (p->>'service_id')::uuid and business_id = p_business and active;
  if not found then raise exception 'Service not available'; end if;
  if svc.price_on_request and not v_admin then raise exception 'This service is priced on request — please contact us'; end if;
  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'A valid email is required'; end if;
  if coalesce(trim(p->>'first_name'),'') = '' then raise exception 'Name is required'; end if;
  if not v_admin and coalesce(trim(p->>'mobile'),'') = '' then raise exception 'Mobile number is required'; end if;
  if v_date < current_date and not v_admin then raise exception 'That date has passed'; end if;

  v_buffer := coalesce((biz.settings->>'buffer')::int, 30);
  v_hstart := coalesce((biz.settings->'hours'->>'start')::time, '08:30');
  v_hend   := coalesce((biz.settings->'hours'->>'end')::time, '18:00');

  if not v_admin then
    for i in 0 .. greatest(svc.days,1) - 1 loop
      if not ((biz.settings->'workDays') @> to_jsonb(extract(dow from v_date + i)::int))
         or exists (select 1 from public.blocked_dates bd where bd.business_id = p_business and v_date + i between bd.from_date and bd.to_date) then
        raise exception 'Sorry, that day is not available';
      end if;
    end loop;
  end if;

  if svc.days > 0 then
    v_start := v_hstart; v_mins := 0;
    for i in 0 .. svc.days - 1 loop
      if exists (select 1 from public.bookings b where b.business_id = p_business and b.status <> 'Cancelled'
                 and (b.date = v_date + i or (b.days > 0 and v_date + i between b.date and b.date + b.days - 1))) then
        raise exception 'Sorry, that day has just been booked';
      end if;
    end loop;
  else
    v_mins := svc.duration_mins;
    if coalesce(biz.settings->>'slotMode','fixed') = 'fixed' and not v_admin then
      if not exists (select 1 from public.time_slots t where t.business_id = p_business and t.start_time = v_start and t.enabled)
         or exists (select 1 from public.slot_closures c where c.business_id = p_business and c.date = v_date and c.start_time = v_start) then
        raise exception 'That start time is not available';
      end if;
    end if;
    v_s := extract(epoch from v_start)::int / 60; v_e := v_s + v_mins;
    if exists (
      select 1 from public.bookings b
      where b.business_id = p_business and b.status <> 'Cancelled'
        and (
          (b.days > 0 and v_date between b.date and b.date + b.days - 1)
          or (b.days = 0 and b.date = v_date
              and v_s < extract(epoch from b.start_time)::int / 60 + b.duration_mins + v_buffer
              and v_e + v_buffer > extract(epoch from b.start_time)::int / 60)
        )) then
      raise exception 'Sorry, that time has just been booked — please pick another';
    end if;
  end if;

  -- price (server side) + call-out charge by postcode district
  v_price := case when v_admin and p ? 'price' then (p->>'price')::numeric else coalesce(public.service_price(svc, v_size), 0) end;
  v_out := upper(regexp_replace(coalesce(p->>'postcode',''), '\s+', '', 'g'));
  v_out := case when length(v_out) > 3 then left(v_out, length(v_out) - 3) else v_out end;
  for sc in select * from jsonb_array_elements(coalesce(biz.settings->'area'->'surcharges','[]'::jsonb)) loop
    if (sc->>'match') ~ '\d' then
      if v_out = upper(sc->>'match') then v_callout := (sc->>'fee')::numeric; exit; end if;
    elsif regexp_replace(v_out, '\d.*$', '') = upper(sc->>'match') then
      v_callout := (sc->>'fee')::numeric; exit;
    end if;
  end loop;
  v_total := v_price + v_callout;
  v_dep := round(v_total * coalesce((biz.settings->>'depositPct')::numeric, 20) / 100, 2);

  -- customer (match on email) & vehicle (match on reg)
  select id into cust_id from public.customers where business_id = p_business and lower(email) = v_email;
  if cust_id is null then
    insert into public.customers (business_id, first_name, last_name, email, mobile, house, address, postcode, user_id)
    values (p_business, trim(p->>'first_name'), coalesce(trim(p->>'last_name'),''), v_email, coalesce(trim(p->>'mobile'),''),
            coalesce(p->>'house',''), coalesce(p->>'address',''), upper(coalesce(p->>'postcode','')),
            case when auth.uid() is not null and lower(auth.email()) = v_email then auth.uid() end)
    returning id into cust_id;
  else
    update public.customers set first_name = trim(p->>'first_name'), last_name = coalesce(trim(p->>'last_name'), last_name),
      mobile = coalesce(nullif(trim(p->>'mobile'),''), mobile), house = coalesce(p->>'house', house), address = coalesce(p->>'address', address),
      postcode = upper(coalesce(p->>'postcode', postcode))
    where id = cust_id;
  end if;

  select id into veh_id from public.vehicles
   where customer_id = cust_id and upper(replace(reg,' ','')) = upper(replace(coalesce(p->>'reg',''),' ',''));
  if veh_id is null then
    insert into public.vehicles (business_id, customer_id, reg, make, model, colour, size)
    values (p_business, cust_id, upper(coalesce(p->>'reg','')), coalesce(p->>'make',''), coalesce(p->>'model',''), coalesce(p->>'colour',''), v_size)
    returning id into veh_id;
  else
    update public.vehicles set make = coalesce(p->>'make', make), model = coalesce(p->>'model', model), size = v_size where id = veh_id;
  end if;

  update public.businesses set ref_seq = ref_seq + 1 where id = p_business returning ref_prefix || '-' || ref_seq into v_ref;

  insert into public.bookings (business_id, ref, customer_id, vehicle_id, service_id, service_name, size, date, start_time,
     duration_mins, days, price, callout, total, status, source, notes, postcode, address)
  values (p_business, v_ref, cust_id, veh_id, svc.id, svc.name, v_size, v_date, v_start, v_mins, svc.days,
     v_price, v_callout, v_total,
     case when v_pay in ('deposit','full') and coalesce((biz.settings->>'paymentsLive')::boolean, false) and not v_admin then 'Pending'::public.booking_status else 'Booked'::public.booking_status end,
     case when v_admin then 'manual' else 'website' end, coalesce(p->>'notes',''), upper(coalesce(p->>'postcode','')), trim(coalesce(p->>'house','') || ' ' || coalesce(p->>'address','')))
  returning id into v_id;

  if not v_admin then
  insert into public.notifications (business_id, kind, text, booking_id)
  values (p_business, 'newBooking',
          format('New booking — %s %s, %s on %s at %s', trim(p->>'first_name'), coalesce(trim(p->>'last_name'),''), svc.name, to_char(v_date,'Dy DD Mon'), to_char(v_start,'HH24:MI')),
          v_id);
  end if;

  return jsonb_build_object('id', v_id, 'ref', v_ref, 'total', v_total, 'deposit', v_dep, 'callout', v_callout,
                            'status', (select status from public.bookings where id = v_id));
end $$;

revoke all on function public.create_booking(uuid, jsonb) from public;
grant execute on function public.create_booking(uuid, jsonb) to anon, authenticated;
