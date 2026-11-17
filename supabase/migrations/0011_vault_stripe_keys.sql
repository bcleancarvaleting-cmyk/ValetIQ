-- Let edge functions read the Stripe keys from Supabase Vault (Settings → Vault), so keys can be added from a phone
create or replace function public.get_stripe_config() returns jsonb
language sql stable security definer set search_path = public, vault as $$
  select coalesce(jsonb_object_agg(name, decrypted_secret), '{}'::jsonb)
  from vault.decrypted_secrets where name in ('STRIPE_SECRET_KEY','STRIPE_WEBHOOK_SECRET');
$$;
revoke execute on function public.get_stripe_config() from public, anon, authenticated;
grant execute on function public.get_stripe_config() to service_role;
