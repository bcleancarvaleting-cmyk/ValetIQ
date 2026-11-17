-- Offers as % off, £ off or a fixed price; monthly memberships (Stripe subscriptions); regular slots;
-- business/fleet accounts with monthly statements; "due a clean" list; push a customer from the admin app.

-- ---------- offers ----------
alter table public.services add column if not exists offer_amount numeric(10,2);   -- £ off
alter table public.services add column if not exists offer_price  numeric(10,2);   -- fixed price (small); bigger sizes keep their difference
create or replace function public.offer_price(svc public.services, p_size smallint, p_date date) returns numeric
language sql stable as $$
  select case
    when (svc.offer_pct is null or svc.offer_pct = 0) and svc.offer_amount is null and svc.offer_price is null then public.service_price(svc, p_size)
    when svc.offer_until is not null and svc.offer_until < p_date then public.service_price(svc, p_size)
    when svc.offer_price is not null then greatest(0, svc.offer_price + (public.service_price(svc, p_size) - public.service_price(svc, 0::smallint)))
    when svc.offer_amount is not null then greatest(0, public.service_price(svc, p_size) - svc.offer_amount)
    else round(public.service_price(svc, p_size) * (1 - svc.offer_pct / 100), 2) end;
$$;

-- ---------- business / fleet accounts ----------
alter table public.customers add column if not exists business_account boolean not null default false;
alter table public.customers add column if not exists company_name text;
alter table public.customers add column if not exists invoice_email text;
alter table public.bookings add column if not exists statement_id text;

-- ---------- memberships (monthly, Stripe Billing) ----------
create table if not exists public.memberships (
  id               uuid primary key default gen_random_uuid(),
  business_id      uuid not null references public.businesses on delete cascade,
  name             text not null,
  description      text not null default '',
  washes_per_month integer not null default 1,
  price_monthly    numeric(10,2) not null,
  eligible         uuid[] not null default '{}',
  active           boolean not null default true,
  sort             integer not null default 0,
  created_at       timestamptz not null default now()
);
alter table public.memberships enable row level security;
drop policy if exists "public read memberships" on public.memberships;
create policy "public read memberships" on public.memberships for select using (true);
drop policy if exists "members manage memberships" on public.memberships;
create policy "members manage memberships" on public.memberships for all using (public.is_member(business_id)) with check (public.is_member(business_id));
grant select on public.memberships to anon, authenticated; grant insert, update, delete on public.memberships to authenticated;
alter table public.plan_subscriptions add column if not exists stripe_sub_id text;
alter table public.plan_subscriptions add column if not exists membership_id uuid references public.memberships on delete set null;
create unique index if not exists plan_subs_stripe_sub on public.plan_subscriptions (stripe_sub_id) where stripe_sub_id is not null;

-- ---------- regular slots ----------
create table if not exists public.regular_slots (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses on delete cascade,
  customer_id  uuid not null references public.customers on delete cascade,
  service_id   uuid not null references public.services on delete cascade,
  cars         jsonb not null default '[]',
  every_weeks  integer not null default 4 check (every_weeks between 1 and 26),
  start_time   time not null,
  next_date    date not null,
  active       boolean not null default true,
  notes        text not null default '',
  created_at   timestamptz not null default now()
);
alter table public.regular_slots enable row level security;
drop policy if exists "members manage regulars" on public.regular_slots;
create policy "members manage regulars" on public.regular_slots for all using (public.is_member(business_id)) with check (public.is_member(business_id));
drop policy if exists "customer manages own regulars" on public.regular_slots;
create policy "customer manages own regulars" on public.regular_slots for all
  using (exists (select 1 from public.customers c where c.id = customer_id and c.user_id = auth.uid()))
  with check (exists (select 1 from public.customers c where c.id = customer_id and c.user_id = auth.uid() and c.business_id = regular_slots.business_id));
grant select, insert, update, delete on public.regular_slots to authenticated;

