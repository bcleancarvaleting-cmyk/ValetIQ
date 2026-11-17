-- Pre-paid washes (credits) added by the business, used when booking (admin or signed-in customer), refunded on cancel
alter table public.plan_subscriptions add column if not exists eligible uuid[] not null default '{}';  -- empty = any service
alter table public.plan_subscriptions add column if not exists note text not null default '';

create or replace function public.refund_credit_on_cancel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'Cancelled' and old.status <> 'Cancelled' and new.credit and new.subscription_id is not null then
    update public.plan_subscriptions set credits = credits + 1 where id = new.subscription_id;
    insert into public.credit_ledger (business_id, subscription_id, delta, note, booking_id)
    values (new.business_id, new.subscription_id, 1, 'Returned — ' || new.ref || ' cancelled', new.id);
  end if;
  return new;
end $$;
drop trigger if exists bookings_refund_credit on public.bookings;
create trigger bookings_refund_credit after update of status on public.bookings
  for each row execute function public.refund_credit_on_cancel();

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
  v_sub      public.plan_subscriptions;
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
  v_dep := round(v_total * coalesce(svc.deposit_pct, (biz.settings->>'depositPct')::numeric, 20) / 100, 2);

  -- customer (match on email) & vehicle (match on reg)
  select id into cust_id from public.customers where business_id = p_business and lower(email) = v_email;
  -- not found by email (or no real email given): match on mobile number, whatever format (07…, +44 7…, spaces)
  if cust_id is null and public.norm_mobile(p->>'mobile') <> '' then
    select id into cust_id from public.customers
     where business_id = p_business and mobile_norm = public.norm_mobile(p->>'mobile')
     order by (email like '%@no-email.invalid') desc, created_at limit 1;
    if cust_id is not null and v_email not like '%@no-email.invalid' then
      update public.customers set email = v_email where id = cust_id and email like '%@no-email.invalid'
        and not exists (select 1 from public.customers x where x.business_id = p_business and lower(x.email) = v_email);
    end if;
  end if;
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

  -- services like maintenance valets are only for customers the business has approved
  if svc.requires_approval and not v_admin
     and not coalesce((select maintenance_ok from public.customers where id = cust_id), false) then
    raise exception '% is for our existing customers who have had a deep clean, enhancement or paint correction with us — please book one of those first, or message us', svc.name;
  end if;

  -- pay with a pre-paid wash (credit): the customer must be signed in to their own account (or the business books it)
  if v_pay = 'credit' then
    if not v_admin and not exists (select 1 from public.customers where id = cust_id and user_id = auth.uid() and auth.uid() is not null) then
      raise exception 'Please sign in to your account to use your pre-paid washes';
    end if;
    select * into v_sub from public.plan_subscriptions s
     where s.customer_id = cust_id and s.status = 'active' and s.credits > 0 and s.end_date >= v_date
       and (cardinality(s.eligible) = 0 or svc.id = any(s.eligible))
     order by s.end_date limit 1 for update;
    if not found then raise exception 'No pre-paid washes left for this service — please pay as normal'; end if;
    v_price := 0; v_callout := 0; v_total := 0; v_dep := 0;
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
     duration_mins, days, price, callout, total, status, source, notes, postcode, address, credit, subscription_id)
  values (p_business, v_ref, cust_id, veh_id, svc.id, svc.name, v_size, v_date, v_start, v_mins, svc.days,
     v_price, v_callout, v_total,
     case when v_pay in ('deposit','full') and v_dep > 0 and coalesce((biz.settings->>'paymentsLive')::boolean, false) and not v_admin then 'Pending'::public.booking_status else 'Booked'::public.booking_status end,
     case when v_admin then 'manual' else 'website' end, coalesce(p->>'notes',''), upper(coalesce(p->>'postcode','')), trim(coalesce(p->>'house','') || ' ' || coalesce(p->>'address','')),
     v_pay = 'credit', case when v_pay = 'credit' then v_sub.id end)
  returning id into v_id;

  if v_pay = 'credit' then
    update public.plan_subscriptions set credits = credits - 1 where id = v_sub.id;
    insert into public.credit_ledger (business_id, subscription_id, delta, note, booking_id)
    values (p_business, v_sub.id, -1, 'Used for ' || v_ref, v_id);
  end if;

  if not v_admin then
  insert into public.notifications (business_id, kind, text, booking_id)
  values (p_business, 'newBooking',
          format('New booking — %s %s, %s on %s at %s', trim(p->>'first_name'), coalesce(trim(p->>'last_name'),''), svc.name, to_char(v_date,'Dy DD Mon'), to_char(v_start,'HH24:MI')),
          v_id);
  end if;

  return jsonb_build_object('id', v_id, 'ref', v_ref, 'total', v_total, 'deposit', v_dep, 'callout', v_callout, 'credit', v_pay = 'credit', 'credits_left', case when v_pay = 'credit' then v_sub.credits - 1 end,
                            'status', (select status from public.bookings where id = v_id));
end $$;
grant execute on function public.create_booking(uuid, jsonb) to anon, authenticated;
