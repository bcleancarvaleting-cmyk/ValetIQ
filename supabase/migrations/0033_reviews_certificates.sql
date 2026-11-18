-- Live Google + Facebook reviews (synced daily) and ceramic coating certificates

-- ---------- Reviews pulled from Google / Facebook ----------
create table if not exists public.ext_reviews (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  source text not null check (source in ('google','facebook')),
  ext_id text not null,
  author text not null default '',
  avatar text,
  rating int not null default 5 check (rating between 1 and 5),
  text text not null default '',
  posted_at timestamptz,
  url text,
  hidden boolean not null default false,
  synced_at timestamptz not null default now(),
  unique (business_id, source, ext_id)
);
alter table public.ext_reviews enable row level security;
drop policy if exists ext_reviews_public on public.ext_reviews;
create policy ext_reviews_public on public.ext_reviews for select using (not hidden or public.is_member(business_id));
drop policy if exists ext_reviews_member on public.ext_reviews;
create policy ext_reviews_member on public.ext_reviews for update using (public.is_member(business_id)) with check (public.is_member(business_id));
grant select on public.ext_reviews to anon, authenticated;
grant update (hidden) on public.ext_reviews to authenticated;

alter table private.business_secrets add column if not exists google_key text;
alter table private.business_secrets add column if not exists fb_token text;

-- null = leave unchanged, '' = remove
create or replace function public.save_review_keys(p_business uuid, p_google_key text, p_fb_token text) returns void
language plpgsql security definer set search_path = public, private as $$
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  insert into private.business_secrets (business_id) values (p_business) on conflict (business_id) do nothing;
  update private.business_secrets set
    google_key = case when p_google_key is null then google_key else nullif(trim(p_google_key),'') end,
    fb_token  = case when p_fb_token  is null then fb_token  else nullif(trim(p_fb_token),'') end,
    updated_at = now()
  where business_id = p_business;
end $$;

create or replace function public.review_keys_status(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = public, private as $$
declare g text; f text;
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  select google_key, fb_token into g, f from private.business_secrets where business_id = p_business;
  return jsonb_build_object('google', g is not null, 'facebook', f is not null);
end $$;

create or replace function public.get_review_keys(p_business uuid) returns jsonb
language sql stable security definer set search_path = public, private as $$
  select jsonb_build_object('google_key', google_key, 'fb_token', fb_token) from private.business_secrets where business_id = p_business;
$$;
revoke execute on function public.get_review_keys(uuid) from public, anon, authenticated;
grant execute on function public.get_review_keys(uuid) to service_role;
grant execute on function public.save_review_keys(uuid, text, text) to authenticated;
grant execute on function public.review_keys_status(uuid) to authenticated;

-- daily sync for every business with a key
create or replace function private.sync_all_reviews() returns void
language plpgsql security definer set search_path = public, private as $$
declare hook text; r record;
begin
  select v into hook from private.app_secrets where k = 'push_hook';
  for r in select business_id from private.business_secrets where google_key is not null or fb_token is not null loop
    perform net.http_post(url := 'https://tigznsqtesgofvoflmem.supabase.co/functions/v1/reviews-sync',
      body := jsonb_build_object('business_id', r.business_id),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', hook));
  end loop;
end $$;
select cron.unschedule('valetiq-reviews') where exists (select 1 from cron.job where jobname = 'valetiq-reviews');
select cron.schedule('valetiq-reviews', '17 4 * * *', 'select private.sync_all_reviews()');

-- ---------- Ceramic coating certificates ----------
create table if not exists public.certificates (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  code text not null unique,
  customer_id uuid references public.customers(id) on delete set null,
  booking_id uuid references public.bookings(id) on delete set null,
  customer_name text not null default '',
  reg text not null default '',
  vehicle text not null default '',
  colour text not null default '',
  product text not null default '',
  layers int not null default 1,
  warranty_years numeric not null default 1,
  applied_on date not null default current_date,
  expires_on date,
  coverage text not null default '',
  notes text not null default '',
  void boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.certificates enable row level security;
drop policy if exists certificates_member on public.certificates;
create policy certificates_member on public.certificates for all using (public.is_member(business_id)) with check (public.is_member(business_id));
grant select, insert, update, delete on public.certificates to authenticated;

create or replace function public.new_cert_code(p_business uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text; pre text;
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  select coalesce(nullif(settings->>'invoicePrefix',''), 'BC') into pre from public.businesses where id = p_business;
  loop
    c := upper(pre) || '-CERT-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.certificates where code = c);
  end loop;
  return c;
end $$;
grant execute on function public.new_cert_code(uuid) to authenticated;

-- public lookup for the verify page / QR code
create or replace function public.get_certificate(p_code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', c.code, 'customer_name', c.customer_name, 'reg', c.reg, 'vehicle', c.vehicle, 'colour', c.colour,
    'product', c.product, 'layers', c.layers, 'warranty_years', c.warranty_years, 'applied_on', c.applied_on,
    'expires_on', c.expires_on, 'coverage', c.coverage, 'notes', c.notes, 'void', c.void,
    'business', b.name, 'design', coalesce(b.settings->'certDesign', '{}'::jsonb), 'brand', coalesce(b.settings->'brand', '{}'::jsonb),
    'phone', b.settings->>'phone', 'email', b.settings->>'email')
  from public.certificates c join public.businesses b on b.id = c.business_id
  where upper(c.code) = upper(trim(p_code));
$$;
grant execute on function public.get_certificate(text) to anon, authenticated;
