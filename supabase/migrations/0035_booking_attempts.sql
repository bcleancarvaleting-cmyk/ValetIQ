-- Abandoned bookings: the website saves how far someone got (and the contact details they typed)
-- so the owner can follow up. Converted attempts are linked to the booking that was made.
create table if not exists public.booking_attempts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  session text not null,
  first_name text not null default '',
  last_name text not null default '',
  mobile text not null default '',
  email text not null default '',
  postcode text not null default '',
  service_id uuid,
  service_name text not null default '',
  date date,
  start_time text,
  total numeric,
  step int not null default 1,
  source text not null default '',
  booking_id uuid references public.bookings(id) on delete set null,
  status text not null default 'open',   -- open | contacted | dismissed | booked
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, session)
);
alter table public.booking_attempts enable row level security;
drop policy if exists booking_attempts_member on public.booking_attempts;
create policy booking_attempts_member on public.booking_attempts for all using (public.is_member(business_id)) with check (public.is_member(business_id));
grant select, update, delete on public.booking_attempts to authenticated;

create or replace function public.track_booking_attempt(p_business uuid, p_session text, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if coalesce(trim(p_session), '') = '' or length(p_session) > 80 then return; end if;
  select count(*) into n from public.booking_attempts where business_id = p_business and created_at > now() - interval '1 hour';
  if n > 300 then return; end if;
  insert into public.booking_attempts as a (business_id, session, first_name, last_name, mobile, email, postcode, service_id, service_name, date, start_time, total, step, source, booking_id, status)
  values (p_business, left(p_session, 80), left(coalesce(p->>'first', ''), 80), left(coalesce(p->>'last', ''), 80), left(coalesce(p->>'mobile', ''), 30),
          left(coalesce(p->>'email', ''), 160), upper(left(coalesce(p->>'postcode', ''), 10)), nullif(p->>'service_id', '')::uuid, left(coalesce(p->>'service', ''), 120),
          nullif(p->>'date', '')::date, left(nullif(p->>'time', ''), 8), nullif(p->>'total', '')::numeric, coalesce((p->>'step')::int, 1), left(coalesce(p->>'source', ''), 60),
          nullif(p->>'booking_id', '')::uuid, case when nullif(p->>'booking_id', '') is not null then 'booked' else 'open' end)
  on conflict (business_id, session) do update set
    first_name = coalesce(nullif(excluded.first_name, ''), a.first_name), last_name = coalesce(nullif(excluded.last_name, ''), a.last_name),
    mobile = coalesce(nullif(excluded.mobile, ''), a.mobile), email = coalesce(nullif(excluded.email, ''), a.email), postcode = coalesce(nullif(excluded.postcode, ''), a.postcode),
    service_id = coalesce(excluded.service_id, a.service_id), service_name = coalesce(nullif(excluded.service_name, ''), a.service_name),
    date = coalesce(excluded.date, a.date), start_time = coalesce(excluded.start_time, a.start_time), total = coalesce(excluded.total, a.total),
    step = greatest(a.step, excluded.step), source = coalesce(nullif(a.source, ''), excluded.source),
    booking_id = coalesce(excluded.booking_id, a.booking_id),
    status = case when excluded.booking_id is not null then 'booked' else a.status end, updated_at = now();
end $$;
grant execute on function public.track_booking_attempt(uuid, text, jsonb) to anon, authenticated;

-- a booking made by the same mobile number afterwards counts as converted
create or replace function private.attempt_converted() returns trigger
language plpgsql security definer set search_path = public, private as $$
declare m text;
begin
  select regexp_replace(coalesce(mobile, ''), '\D', '', 'g') into m from public.customers where id = new.customer_id;
  if coalesce(m, '') <> '' then
    update public.booking_attempts set status = 'booked', booking_id = coalesce(booking_id, new.id), updated_at = now()
     where business_id = new.business_id and status in ('open', 'contacted') and created_at > now() - interval '30 days'
       and right(regexp_replace(mobile, '\D', '', 'g'), 10) = right(m, 10) and length(m) >= 10;
  end if;
  return new;
end $$;
drop trigger if exists bookings_attempt_converted on public.bookings;
create trigger bookings_attempt_converted after insert on public.bookings for each row execute function private.attempt_converted();
