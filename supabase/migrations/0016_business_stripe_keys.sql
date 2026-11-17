-- Per-business Stripe keys, entered in the admin app (never readable from the browser)
create schema if not exists private;
create table if not exists private.business_secrets (
  business_id           uuid primary key references public.businesses on delete cascade,
  stripe_secret         text,
  stripe_webhook_secret text,
  stripe_webhook_id     text,
  stripe_mode           text,
  stripe_account        text,
  updated_at            timestamptz not null default now()
);
revoke all on private.business_secrets from public, anon, authenticated;

-- edge functions only
create or replace function public.get_business_stripe(p_business uuid) returns jsonb
language sql stable security definer set search_path = public, private as $$
  select coalesce((select jsonb_build_object('secret', stripe_secret, 'whsec', stripe_webhook_secret, 'webhook_id', stripe_webhook_id, 'mode', stripe_mode)
                     from private.business_secrets where business_id = p_business and stripe_secret is not null), '{}'::jsonb);
$$;
create or replace function public.save_business_stripe(p_business uuid, p_secret text, p_whsec text, p_whid text, p_mode text, p_account text) returns void
language sql security definer set search_path = public, private as $$
  insert into private.business_secrets (business_id, stripe_secret, stripe_webhook_secret, stripe_webhook_id, stripe_mode, stripe_account, updated_at)
  values (p_business, p_secret, p_whsec, p_whid, p_mode, p_account, now())
  on conflict (business_id) do update set stripe_secret = excluded.stripe_secret, stripe_webhook_secret = excluded.stripe_webhook_secret,
    stripe_webhook_id = excluded.stripe_webhook_id, stripe_mode = excluded.stripe_mode, stripe_account = excluded.stripe_account, updated_at = now();
$$;
revoke execute on function public.get_business_stripe(uuid) from public, anon, authenticated;
revoke execute on function public.save_business_stripe(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.get_business_stripe(uuid) to service_role;
grant execute on function public.save_business_stripe(uuid, text, text, text, text, text) to service_role;

-- admin app: see status only (masked), or disconnect
create or replace function public.stripe_status(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = public, private as $$
declare r private.business_secrets;
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  select * into r from private.business_secrets where business_id = p_business;
  if r.stripe_secret is null then return jsonb_build_object('connected', false); end if;
  return jsonb_build_object('connected', true, 'mode', r.stripe_mode, 'account', r.stripe_account,
    'key', left(r.stripe_secret, 8) || '…' || right(r.stripe_secret, 4), 'webhook', r.stripe_webhook_id is not null, 'updated_at', r.updated_at);
end $$;
create or replace function public.disconnect_stripe(p_business uuid) returns void
language plpgsql security definer set search_path = public, private as $$
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  update private.business_secrets set stripe_secret = null, stripe_webhook_secret = null, stripe_webhook_id = null, stripe_mode = null, stripe_account = null, updated_at = now()
   where business_id = p_business;
end $$;
grant execute on function public.stripe_status(uuid) to authenticated;
grant execute on function public.disconnect_stripe(uuid) to authenticated;
