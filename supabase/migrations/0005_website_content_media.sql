-- Website content managed from admin + image storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 8388608, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "members upload media" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "members update media" on storage.objects for update to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "members delete media" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "members list media" on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));

update public.businesses set settings = settings || '{"terms": "Bookings are confirmed once the deposit is received. We need access to water and electricity, or we will bring our own (please let us know). Vehicles must be accessible at the booked time. Prices may vary on inspection where condition is significantly worse than described.", "cancel": "You can cancel or reschedule free of charge up to 48 hours before your appointment and your deposit will be refunded. Within 48 hours the deposit is non-refundable but can be moved to a new date once.", "refund": "If you are unhappy with any part of the service, tell us within 48 hours and we will return to put it right. Refunds of balances are issued to the original payment method within 5\u201310 working days.", "faq": [["Do I need to provide water and power?", "No \u2014 we are fully self-sufficient, though access to an outside tap is always helpful."], ["How long does a valet take?", "Maintenance valets take around 2 hours; full valets around 3. Detailing packages are full-day or multi-day bookings."], ["How does the deposit work?", "A 20% deposit secures your slot. The balance is paid on the day by card, cash or bank transfer."], ["What areas do you cover?", "We cover the whole of Kent. Enter your postcode when booking to check instantly."], ["How do pre-paid plans work?", "Pay once for 12 or 24 valets at 20% off, then book them whenever suits you \u2014 no paying each time."], ["Can I buy a gift voucher?", "Yes \u2014 message us on WhatsApp and we''ll arrange a voucher for any amount or service."]], "heroSlides": [], "offers": [], "stats": [{"v": "Kent", "l": "fully mobile service"}, {"v": "100%", "l": "fully insured"}, {"v": "20%", "l": "off pre-paid plans"}, {"v": "7 days", "l": "online enquiries"}], "social": {"facebook": "https://www.facebook.com/share/192dtBBr77/?mibextid=wwXIfr", "instagram": "", "tiktok": "", "google": ""}}'::jsonb
where slug = 'bclean' and not (settings ? 'faq');
