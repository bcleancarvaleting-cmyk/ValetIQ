revoke execute on function public.link_my_customer_records() from public, anon;
grant execute on function public.link_my_customer_records() to authenticated;
revoke execute on function public.busy_times(uuid, date, date) from public;
grant execute on function public.busy_times(uuid, date, date) to anon, authenticated;
