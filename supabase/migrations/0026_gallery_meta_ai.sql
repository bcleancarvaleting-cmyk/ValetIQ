-- Gallery: date + location for each before/after; optional AI key for social post captions
alter table public.gallery_items add column if not exists done_on date;
alter table public.gallery_items add column if not exists location text not null default '';
update public.gallery_items g set done_on = b.date from public.bookings b where b.id = g.booking_id and g.done_on is null;

alter table private.business_secrets add column if not exists ai_key text;
create or replace function public.save_ai_key(p_business uuid, p_key text) returns void
language plpgsql security definer set search_path = public, private as $$
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  insert into private.business_secrets (business_id, ai_key) values (p_business, nullif(p_key,''))
  on conflict (business_id) do update set ai_key = nullif(p_key,''), updated_at = now();
end $$;
create or replace function public.ai_status(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = public, private as $$
declare k text;
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  select ai_key into k from private.business_secrets where business_id = p_business;
  return jsonb_build_object('connected', k is not null, 'key', case when k is not null then left(k, 7) || '…' || right(k, 4) end);
end $$;
create or replace function public.get_business_ai(p_business uuid) returns text
language sql stable security definer set search_path = public, private as $$
  select ai_key from private.business_secrets where business_id = p_business;
$$;
revoke execute on function public.get_business_ai(uuid) from public, anon, authenticated;
grant execute on function public.get_business_ai(uuid) to service_role;
grant execute on function public.save_ai_key(uuid, text) to authenticated;
grant execute on function public.ai_status(uuid) to authenticated;
