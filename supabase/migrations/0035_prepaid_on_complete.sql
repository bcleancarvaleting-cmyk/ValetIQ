-- Pre-paid washes: completing a £0 booking for a customer with pre-paid washes uses one wash
-- (if one wasn't already used when it was booked) and links the booking to the plan, so both the
-- admin app and the customer app can show a green tick for every wash done.
create or replace function private.prepaid_on_complete() returns trigger
language plpgsql security definer set search_path = public, private as $$
declare s record; n int;
begin
  if new.status = 'Completed' and old.status is distinct from 'Completed' and new.customer_id is not null
     and not exists (select 1 from public.credit_ledger where booking_id = new.id and delta < 0)
     and coalesce(new.total, 0) = 0 then
    n := greatest(coalesce(new.qty, 1), 1);
    select ps.* into s from public.plan_subscriptions ps
      where ps.customer_id = new.customer_id and ps.status = 'active' and ps.credits >= 1
        and (coalesce(array_length(ps.eligible, 1), 0) = 0 or new.service_id::text = any (ps.eligible::text[]))
      order by ps.end_date nulls last limit 1 for update;
    if found then
      n := least(n, s.credits);
      update public.plan_subscriptions set credits = credits - n where id = s.id;
      insert into public.credit_ledger (business_id, subscription_id, delta, note, booking_id)
        values (new.business_id, s.id, -n, 'Used — ' || coalesce(new.ref, '') || ' completed', new.id);
      update public.bookings set credit = true, subscription_id = s.id where id = new.id;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists bookings_prepaid_complete on public.bookings;
create trigger bookings_prepaid_complete after update of status on public.bookings
  for each row execute function private.prepaid_on_complete();
