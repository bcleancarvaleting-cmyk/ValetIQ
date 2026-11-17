-- Growth & retention: review requests, job photos + website gallery, coating check-ups, refer-a-friend (£5/£5), online plan purchases
-- ---------- photos & gallery ----------
create table if not exists public.booking_photos (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  booking_id  uuid not null references public.bookings on delete cascade,
  kind        text not null default 'after' check (kind in ('before','after')),
  url         text not null,
  created_at  timestamptz not null default now()
);
create index if not exists booking_photos_booking on public.booking_photos (booking_id);
alter table public.booking_photos enable row level security;
drop policy if exists "members manage photos" on public.booking_photos;
create policy "members manage photos" on public.booking_photos for all using (public.is_member(business_id)) with check (public.is_member(business_id));
drop policy if exists "customer reads own photos" on public.booking_photos;
create policy "customer reads own photos" on public.booking_photos for select using (exists (
  select 1 from public.bookings b join public.customers c on c.id = b.customer_id where b.id = booking_id and c.user_id = auth.uid()));
grant select, insert, update, delete on public.booking_photos to authenticated;

create table if not exists public.gallery_items (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  booking_id  uuid references public.bookings on delete set null,
  title       text not null default '',
  before_url  text,
  after_url   text,
  show        boolean not null default true,
  sort        integer not null default 0,
  created_at  timestamptz not null default now()
);
alter table public.gallery_items enable row level security;
drop policy if exists "public reads gallery" on public.gallery_items;
create policy "public reads gallery" on public.gallery_items for select using (show or public.is_member(business_id));
drop policy if exists "members manage gallery" on public.gallery_items;
create policy "members manage gallery" on public.gallery_items for all using (public.is_member(business_id)) with check (public.is_member(business_id));
grant select on public.gallery_items to anon, authenticated;
grant insert, update, delete on public.gallery_items to authenticated;

-- ---------- referrals & rewards ----------
alter table public.customers add column if not exists referral_code text;
alter table public.customers add column if not exists referred_by uuid references public.customers on delete set null;
alter table public.customers add column if not exists reward_balance numeric(10,2) not null default 0;
alter table public.customers add column if not exists referral_rewarded boolean not null default false;
create unique index if not exists customers_ref_code on public.customers (business_id, upper(referral_code));
create or replace function public.make_ref_code() returns trigger language plpgsql as $$
declare c text;
begin
  if new.referral_code is null or new.referral_code = '' then
    loop
      c := upper(regexp_replace(left(coalesce(nullif(new.first_name,''),'BC'), 4), '[^A-Za-z]', '', 'g')) || lpad((floor(random()*900)+100)::int::text, 3, '0');
      exit when not exists (select 1 from public.customers where business_id = new.business_id and upper(referral_code) = c);
    end loop;
    new.referral_code := c;
  end if;
  return new;
end $$;
drop trigger if exists customers_ref_code on public.customers;
create trigger customers_ref_code before insert or update of referral_code on public.customers for each row execute function public.make_ref_code();
update public.customers set referral_code = null where referral_code is null;  -- fires trigger to back-fill codes

create table if not exists public.reward_ledger (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  customer_id uuid not null references public.customers on delete cascade,
  amount      numeric(10,2) not null,
  note        text not null default '',
  booking_id  uuid references public.bookings on delete set null,
  created_at  timestamptz not null default now()
);
alter table public.reward_ledger enable row level security;
drop policy if exists "members manage rewards" on public.reward_ledger;
create policy "members manage rewards" on public.reward_ledger for all using (public.is_member(business_id)) with check (public.is_member(business_id));
drop policy if exists "customer reads own rewards" on public.reward_ledger;
create policy "customer reads own rewards" on public.reward_ledger for select using (exists (select 1 from public.customers c where c.id = customer_id and c.user_id = auth.uid()));
grant select on public.reward_ledger to authenticated; grant insert on public.reward_ledger to authenticated;

-- ---------- job completion: reviews, referral rewards ----------
alter table public.bookings add column if not exists completed_at timestamptz;
alter table public.bookings add column if not exists review_sent_at timestamptz;
alter table public.bookings add column if not exists checkup_sent date;

create or replace function public.on_booking_completed() returns trigger
language plpgsql security definer set search_path = public, private as $$
declare c public.customers; amt numeric;
begin
  if new.status = 'Completed' and old.status is distinct from 'Completed' then
    update public.bookings set completed_at = now() where id = new.id and completed_at is null;
    select * into c from public.customers where id = new.customer_id;
    if c.referred_by is not null and not c.referral_rewarded then
      select coalesce((settings->>'referralReward')::numeric, 5) into amt from public.businesses where id = new.business_id;
      update public.customers set referral_rewarded = true where id = c.id;
      update public.customers set reward_balance = reward_balance + amt where id = c.referred_by;
      insert into public.reward_ledger (business_id, customer_id, amount, note, booking_id)
      values (new.business_id, c.referred_by, amt, 'Referral reward — ' || c.first_name || ' booked with us', new.id);
      insert into public.notifications (business_id, kind, text, booking_id)
      values (new.business_id, 'referral', format('Referral reward — £%s credit given to %s for referring %s %s',
              amt, (select first_name || ' ' || last_name from public.customers where id = c.referred_by), c.first_name, c.last_name), new.id);
      perform private.customer_push(c.referred_by, 'referral', new.id, amt);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists bookings_completed on public.bookings;
create trigger bookings_completed after update of status on public.bookings for each row execute function public.on_booking_completed();

