-- Sequential invoice numbers (e.g. BC208, BC209 …) carried on from the business's old system
alter table public.businesses add column if not exists invoice_seq integer;
create or replace function public.next_invoice_number(p_business uuid) returns text
language plpgsql security definer set search_path = public as $$
declare n int; pre text;
begin
  update public.businesses set invoice_seq = coalesce(invoice_seq, 0) + 1 where id = p_business
  returning invoice_seq, coalesce(nullif(settings->>'invoicePrefix', ''), 'INV') into n, pre;
  return pre || n;
end $$;
revoke execute on function public.next_invoice_number(uuid) from public, anon, authenticated;
grant execute on function public.next_invoice_number(uuid) to service_role;
create or replace function public.set_invoice_numbering(p_business uuid, p_prefix text, p_next int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_business) then raise exception 'Not allowed'; end if;
  if p_next < 1 then raise exception 'Number must be 1 or more'; end if;
  update public.businesses set invoice_seq = p_next - 1,
    settings = settings || jsonb_build_object('invoicePrefix', upper(regexp_replace(coalesce(p_prefix,''), '[^A-Za-z0-9-]', '', 'g')))
  where id = p_business;
end $$;
grant execute on function public.set_invoice_numbering(uuid, text, int) to authenticated;
