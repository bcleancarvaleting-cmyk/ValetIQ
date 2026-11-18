-- Invoice tracking: sent / opened / viewed, reminders, due dates
alter table public.payment_links add column if not exists number text;
alter table public.payment_links add column if not exists pdf text;
alter table public.payment_links add column if not exists due_date date;
alter table public.payment_links add column if not exists sent_at timestamptz;
alter table public.payment_links add column if not exists opened_at timestamptz;
alter table public.payment_links add column if not exists viewed_at timestamptz;
alter table public.payment_links add column if not exists view_count integer not null default 0;
alter table public.payment_links add column if not exists reminder_count integer not null default 0;
alter table public.payment_links add column if not exists last_reminder_at timestamptz;
