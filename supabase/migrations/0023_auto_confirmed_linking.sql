-- Accounts created instantly (no email confirmation) only take over an existing customer record
-- when the mobile number matches too, so nobody can see someone else's bookings just by knowing their email.
create or replace function public.link_my_customer_records(p_mobile text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer := 0; m integer := 0; auto boolean;
begin
  if auth.uid() is null then return 0; end if;
  select coalesce((raw_app_meta_data->>'auto_confirmed')::boolean, false) into auto from auth.users where id = auth.uid();
  update public.customers c set user_id = auth.uid()
   where c.user_id is null and lower(c.email) = lower(auth.email())
     and (not auto or coalesce(c.mobile_norm, '') = '' or c.mobile_norm = public.norm_mobile(p_mobile));
  get diagnostics n = row_count;
  if public.norm_mobile(p_mobile) <> '' then
    update public.customers c set user_id = auth.uid(), email = lower(auth.email())
     where c.user_id is null and c.mobile_norm = public.norm_mobile(p_mobile) and c.email like '%@no-email.invalid'
       and not exists (select 1 from public.customers x where x.business_id = c.business_id and lower(x.email) = lower(auth.email()));
    get diagnostics m = row_count;
  end if;
  return n + m;
end $$;
do $do$
declare d text;
begin
  select pg_get_functiondef('public.register_customer(uuid,text,text,text)'::regprocedure) into d;
  d := replace(d, 'This email is already linked to another account. Please contact us.', 'We already have your details under a different mobile number — please message us and we will link your account.');
  execute d;
end $do$;
