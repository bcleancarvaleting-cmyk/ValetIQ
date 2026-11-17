-- Online bookings only reach the diary (and alert the owner) once the deposit is paid.
-- 1) A 0% deposit on a service no longer lets online bookings skip payment: the standard deposit applies online.
-- 2) "New booking" alert is sent when the booking is paid (Pending → Booked), not when the slot is first held.
do $do$
declare d text;
begin
  select pg_get_functiondef('public.create_booking(uuid,jsonb)'::regprocedure) into d;
  if position('nullif(svc.deposit_pct, 0)' in d) > 0 then return; end if;
  d := replace(d, 'coalesce(svc.deposit_pct, (biz.settings->>''depositPct'')::numeric, 20)',
                  'coalesce(case when v_admin then svc.deposit_pct else nullif(svc.deposit_pct, 0) end, nullif((biz.settings->>''depositPct'')::numeric, 0), 20)');
  d := replace(d, '  if not v_admin then
  insert into public.notifications (business_id, kind, text, booking_id)',
                  '  if not v_admin and (select status from public.bookings where id = v_id) <> ''Pending'' then
  insert into public.notifications (business_id, kind, text, booking_id)');
  if position('nullif(svc.deposit_pct, 0)' in d) = 0 or position('<> ''Pending'' then' in d) = 0 then
    raise exception 'create_booking patch did not apply cleanly';
  end if;
  execute d;
end $do$;

create or replace function public.notify_paid_booking() returns trigger
language plpgsql security definer set search_path = public as $$
declare c record;
begin
  if old.status = 'Pending' and new.status in ('Booked','Confirmed') then
    select first_name, last_name into c from public.customers where id = new.customer_id;
    insert into public.notifications (business_id, kind, text, booking_id)
    values (new.business_id, 'newBooking',
            format('New booking (deposit paid) — %s %s, %s on %s at %s', coalesce(c.first_name,''), coalesce(c.last_name,''), new.service_name,
                   to_char(new.date,'Dy DD Mon'), to_char(new.start_time,'HH24:MI')), new.id);
  end if;
  return new;
end $$;
drop trigger if exists bookings_paid_notify on public.bookings;
create trigger bookings_paid_notify after update of status on public.bookings for each row execute function public.notify_paid_booking();
