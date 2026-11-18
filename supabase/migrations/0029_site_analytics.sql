-- Website visit tracking (no cookies, no personal data): day, source, page, anonymous visitor id
create table if not exists public.page_views (
  id          bigserial primary key,
  business_id uuid not null references public.businesses on delete cascade,
  day         date not null default (now() at time zone 'Europe/London')::date,
  source      text not null default 'Direct',
  path        text not null default '/',
  visitor     text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists page_views_biz_day on public.page_views (business_id, day);
alter table public.page_views enable row level security;
drop policy if exists "members read views" on public.page_views;
create policy "members read views" on public.page_views for select using (public.is_member(business_id));

create or replace function public.track_view(p_business uuid, p_source text, p_path text, p_visitor text) returns void
language plpgsql security definer set search_path = public as $$
declare src text := left(coalesce(nullif(trim(p_source), ''), 'Direct'), 40);
begin
  if not exists (select 1 from public.businesses where id = p_business) then return; end if;
  -- one count per visitor per page per 30 minutes (stops refreshes inflating numbers)
  if exists (select 1 from public.page_views where business_id = p_business and visitor = left(coalesce(p_visitor,''),40)
             and path = left(coalesce(p_path,'/'),120) and created_at > now() - interval '30 minutes' and coalesce(p_visitor,'') <> '') then return; end if;
  insert into public.page_views (business_id, source, path, visitor) values (p_business, src, left(coalesce(p_path,'/'),120), left(coalesce(p_visitor,''),40));
end $$;
grant execute on function public.track_view(uuid, text, text, text) to anon, authenticated;

create or replace function public.site_stats(p_business uuid, p_days int default 14) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := (now() at time zone 'Europe/London')::date;
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  return jsonb_build_object(
    'days', (select coalesce(jsonb_agg(jsonb_build_object('day', d::date, 'views', coalesce(v.views,0), 'visitors', coalesce(v.visitors,0)) order by d), '[]')
             from generate_series(today - (p_days - 1), today, interval '1 day') d
             left join (select day, count(*) views, count(distinct nullif(visitor,'')) visitors from public.page_views where business_id = p_business and day > today - p_days group by day) v on v.day = d::date),
    'sources_today', (select coalesce(jsonb_agg(jsonb_build_object('source', source, 'n', n) order by n desc), '[]') from (select source, count(distinct coalesce(nullif(visitor,''), id::text)) n from public.page_views where business_id = p_business and day = today group by source) s),
    'sources_range', (select coalesce(jsonb_agg(jsonb_build_object('source', source, 'n', n) order by n desc), '[]') from (select source, count(distinct coalesce(nullif(visitor,''), id::text)) n from public.page_views where business_id = p_business and day > today - p_days group by source) s)
  );
end $$;
grant execute on function public.site_stats(uuid, int) to authenticated;
