-- Admin alerts (registration / booking / payment) + web push to the business owner's phone
create extension if not exists pg_net;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.app_secrets (k text primary key, v text not null);
-- keys inserted separately (not stored in git)

create or replace function public.get_push_config() returns jsonb
language sql stable security definer set search_path = public, private as $$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from private.app_secrets where k in ('vapid_public','vapid_private','push_hook');
$$;
revoke execute on function public.get_push_config() from public, anon, authenticated;
grant execute on function public.get_push_config() to service_role;

create table if not exists public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users on delete cascade,
  business_id uuid references public.businesses on delete cascade,
  endpoint    text unique not null,
  p256dh      text not null,
  auth        text not null,
  ua          text not null default '',
  created_at  timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
create policy "own subscriptions" on public.push_subscriptions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and (business_id is null or public.is_member(business_id)));
grant select, insert, update, delete on public.push_subscriptions to authenticated;

-- New registration → admin notification
create or replace function public.on_customer_registered() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is not null and (tg_op = 'INSERT' or old.user_id is null) then
    insert into public.notifications (business_id, kind, text)
    values (new.business_id, 'registration', format('New registration — %s %s', new.first_name, new.last_name));
  end if;
  return new;
end $$;
drop trigger if exists customer_registered on public.customers;
create trigger customer_registered after insert or update of user_id on public.customers
  for each row execute function public.on_customer_registered();

-- Every new notification → push to the owner's phone (the edge function checks the on/off settings)
create or replace function public.dispatch_push() returns trigger
language plpgsql security definer set search_path = public, private as $$
declare hook text;
begin
  select v into hook from private.app_secrets where k = 'push_hook';
  if hook is not null then
    begin
    perform net.http_post(
      url := 'https://tigznsqtesgofvoflmem.supabase.co/functions/v1/notify-push',
      body := jsonb_build_object('id', new.id),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', hook));
    exception when others then null;  -- never block a booking/payment because a push couldn't be queued
    end;
  end if;
  return new;
end $$;
drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push after insert on public.notifications
  for each row execute function public.dispatch_push();

update public.businesses set settings = settings || jsonb_build_object('adminAlerts', jsonb_build_object(
  'registration', jsonb_build_object('inapp', true, 'push', true, 'email', false),
  'newBooking',   jsonb_build_object('inapp', true, 'push', true, 'email', false),
  'newPayment',   jsonb_build_object('inapp', true, 'push', true, 'email', false)
)) where not (settings ? 'adminAlerts');