-- review requests ~1 hour after a job is completed; coating check-ups every 6 months
create or replace function private.send_followups() returns void
language plpgsql security definer set search_path = public, private as $$
declare b record; n int;
begin
  for b in select id, customer_id from public.bookings
           where status = 'Completed' and review_sent_at is null and completed_at between now() - interval '3 hours' and now() - interval '60 minutes' loop
    update public.bookings set review_sent_at = now() where id = b.id;
    perform private.customer_push(b.customer_id, 'review', b.id);
  end loop;
  for b in select id, customer_id, business_id, ref, warranty from public.bookings
           where warranty is not null and (warranty->>'applied') is not null and (checkup_sent is null or checkup_sent < current_date - 30) loop
    for n in 1..20 loop
      if ((b.warranty->>'applied')::date + make_interval(months => 6*n))::date = current_date then
        update public.bookings set checkup_sent = current_date where id = b.id;
        perform private.customer_push(b.customer_id, 'checkup', b.id);
        insert into public.notifications (business_id, kind, text, booking_id)
        values (b.business_id, 'checkup', format('Coating check-up due — %s (%s, %s)', (select first_name || ' ' || last_name from public.customers where id = b.customer_id), b.warranty->>'reg', b.warranty->>'product'), b.id);
      end if;
    end loop;
  end loop;
end $$;
select cron.unschedule('valetiq-followups') where exists (select 1 from cron.job where jobname = 'valetiq-followups');
select cron.schedule('valetiq-followups', '*/15 * * * *', 'select private.send_followups()');

-- ---------- service offers (e.g. 15% off a Full Valet until a date) ----------
alter table public.services add column if not exists offer_pct numeric(5,2);
alter table public.services add column if not exists offer_label text;
alter table public.services add column if not exists offer_until date;

-- ---------- create_booking: service offers, referral code + reward balance discounts ----------
do $do$
declare d text;
begin
  select pg_get_functiondef('public.create_booking(uuid,jsonb)'::regprocedure) into d;
  if position('v_ref_code' in d) > 0 then return; end if;
  d := replace(d, 'v_price := v_price + coalesce(public.service_price(svc, coalesce((v_veh->>''size'')::smallint, v_size)), 0);',
'v_price := v_price + round(coalesce(public.service_price(svc, coalesce((v_veh->>''size'')::smallint, v_size)), 0)
        * (case when coalesce(svc.offer_pct, 0) > 0 and (svc.offer_until is null or svc.offer_until >= v_date) then 1 - svc.offer_pct / 100 else 1 end), 2);');
  d := replace(d, '  v_need     integer; v_take integer; v_first_sub uuid;',
'  v_need     integer; v_take integer; v_first_sub uuid;
  v_ref_code text := upper(nullif(trim(p->>''ref_code''), ''''));
  v_referrer uuid; v_disc numeric := 0; v_bal numeric := 0; v_used_bal numeric := 0; v_reward numeric;');
  d := replace(d, '  if v_pay = ''credit'' then
    if not v_admin and not exists',
'  if v_pay <> ''credit'' and not v_admin then
    v_reward := coalesce((biz.settings->>''referralReward'')::numeric, 5);
    if v_ref_code is not null then
      select id into v_referrer from public.customers where business_id = p_business and upper(referral_code) = v_ref_code and id <> cust_id;
      if v_referrer is not null and (select referred_by from public.customers where id = cust_id) is null
         and not exists (select 1 from public.bookings b where b.customer_id = cust_id and b.status <> ''Cancelled'') then
        update public.customers set referred_by = v_referrer where id = cust_id;
        v_disc := v_reward;
      end if;
    end if;
    select coalesce(reward_balance, 0) into v_bal from public.customers where id = cust_id;
    if v_bal > 0 then v_used_bal := least(v_bal, greatest(v_total - v_disc, 0)); v_disc := v_disc + v_used_bal; end if;
    v_disc := least(v_disc, v_total);
    if v_disc > 0 then
      v_total := v_total - v_disc;
      v_dep := round(v_total * coalesce(svc.deposit_pct, (biz.settings->>''depositPct'')::numeric, 20) / 100, 2);
    end if;
  end if;

  if v_pay = ''credit'' then
    if not v_admin and not exists');
  d := replace(d, 'credit, subscription_id, qty, cars, upgrade_id, upgrade_name)', 'credit, subscription_id, qty, cars, upgrade_id, upgrade_name, discount, discount_code)');
  d := replace(d, 'v_pay = ''credit'', null, v_qty, v_vout, v_upg.id, v_upg.name)', 'v_pay = ''credit'', null, v_qty, v_vout, v_upg.id, v_upg.name, v_disc, case when v_disc > 0 then coalesce(case when v_referrer is not null then v_ref_code end, ''REWARD'') end)');
  d := replace(d, '  if v_pay = ''credit'' then
    v_need := v_qty;',
'  if v_used_bal > 0 then
    update public.customers set reward_balance = reward_balance - v_used_bal where id = cust_id;
    insert into public.reward_ledger (business_id, customer_id, amount, note, booking_id) values (p_business, cust_id, -v_used_bal, ''Used on '' || v_ref, v_id);
  end if;

  if v_pay = ''credit'' then
    v_need := v_qty;');
  d := replace(d, '''callout'', v_callout,', '''callout'', v_callout, ''discount'', v_disc,');
  if position('svc.offer_pct' in d) = 0 or position('v_used_bal > 0 then' in d) = 0 or position('discount_code)' in d) = 0 or position('''discount'', v_disc' in d) = 0 then
    raise exception 'create_booking patch did not apply cleanly';
  end if;
  execute d;
end $do$;