-- book regular slots up to 4 weeks ahead (runs daily); clashes are skipped and flagged to the business
create or replace function private.book_regulars() returns void
language plpgsql security definer set search_path = public, private as $$
declare r record; c public.customers; res jsonb; v_cr int; q int;
begin
  for r in select * from public.regular_slots where active and next_date <= current_date + 28 for update loop
    select * into c from public.customers where id = r.customer_id;
    while r.next_date <= current_date + 28 loop
      if r.next_date >= current_date then
        q := greatest(jsonb_array_length(r.cars), 1);
        select coalesce(sum(s.credits),0) into v_cr from public.plan_subscriptions s
         where s.customer_id = c.id and s.status = 'active' and s.end_date >= r.next_date
           and (cardinality(s.eligible) = 0 or r.service_id = any(s.eligible));
        begin
          res := public.create_booking(r.business_id, jsonb_build_object(
            'service_id', r.service_id, 'date', r.next_date, 'start_time', r.start_time,
            'first_name', c.first_name, 'last_name', c.last_name, 'email', c.email, 'mobile', c.mobile,
            'address', trim(coalesce(c.house,'') || ' ' || coalesce(c.address,'')), 'postcode', c.postcode,
            'vehicles', case when jsonb_array_length(r.cars) > 0 then r.cars else null end,
            'pay', case when v_cr >= q then 'credit' else 'deposit' end,
            'notes', 'Regular slot — every ' || r.every_weeks || ' weeks'));
        exception when others then
          insert into public.notifications (business_id, kind, text)
          values (r.business_id, 'regularClash', format('Couldn''t book %s %s''s regular slot on %s at %s — %s',
                  c.first_name, c.last_name, to_char(r.next_date,'Dy DD Mon'), to_char(r.start_time,'HH24:MI'), sqlerrm));
        end;
      end if;
      r.next_date := r.next_date + r.every_weeks * 7;
    end loop;
    update public.regular_slots set next_date = r.next_date where id = r.id;
  end loop;
end $$;
select cron.unschedule('valetiq-regulars') where exists (select 1 from cron.job where jobname = 'valetiq-regulars');
select cron.schedule('valetiq-regulars', '7 5 * * *', 'select private.book_regulars()');

-- ---------- admin helpers ----------

create or replace function public.lapsing_customers(p_business uuid, p_min_weeks int default 6)
returns table (customer_id uuid, first_name text, last_name text, mobile text, email text, last_date date, last_service text,
               visits bigint, spend numeric, has_app boolean, weeks int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  return query
  select c.id, c.first_name, c.last_name, c.mobile, c.email, x.last_date, x.last_service, x.visits, x.spend,
         exists (select 1 from public.push_subscriptions s where s.customer_id = c.id), ((current_date - x.last_date) / 7)::int
  from public.customers c
  join lateral (select max(b.date) last_date, (array_agg(b.service_name order by b.date desc))[1] last_service,
                       count(*) visits, coalesce(sum(b.total),0) spend
                from public.bookings b where b.customer_id = c.id and b.status <> 'Cancelled') x on x.last_date is not null
  where c.business_id = p_business and x.last_date <= current_date - p_min_weeks * 7
    and not exists (select 1 from public.bookings f where f.customer_id = c.id and f.status <> 'Cancelled' and f.date > current_date)
  order by x.last_date desc;
end $$;
grant execute on function public.lapsing_customers(uuid, int) to authenticated;

-- ---------- create_booking: offer function, internal (cron) bookings, business accounts book without deposit ----------
do $do$
declare d text;
begin
  select pg_get_functiondef('public.create_booking(uuid,jsonb)'::regprocedure) into d;
  if position('public.offer_price(svc' in d) > 0 then return; end if;
  d := replace(d, 'v_price := v_price + round(coalesce(public.service_price(svc, coalesce((v_veh->>''size'')::smallint, v_size)), 0)
        * (case when coalesce(svc.offer_pct, 0) > 0 and (svc.offer_until is null or svc.offer_until >= v_date) then 1 - svc.offer_pct / 100 else 1 end), 2);',
    'v_price := v_price + coalesce(public.offer_price(svc, coalesce((v_veh->>''size'')::smallint, v_size), v_date), 0);');
  d := replace(d, '  v_admin := public.is_member(p_business);', '  v_admin := public.is_member(p_business) or session_user = ''postgres'';');
  d := replace(d, 'and coalesce((biz.settings->>''paymentsLive'')::boolean, false) and not v_admin then ''Pending''',
                  'and coalesce((biz.settings->>''paymentsLive'')::boolean, false) and not v_admin and not coalesce((select business_account from public.customers where id = cust_id), false) then ''Pending''');
  if position('public.offer_price(svc' in d) = 0 or position('session_user' in d) = 0 or position('business_account' in d) = 0 then
    raise exception 'create_booking patch did not apply cleanly';
  end if;
  execute d;
end $do$;

-- ---------- emails (Resend) — key entered in the admin app, stored privately ----------
alter table private.business_secrets add column if not exists resend_key text;
alter table private.business_secrets add column if not exists email_from text;
create or replace function public.save_email_settings(p_business uuid, p_key text, p_from text) returns void
language plpgsql security definer set search_path = public, private as $$
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  insert into private.business_secrets (business_id, resend_key, email_from) values (p_business, nullif(p_key,''), nullif(p_from,''))
  on conflict (business_id) do update set resend_key = coalesce(nullif(p_key,''), private.business_secrets.resend_key),
    email_from = coalesce(nullif(p_from,''), private.business_secrets.email_from), updated_at = now();
