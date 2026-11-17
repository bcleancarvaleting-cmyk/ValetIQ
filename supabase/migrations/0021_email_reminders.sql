-- Reminder emails alongside the push, and no per-booking "payment received" emails for monthly statements
create or replace function private.send_reminders() returns void
language plpgsql security definer set search_path = public, private as $$
declare b record;
begin
  for b in select id, customer_id, business_id from public.bookings
           where status in ('Booked','Confirmed') and reminded_at is null
             and ((date + start_time) at time zone 'Europe/London') between now() + interval '23 hours' and now() + interval '24 hours 5 minutes' loop
    update public.bookings set reminded_at = now() where id = b.id;
    perform private.customer_push(b.customer_id, 'reminder', b.id);
    perform private.queue_email(b.business_id, 'reminder', b.customer_id, b.id);
  end loop;
end $$;
create or replace function public.email_on_payment() returns trigger language plpgsql security definer set search_path = public, private as $$
begin
  if new.customer_id is not null and new.amount > 0 and coalesce(new.method,'') <> 'Monthly statement' then
    perform private.queue_email(new.business_id, 'received', new.customer_id, new.booking_id, new.amount);
  end if;
  return new;
end $$;

-- Custom push message from the admin app ("send everywhere" and the due-a-clean dashboard)
create or replace function public.send_customer_note(p_customer uuid, p_title text, p_text text, p_booking uuid default null, p_kind text default 'custom')
returns boolean language plpgsql security definer set search_path = public, private as $$
declare hook text;
begin
  if not public.is_member((select business_id from public.customers where id = p_customer)) then raise exception 'Not allowed'; end if;
  if not exists (select 1 from public.push_subscriptions where customer_id = p_customer) then return false; end if;
  select v into hook from private.app_secrets where k = 'push_hook';
  perform net.http_post(url := 'https://tigznsqtesgofvoflmem.supabase.co/functions/v1/notify-push',
    body := jsonb_build_object('customer', p_customer, 'msg', p_kind, 'booking', p_booking, 'title', p_title, 'text', p_text),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', hook));
  return true;
end $$;
grant execute on function public.send_customer_note(uuid, text, text, uuid, text) to authenticated;
