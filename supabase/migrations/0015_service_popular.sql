-- 'Most popular' badge on a service
alter table public.services add column if not exists popular boolean not null default false;