end $$;
create or replace function public.clear_email_settings(p_business uuid) returns void
language plpgsql security definer set search_path = public, private as $$
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  update private.business_secrets set resend_key = null where business_id = p_business;
end $$;
create or replace function public.email_status(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = public, private as $$
declare r private.business_secrets;
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  select * into r from private.business_secrets where business_id = p_business;
  return jsonb_build_object('connected', r.resend_key is not null, 'key', case when r.resend_key is not null then left(r.resend_key, 5) || '…' || right(r.resend_key, 4) end, 'from', r.email_from);
end $$;
create or replace function public.get_business_email(p_business uuid) returns jsonb
language sql stable security definer set search_path = public, private as $$
  select coalesce((select jsonb_build_object('key', resend_key, 'from', email_from) from private.business_secrets where business_id = p_business and resend_key is not null), '{}'::jsonb);
$$;
revoke execute on function public.get_business_email(uuid) from public, anon, authenticated;
grant execute on function public.get_business_email(uuid) to service_role;
grant execute on function public.save_email_settings(uuid, text, text) to authenticated;
grant execute on function public.clear_email_settings(uuid) to authenticated;
grant execute on function public.email_status(uuid) to authenticated;

-- queue an email through the send-email function (does nothing if the business hasn't connected Resend)
create or replace function private.queue_email(p_business uuid, p_kind text, p_customer uuid, p_booking uuid, p_amount numeric default null)
returns void language plpgsql security definer set search_path = public, private as $$
declare hook text;
begin
  if not exists (select 1 from private.business_secrets where business_id = p_business and resend_key is not null) then return; end if;
  select v into hook from private.app_secrets where k = 'push_hook';
  if hook is null then return; end if;
  begin
    perform net.http_post(url := 'https://tigznsqtesgofvoflmem.supabase.co/functions/v1/send-email',
      body := jsonb_build_object('business_id', p_business, 'kind', p_kind, 'customer_id', p_customer, 'booking_id', p_booking, 'amount', p_amount),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', hook));
  exception when others then null;
  end;
end $$;

create or replace function public.email_on_registered() returns trigger language plpgsql security definer set search_path = public, private as $$
begin
  if new.user_id is not null and (tg_op = 'INSERT' or old.user_id is null) then perform private.queue_email(new.business_id, 'welcome', new.id, null); end if;
  return new;
end $$;
drop trigger if exists customers_email_welcome on public.customers;
create trigger customers_email_welcome after insert or update of user_id on public.customers for each row execute function public.email_on_registered();

create or replace function public.email_on_booking() returns trigger language plpgsql security definer set search_path = public, private as $$
begin
  if tg_op = 'INSERT' and new.status in ('Booked','Confirmed') and new.date >= current_date
     and (new.repeat_group is null or not exists (select 1 from public.bookings x where x.repeat_group = new.repeat_group and x.date < new.date)) then
    perform private.queue_email(new.business_id, 'confirmed', new.customer_id, new.id);
  elsif tg_op = 'UPDATE' and old.status = 'Pending' and new.status = 'Booked' then
    perform private.queue_email(new.business_id, 'confirmed', new.customer_id, new.id);
  end if;
  return new;
end $$;
drop trigger if exists bookings_email on public.bookings;
create trigger bookings_email after insert or update of status on public.bookings for each row execute function public.email_on_booking();

create or replace function public.email_on_payment() returns trigger language plpgsql security definer set search_path = public, private as $$
begin
  if new.customer_id is not null and new.amount > 0 then perform private.queue_email(new.business_id, 'received', new.customer_id, new.booking_id, new.amount); end if;
  return new;
end $$;
drop trigger if exists payments_email on public.payments;
create trigger payments_email after insert on public.payments for each row execute function public.email_on_payment();

-- admin: push a message to a customer, optionally about a booking
create or replace function public.send_customer_push(p_customer uuid, p_msg text, p_booking uuid default null) returns void
language plpgsql security definer set search_path = public, private as $$
begin
  if not public.is_member((select business_id from public.customers where id = p_customer)) then raise exception 'Not allowed'; end if;
  perform private.customer_push(p_customer, p_msg, p_booking);
end $$;
grant execute on function public.send_customer_push(uuid, text, uuid) to authenticated;
