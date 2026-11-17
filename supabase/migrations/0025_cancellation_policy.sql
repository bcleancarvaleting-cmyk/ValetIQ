-- Cancellation policy: online customers must agree before booking; the agreement is saved on the booking.
alter table public.bookings add column if not exists policy_accepted_at timestamptz;
alter table public.bookings add column if not exists policy_hours integer;
do $do$
declare d text;
begin
  select pg_get_functiondef('public.create_booking(uuid,jsonb)'::regprocedure) into d;
  if position('policy_ok' in d) > 0 then return; end if;
  d := replace(d, '  if v_date < current_date and not v_admin then raise exception ''That date has passed''; end if;',
                  '  if v_date < current_date and not v_admin then raise exception ''That date has passed''; end if;
  if not v_admin and coalesce((biz.settings->>''cancelRequired'')::boolean, true) and not coalesce((p->>''policy_ok'')::boolean, false) then
    raise exception ''Please tick to agree to the cancellation policy'';
  end if;');
  d := replace(d, '  if v_used_bal > 0 then
    update public.customers set reward_balance',
                  '  if coalesce((p->>''policy_ok'')::boolean, false) then
    update public.bookings set policy_accepted_at = now(), policy_hours = coalesce((biz.settings->>''cancelHours'')::int, 48) where id = v_id;
  end if;

  if v_used_bal > 0 then
    update public.customers set reward_balance');
  if (length(d) - length(replace(d, 'policy_ok', ''))) / length('policy_ok') <> 2 then
    raise exception 'create_booking patch did not apply cleanly';
  end if;
  execute d;
end $do$;
