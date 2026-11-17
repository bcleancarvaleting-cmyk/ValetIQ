create or replace function private.book_regulars(p_business uuid) returns void
language plpgsql security definer set search_path = public, private as $$
declare r record; c public.customers; res jsonb; v_cr int; q int;
begin
  for r in select * from public.regular_slots where active and (p_business is null or business_id = p_business) and next_date <= current_date + 28 for update loop
    select * into c from public.customers where id = r.customer_id;
    while r.next_date <= current_date + 28 loop
      if r.next_date >= current_date then
        q := greatest(jsonb_array_length(r.cars), 1);
        select coalesce(sum(s.credits),0) into v_cr from public.plan_subscriptions s
         where s.customer_id = c.id and s.status = 'active' and s.end_date >= r.next_date
           and (cardinality(s.eligible) = 0 or r.service_id = any(s.eligible));
        begin
          res := public.create_booking(r.business_id, jsonb_build_object(
            'service_id', r.service_id, 'date', r.next_date, 'start_time', r.start_time,
            'first_name', c.first_name, 'last_name', c.last_name, 'email', c.email, 'mobile', c.mobile,
            'address', trim(coalesce(c.house,'') || ' ' || coalesce(c.address,'')), 'postcode', c.postcode,
            'vehicles', case when jsonb_array_length(r.cars) > 0 then r.cars else null end,
            'pay', case when v_cr >= q then 'credit' else 'deposit' end,
            'notes', 'Regular slot — every ' || r.every_weeks || ' weeks'));
        exception when others then
          insert into public.notifications (business_id, kind, text)
          values (r.business_id, 'regularClash', format('Couldn''t book %s %s''s regular slot on %s at %s — %s',
                  c.first_name, c.last_name, to_char(r.next_date,'Dy DD Mon'), to_char(r.start_time,'HH24:MI'), sqlerrm));
        end;
      end if;
      r.next_date := r.next_date + r.every_weeks * 7;
    end loop;
    update public.regular_slots set next_date = r.next_date where id = r.id;
  end loop;
end $$;
create or replace function private.book_regulars() returns void language sql security definer set search_path = public, private as $$ select private.book_regulars(null::uuid) $$;
create or replace function public.book_regulars_now(p_business uuid) returns void
language plpgsql security definer set search_path = public, private as $$
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  perform private.book_regulars(p_business);
end $$;
grant execute on function public.book_regulars_now(uuid) to authenticated;
