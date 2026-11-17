-- Take deposits online (Stripe connected) + release slots held by unpaid online bookings after 45 minutes
update public.businesses set settings = settings || '{"paymentsLive": true}'::jsonb where slug = 'bclean';

create or replace function private.release_unpaid_bookings() returns void
language sql security definer set search_path = public as $$
  update public.bookings b set status = 'Cancelled', notes = trim(b.notes || E'\n[Auto-cancelled: deposit not paid]')
   where b.status = 'Pending' and b.source = 'website' and b.created_at < now() - interval '45 minutes'
     and not exists (select 1 from public.payments p where p.booking_id = b.id);
$$;
create extension if not exists pg_cron;
select cron.unschedule('valetiq-release-unpaid') where exists (select 1 from cron.job where jobname = 'valetiq-release-unpaid');
select cron.schedule('valetiq-release-unpaid', '*/10 * * * *', 'select private.release_unpaid_bookings()');
