-- Customer app: registration, install tracking, notification consent, customer push
alter table public.customers add column if not exists notify_ok boolean not null default false;
alter table public.customers add column if not exists notify_consent_at timestamptz;

alter table public.push_subscriptions add column if not exists role text not null default 'admin';
alter table public.push_subscriptions add column if not exists customer_id uuid references public.customers on delete cascade;
drop policy if exists "own subscriptions" on public.push_subscriptions;
create policy "own subscriptions" on public.push_subscriptions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and (
    (role = 'admin' and (business_id is null or public.is_member(business_id)))
    or (role = 'customer' and exists (select 1 from public.customers c where c.id = customer_id and c.user_id = auth.uid() and c.business_id = push_subscriptions.business_id))));

-- Register / sign in: link existing records (email or mobile), otherwise create the customer
create or replace function public.register_customer(p_business uuid, p_first text default null, p_last text default null, p_mobile text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid; meta jsonb;
begin
  if auth.uid() is null then raise exception 'Please sign in'; end if;
  select raw_user_meta_data into meta from auth.users where id = auth.uid();
  p_first  := nullif(trim(coalesce(p_first,  meta->>'first_name', '')), '');
  p_last   := coalesce(nullif(trim(coalesce(p_last, meta->>'last_name', '')), ''), '');
  p_mobile := nullif(trim(coalesce(p_mobile, meta->>'mobile', '')), '');
  perform public.link_my_customer_records(p_mobile);
  select id into cid from public.customers where business_id = p_business and user_id = auth.uid() order by created_at limit 1;
  if cid is null then
    -- an existing record with this email that belongs to someone else's login is not touched
    if exists (select 1 from public.customers where business_id = p_business and lower(email) = lower(auth.email())) then
      raise exception 'This email is already linked to another account. Please contact us.';
    end if;
    insert into public.customers (business_id, user_id, first_name, last_name, email, mobile)
    values (p_business, auth.uid(), coalesce(p_first, split_part(auth.email(), '@', 1)), p_last, lower(auth.email()), coalesce(p_mobile, ''))
    returning id into cid;
  else
    update public.customers set
      mobile = case when mobile = '' and p_mobile is not null then p_mobile else mobile end,
      first_name = case when first_name = '' and p_first is not null then p_first else first_name end
    where id = cid;
  end if;
  return cid;
end $$;
revoke execute on function public.register_customer(uuid, text, text, text) from public, anon;
grant execute on function public.register_customer(uuid, text, text, text) to authenticated;

create or replace function public.record_app_install(p_business uuid, p_platform text)
returns void language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select id into cid from public.customers where business_id = p_business and user_id = auth.uid() limit 1;
  if cid is null then return; end if;
  if not exists (select 1 from public.app_installs where customer_id = cid and platform = left(coalesce(p_platform,''), 40)) then
    insert into public.app_installs (business_id, customer_id, platform) values (p_business, cid, left(coalesce(p_platform,''), 40));
  end if;
end $$;
revoke execute on function public.record_app_install(uuid, text) from public, anon;
grant execute on function public.record_app_install(uuid, text) to authenticated;

create or replace function public.set_notify_consent(p_business uuid, p_ok boolean)
returns void language sql security definer set search_path = public as $$
  update public.customers set notify_ok = p_ok, notify_consent_at = now() where business_id = p_business and user_id = auth.uid();
$$;
revoke execute on function public.set_notify_consent(uuid, boolean) from public, anon;
grant execute on function public.set_notify_consent(uuid, boolean) to authenticated;

-- Customer pushes (booking confirmed / payment received / reminder), sent by the notify-push function
create or replace function private.customer_push(p_customer uuid, p_msg text, p_booking uuid, p_amount numeric default null)
returns void language plpgsql security definer set search_path = public, private as $$
declare hook text;
begin
  select v into hook from private.app_secrets where k = 'push_hook';
  if hook is null or not exists (select 1 from public.push_subscriptions where customer_id = p_customer) then return; end if;
  begin
    perform net.http_post(
      url := 'https://tigznsqtesgofvoflmem.supabase.co/functions/v1/notify-push',
      body := jsonb_build_object('customer', p_customer, 'msg', p_msg, 'booking', p_booking, 'amount', p_amount),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', hook));
  exception when others then null;
  end;
end $$;

create or replace function public.booking_customer_push() returns trigger
language plpgsql security definer set search_path = public, private as $$
begin
  if new.status in ('Booked','Confirmed') and new.date >= current_date
     and (new.repeat_group is null or not exists (select 1 from public.bookings x where x.repeat_group = new.repeat_group and x.date < new.date)) then
    perform private.customer_push(new.customer_id, 'confirmed', new.id);
  end if;
  return new;
end $$;
drop trigger if exists bookings_customer_push on public.bookings;
create trigger bookings_customer_push after insert on public.bookings for each row execute function public.booking_customer_push();

create or replace function public.payment_customer_push() returns trigger
language plpgsql security definer set search_path = public, private as $$
begin
  if new.customer_id is not null and new.amount > 0 then
    perform private.customer_push(new.customer_id, 'received', new.booking_id, new.amount);
  end if;
  return new;
end $$;
drop trigger if exists payments_customer_push on public.payments;
create trigger payments_customer_push after insert on public.payments for each row execute function public.payment_customer_push();

-- Day-before reminders, every evening
create or replace function private.send_reminders() returns void
language plpgsql security definer set search_path = public, private as $$
declare b record;
begin
  for b in select id, customer_id from public.bookings
           where date = (now() at time zone 'Europe/London')::date + 1 and status in ('Booked','Confirmed') loop
    perform private.customer_push(b.customer_id, 'reminder', b.id);
  end loop;
end $$;
create extension if not exists pg_cron;
select cron.unschedule('valetiq-reminders') where exists (select 1 from cron.job where jobname = 'valetiq-reminders');
select cron.schedule('valetiq-reminders', '0 18 * * *', 'select private.send_reminders()');
