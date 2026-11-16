-- =====================================================================
-- B Clean Valeting — first business, services, start times
-- Prices are B Clean's own small-vehicle prices. Medium/large are left
-- blank (= same as small) until set in the admin.
-- =====================================================================
with b as (
  insert into public.businesses (slug, name, ref_prefix, settings) values (
    'bclean', 'B Clean', 'BC',
    jsonb_build_object(
      'tagline', 'Premium mobile valeting & detailing',
      'heroWhite', 'B Clean', 'heroBlue', 'Valeting',
      'heroDesc', 'Showroom finish, on your drive. Premium mobile valeting & detailing — fully insured and self-sufficient, with our own water and power.',
      'accent', '#2f7bff',
      'phone', '', 'whatsapp', '', 'email', '',
      'hours', jsonb_build_object('start','08:30','end','18:00'),
      'workDays', jsonb_build_array(1,2,3,4,5,6),
      'slotMode', 'fixed', 'buffer', 30, 'minNoticeHours', 24,
      'depositPct', 20, 'cancelHours', 48, 'prepaidOff', 20,
      'paymentsLive', false,
      'area', jsonb_build_object('mode','county','county','Kent','extra','[]'::jsonb,'excluded','[]'::jsonb,'surcharges','[]'::jsonb)
    )
  ) returning id
),
svc as (
  insert into public.services (business_id, category, name, description, includes, price_small, duration_mins, days, day_label, redeemable, price_on_request, sort)
  select b.id, x.cat, x.name, x.descr, x.inc, x.price, x.mins, x.days, x.lbl, x.redeem, x.poa, x.sort from b, (values
    ('Valeting','Maintenance Valet','A regular wash and interior tidy to keep a well-kept car looking its best between deeper cleans.', array['Snow foam pre-wash & two-bucket hand wash','Wheels, tyres & arches','Interior hoover & wipe down','Glass inside & out','Tyre dressing'], 80::numeric, 120, 0, null::text, true, false, 1),
    ('Valeting','Full Valet','Our complete inside-and-out refresh.', array['Everything in Maintenance','Door shuts & jambs','Dash, console & plastics dressed','Spray sealant','Mats cleaned'], 100, 180, 0, null, true, false, 2),
    ('Valeting','Intensive Deep Clean','For neglected vehicles — heavy soiling, pet hair and stains.', array['Full decontamination wash','Seat & carpet extraction','Pet hair removal','Leather cleaned & conditioned'], 200, 300, 0, null, false, false, 3),
    ('Valeting','Interior Deep Clean','An intensive clean focused on the cabin.', array['Hot-water extraction','Headlining spot clean','Steam clean of vents & plastics','Leather treatment'], 120, 210, 0, null, true, false, 4),
    ('Valeting','Exterior Deep Clean','Full exterior decontamination and protection.', array['Iron fallout & tar removal','Clay bar','Wheels deep cleaned','6-month sealant'], 120, 180, 0, null, true, false, 5),
    ('Detailing','Enhancement Detail + 2yr Ceramic','Single-stage machine polish to lift gloss, sealed with a 2-year ceramic coating.', array['Full decontamination','Single-stage machine polish','2-year ceramic coating','Wheel faces coated','Warranty certificate'], 500, 480, 1, '1 day', false, false, 6),
    ('Detailing','Enhancement + Ceramic + Interior','The enhancement package plus a full interior deep clean.', array['Everything in Enhancement','Interior deep clean','Fabric / leather protection'], 600, 480, 2, '1.5 days', false, false, 7),
    ('Detailing','2-Stage Correction + Ceramic + Interior','Two-stage paint correction removing most swirls, ceramic coated, plus interior deep clean.', array['Paint depth readings','2-stage compound & refine','2-year ceramic coating','Interior deep clean','Warranty certificate'], 800, 480, 2, null, false, false, 8),
    ('Additional Services','Pet Hair Removal','Specialist removal of embedded pet hair from carpets, seats and boot.', array['Rubber & pumice hair removal','High-power extraction','Boot liner clean'], null, 60, 0, null, false, true, 9),
    ('Additional Services','Engine Bay Clean','Safe degrease and dressing of the engine bay.', array['Electrics protected','Low-pressure degrease','Plastics dressed'], null, 60, 0, null, false, true, 10),
    ('Additional Services','Headlight Restoration','Removes yellowing and haze, then seals the lenses with UV protection.', array['Wet sand & machine polish','UV-resistant sealant','Both headlights'], null, 90, 0, null, false, true, 11),
    ('Additional Services','Odour Removal (Ozone)','Ozone treatment to neutralise smoke, pet and damp smells at the source.', array['Ozone generator treatment','Air-con vent treatment','Cabin aired & freshened'], null, 60, 0, null, false, true, 12),
    ('Additional Services','Glass Ceramic Coating','Hydrophobic coating for all exterior glass — rain beads straight off.', array['Glass decontamination','Ceramic glass coating','12-month durability'], null, 60, 0, null, false, true, 13)
  ) as x(cat, name, descr, inc, price, mins, days, lbl, redeem, poa, sort)
  returning id, name, business_id
),
slots as (
  insert into public.time_slots (business_id, start_time)
  select b.id, t::time from b, unnest(array['08:30','09:00','12:00','12:30','14:30','15:00','17:30','18:00']) t
  returning 1
)
insert into public.plans (business_id, name, description, service_id, eligible, counts, months, featured)
select s.business_id, p.name, p.descr, s.id,
       (select array_agg(id) from svc where name = any(p.elig)), p.counts, 12, p.featured
from svc s
join (values
  ('Maintenance Plan','12 visits for a monthly clean, or 24 for fortnightly.','Maintenance Valet', array['Maintenance Valet'], array[12,24], true),
  ('Full Valet Plan','Full inside-and-out valets through the year. Credits can also be used on maintenance valets.','Full Valet', array['Full Valet','Maintenance Valet'], array[6,12], false)
) as p(name, descr, svc_name, elig, counts, featured) on p.svc_name = s.name;
