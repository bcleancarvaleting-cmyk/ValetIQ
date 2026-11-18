-- Real gift vouchers: bought online (Stripe) or issued by the business, redeemed when booking online
create table if not exists public.gift_vouchers (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses on delete cascade,
  code        text not null,
  amount      numeric(10,2) not null check (amount > 0),
  balance     numeric(10,2) not null,
  buyer_name  text not null default '',
  buyer_email text not null default '',
  to_name     text not null default '',
  to_email    text not null default '',
  message     text not null default '',
  expires     date,
  status      text not null default 'active' check (status in ('active','cancelled')),
  source      text not null default 'online',
  stripe_id   text unique,
  created_at  timestamptz not null default now()
);
create unique index if not exists gift_vouchers_code on public.gift_vouchers (business_id, upper(code));
alter table public.gift_vouchers enable row level security;
drop policy if exists "members manage vouchers" on public.gift_vouchers;
create policy "members manage vouchers" on public.gift_vouchers for all using (public.is_member(business_id)) with check (public.is_member(business_id));
grant select, insert, update, delete on public.gift_vouchers to authenticated;

create table if not exists public.voucher_uses (
  id          uuid primary key default gen_random_uuid(),
  voucher_id  uuid not null references public.gift_vouchers on delete cascade,
  booking_id  uuid references public.bookings on delete set null,
  amount      numeric(10,2) not null,
  created_at  timestamptz not null default now()
);
alter table public.voucher_uses enable row level security;
drop policy if exists "members read voucher uses" on public.voucher_uses;
create policy "members read voucher uses" on public.voucher_uses for select using (exists (select 1 from public.gift_vouchers v where v.id = voucher_id and public.is_member(v.business_id)));
grant select on public.voucher_uses to authenticated;

create or replace function public.new_voucher_code(p_business uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text; pre text;
begin
  select upper(left(regexp_replace(coalesce(nullif(settings->>'invoicePrefix',''), name), '[^A-Za-z]', '', 'g'), 3)) into pre from public.businesses where id = p_business;
  loop
    c := coalesce(nullif(pre,''), 'GIFT') || '-GIFT-' || upper(substr(md5(gen_random_uuid()::text), 1, 5));
    exit when not exists (select 1 from public.gift_vouchers where business_id = p_business and upper(code) = c);
  end loop;
  return c;
end $$;
grant execute on function public.new_voucher_code(uuid) to authenticated, service_role;

-- public check used by the booking form (shows the balance, nothing else)
create or replace function public.check_voucher(p_business uuid, p_code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('ok', true, 'balance', balance, 'expires', expires)
     from public.gift_vouchers where business_id = p_business and upper(code) = upper(trim(p_code)) and status = 'active' and balance > 0 and (expires is null or expires >= current_date)),
     jsonb_build_object('ok', false));
$$;
grant execute on function public.check_voucher(uuid, text) to anon, authenticated;

-- give the balance back if a booking that used a voucher is cancelled (or an unpaid hold is released)
create or replace function public.voucher_refund_on_cancel() returns trigger language plpgsql security definer set search_path = public as $$
declare u record;
begin
  if new.status = 'Cancelled' and old.status <> 'Cancelled' then
    for u in select * from public.voucher_uses where booking_id = new.id loop
      update public.gift_vouchers set balance = balance + u.amount where id = u.voucher_id;
      delete from public.voucher_uses where id = u.id;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists bookings_voucher_refund on public.bookings;
create trigger bookings_voucher_refund after update of status on public.bookings for each row execute function public.voucher_refund_on_cancel();

do $do$
declare d text;
begin
  select pg_get_functiondef('public.create_booking(uuid,jsonb)'::regprocedure) into d;
  if position('v_gv_use' in d) > 0 then return; end if;
  d := replace(d, '  v_referrer uuid; v_disc numeric := 0; v_bal numeric := 0; v_used_bal numeric := 0; v_reward numeric;',
                  '  v_referrer uuid; v_disc numeric := 0; v_bal numeric := 0; v_used_bal numeric := 0; v_reward numeric;
  v_gv public.gift_vouchers; v_gv_use numeric := 0;');
  d := replace(d, '    v_disc := least(v_disc, v_total);',
                  '    if nullif(trim(p->>''voucher''), '''') is not null then
      select * into v_gv from public.gift_vouchers where business_id = p_business and upper(code) = upper(trim(p->>''voucher''))
         and status = ''active'' and balance > 0 and (expires is null or expires >= current_date) for update;
      if not found then raise exception ''That gift voucher code isn''''t valid or has already been used''; end if;
      v_gv_use := least(v_gv.balance, greatest(v_total - v_disc, 0));
      v_disc := v_disc + v_gv_use;
    end if;
    v_disc := least(v_disc, v_total);');
  d := replace(d, '  if v_used_bal > 0 then
    update public.customers set reward_balance',
                  '  if v_gv_use > 0 then
    update public.gift_vouchers set balance = balance - v_gv_use where id = v_gv.id;
    insert into public.voucher_uses (voucher_id, booking_id, amount) values (v_gv.id, v_id, v_gv_use);
    update public.bookings set discount_code = v_gv.code where id = v_id;
  end if;

  if v_used_bal > 0 then
    update public.customers set reward_balance');
  if (length(d) - length(replace(d, 'v_gv_use', ''))) / length('v_gv_use') < 6 then raise exception 'create_booking voucher patch did not apply cleanly'; end if;
  execute d;
end $do$;
