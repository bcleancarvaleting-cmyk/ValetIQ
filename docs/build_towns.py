# Builds the town SEO pages (car-valeting/, car-detailing/, ceramic-coating/), /areas, /fleet-valeting,
# sitemap.xml and robots.txt.  Run:  python3 docs/build_towns.py   (from the repo root)
import json, math, os, sys, hashlib, html, datetime
sys.path.insert(0, os.path.dirname(__file__))
from towns import TOWNS, slug, miles

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SITE = 'https://bcleanvaleting.co.uk'
BIZ = 'B Clean Valeting'
PHONE = '07934 852609'
WA = '447934852609'
EMAIL = 'bcleanvaleting@outlook.com'
LOGO = 'https://tigznsqtesgofvoflmem.supabase.co/storage/v1/object/public/media/454dfba2-7a0b-4e08-b87f-03bb57d9ad3c/brand/logo-1794907618178.png'
OG = 'https://tigznsqtesgofvoflmem.supabase.co/storage/v1/object/public/media/454dfba2-7a0b-4e08-b87f-03bb57d9ad3c/brand/og.jpg'
SOCIAL = ['https://www.facebook.com/share/192dtBBr77/', 'https://www.instagram.com/bcleanvaletingdetailing', 'https://www.tiktok.com/@bcleandetailingkent']
TODAY = datetime.date.today().isoformat()

# name, from price, duration text, short description
VALET = [('Maintenance Valet', 80, '2 hrs', 'A regular wash and interior tidy to keep a well-kept car looking its best between deeper cleans.'),
         ('Full Valet', 100, '3 hrs', 'Our complete inside-and-out refresh — hand wash, wheels, glass, vacuum, wipe-down and dressings.'),
         ('Interior Deep Clean', 120, '3.5 hrs', 'An intensive clean focused on the cabin: seats, carpets, headlining and every hard surface.'),
         ('Exterior Deep Clean', 120, '3 hrs', 'Full exterior decontamination — snow foam, iron fallout, tar removal — finished with protection.'),
         ('Intensive Deep Clean', 200, '5 hrs', 'For neglected vehicles — heavy soiling, pet hair and stains brought back to life.')]
DETAIL = [('Enhancement Detail + 2yr Ceramic', 500, '1 day', 'Single-stage machine polish to lift gloss, sealed with a 2-year ceramic coating.'),
          ('Enhancement + Ceramic + Interior', 600, '2 days', 'The enhancement package plus a full interior deep clean.'),
          ('2-Stage Correction + Ceramic + Interior', 800, '2 days', 'Two-stage paint correction removing most swirls and scratches, ceramic coated, plus interior deep clean.'),
          ('Headlight Restoration', None, '1.5 hrs', 'Removes yellowing and haze, then seals the lenses with UV protection.'),
          ('Engine Bay Clean', None, '1 hr', 'Safe degrease and dressing of the engine bay.')]
CERAMIC = [('New Car Protection Package', 330, '1 day', 'Light decontamination and polish for new cars, then a ceramic coating to lock in the showroom finish.'),
           ('Enhancement Detail + 2yr Ceramic', 500, '1 day', 'Machine polish to lift gloss and remove light swirls, sealed with a 2-year ceramic coating.'),
           ('2-Stage Correction + Ceramic + Interior', 800, '2 days', 'Our flagship: two-stage paint correction, ceramic coating and a full interior deep clean.'),
           ('Glass Ceramic Coating', None, '1 hr', 'Hydrophobic coating for all exterior glass — rain beads straight off.'),
           ('Exterior Maintenance (coated cars)', 40, '30 mins', 'Safe maintenance wash for ceramic-coated and protected vehicles to keep your warranty valid.')]

KINDS = {
  'car-valeting': dict(h='Car Valeting', noun='car valeting', svcs=VALET, kick='Mobile car valeting',
    lead='Mobile car valeting in {t}, done on your driveway or at your workplace. We bring our own water — all we need is a power socket nearby, and you just hand over the keys.',
    intros=['Whether it is the school-run SUV or the weekend car, our {t} customers book us for a proper hand valet without leaving home.',
            'From a quick maintenance wash to a full interior deep clean, we valet cars across {t} and the surrounding {d} area every week.',
            'Busy week? We come to you anywhere in {t} — {pc} — and leave your car spotless inside and out.'],
    faq=[('How much does a car valet cost in {t}?', 'A maintenance valet starts from £80 and a full valet from £100 for a small car. Larger vehicles and heavily soiled interiors cost a little more — you will see the exact price when you book online.'),
         ('Do I need to provide water or electricity?', 'We bring our own water, so you do not need a tap. We just need access to a power socket within reach of the car — on a driveway, at your workplace or anywhere in {t} with a socket nearby.'),
         ('How long does a full valet take?', 'Around three hours for a typical car. Intensive deep cleans for very dirty or pet-hair-heavy cars can take up to five hours.'),
         ('Can you remove pet hair and bad smells?', 'Yes — we offer specialist pet hair removal and ozone odour treatment as add-ons to any valet.')]),
  'car-detailing': dict(h='Car Detailing', noun='car detailing', svcs=DETAIL, kick='Paint correction & detailing',
    lead='Professional car detailing in {t}: machine polishing, paint correction and ceramic protection carried out at your home by a fully insured detailer.',
    intros=['Swirl marks, dull paint and light scratches can be corrected without a trip to a unit — we detail cars right across {t}.',
            'Our {t} detailing customers range from daily drivers to prestige and performance cars that deserve a flawless finish.',
            'If your paintwork has lost its gloss, a machine polish and correction will transform it. We cover all of {t} ({pc}).'],
    faq=[('What is the difference between a valet and a detail?', 'A valet cleans your car. A detail goes further — decontaminating and machine polishing the paint to remove swirls and defects, then protecting it, usually with a ceramic coating.'),
         ('How long does paint correction take?', 'An enhancement detail takes one day; a two-stage correction with interior is usually two days. We will confirm timings when you book.'),
         ('Can you detail my car at home in {t}?', 'Yes. We are fully mobile and bring our own water — we just need a power socket nearby. For the best results we ask for a driveway or covered space for longer details.'),
         ('Will polishing remove all scratches?', 'Most swirls and light scratches can be removed or greatly reduced. Deep scratches through the clear coat may need touch-up — we will always tell you honestly beforehand.')]),
  'ceramic-coating': dict(h='Ceramic Coating', noun='ceramic coating', svcs=CERAMIC, kick='Ceramic paint protection',
    lead='Ceramic coating in {t} with a written warranty. We prepare and polish your paint, then apply a professional ceramic coating for years of gloss and easy washing.',
    intros=['A ceramic coating is the best way to keep a new or newly-corrected car looking glossy — and we apply them at customers’ homes across {t}.',
            'Every ceramic coating we apply in {t} comes with a digital warranty certificate you can verify by scanning the QR code.',
            'Protect your paint from bird lime, road salt and UV with a professionally-applied ceramic coating, carried out on your drive in {t}.'],
    faq=[('How much is a ceramic coating in {t}?', 'Our New Car Protection Package starts from £330, and an enhancement detail with a 2-year ceramic coating from £500. The price depends on the size and condition of your car.'),
         ('How long does a ceramic coating last?', 'Our coatings come with a warranty of up to several years, provided the car is maintained with safe washing and an annual inspection.'),
         ('Do I get a certificate?', 'Yes — every coating comes with a {b} certificate of protection showing your vehicle, product, layers and warranty date, with a QR code to verify it.'),
         ('Can I wash my car after it has been coated?', 'Wait 7 days, then use a pH-neutral shampoo and the two-bucket method. Avoid automatic car washes. We also offer maintenance washes for coated cars.')]),
}

def km(a, b):
    R = 6371; la1, lo1, la2, lo2 = map(math.radians, (a[1], a[2], b[1], b[2]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))
def near(t, n=6): return sorted([x for x in TOWNS if x[0] != t[0]], key=lambda x: km(t, x))[:n]
def pick(lst, key): return lst[int(hashlib.md5(key.encode()).hexdigest(), 16) % len(lst)]
E = html.escape

CSS = """*{box-sizing:border-box}body{margin:0;background:#06080d;color:#eef1f7;font:16px/1.6 Inter,system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif}a{color:#7cc0ff}
.w{max-width:1080px;margin:0 auto;padding:0 20px}header{position:sticky;top:0;z-index:5;background:rgba(6,8,13,.85);backdrop-filter:blur(10px);border-bottom:1px solid #1a2130}
header .w{display:flex;align-items:center;gap:12px;height:64px}header img{height:38px}header b{font-size:17px}header .sp{flex:1}
.btn{display:inline-flex;align-items:center;gap:8px;padding:12px 20px;border-radius:999px;font-weight:700;text-decoration:none;border:1px solid #2a3346;color:#fff;background:#111724}.btn.p{background:#2f8cff;border-color:#2f8cff}.btn.g{background:#22c55e;border-color:#22c55e;color:#04110a}.btn.s{padding:8px 14px;font-size:14px}
.hero{padding:64px 0 40px;background:radial-gradient(ellipse at 80% 0%,rgba(47,140,255,.25),transparent 60%)}.kick{color:#2f8cff;font-weight:800;letter-spacing:.14em;text-transform:uppercase;font-size:12px}
h1{font-size:clamp(32px,6vw,54px);line-height:1.08;margin:10px 0 14px;letter-spacing:-.02em}h2{font-size:clamp(24px,4vw,34px);margin:0 0 14px;letter-spacing:-.01em}h3{margin:0 0 6px}
.lead{font-size:19px;color:#c3cad8;max-width:720px}.row{display:flex;gap:10px;flex-wrap:wrap;margin-top:22px}.mu{color:#8f98ab}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:18px}.chip{font-size:13px;padding:6px 12px;border-radius:999px;background:#101623;border:1px solid #1f2738;color:#cfd6e4;text-decoration:none}
section{padding:40px 0;border-top:1px solid #121826}.grid{display:grid;gap:14px;grid-template-columns:repeat(auto-fit,minmax(240px,1fr))}
.card{background:#0d121c;border:1px solid #1a2130;border-radius:16px;padding:18px}.pr{font-size:24px;font-weight:800;margin:6px 0}.pr small{font-size:13px;color:#8f98ab;font-weight:500}
ul.t{list-style:none;padding:0;display:grid;gap:8px;grid-template-columns:repeat(auto-fit,minmax(240px,1fr))}ul.t li:before{content:'✓';color:#22c55e;font-weight:800;margin-right:8px}
details{background:#0d121c;border:1px solid #1a2130;border-radius:12px;padding:14px 16px;margin-bottom:8px}summary{cursor:pointer;font-weight:700}details p{color:#aab3c5;margin:10px 0 0}
.cta{background:linear-gradient(135deg,#0d1730,#070a12);border:1px solid #1f2b45;border-radius:22px;padding:28px}
footer{padding:30px 0 90px;color:#8f98ab;font-size:14px;border-top:1px solid #121826}footer a{color:#aab3c5;margin-right:14px}
.dock{position:fixed;left:12px;right:12px;bottom:12px;display:flex;gap:8px;justify-content:center;z-index:9}.dock a{flex:1;max-width:220px;justify-content:center}"""

def page(title, desc, canon, body, ld):
    return f"""<!DOCTYPE html><html lang="en-GB"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{E(title)}</title><meta name="description" content="{E(desc)}"><link rel="canonical" href="{canon}">
<meta property="og:type" content="website"><meta property="og:title" content="{E(title)}"><meta property="og:description" content="{E(desc)}"><meta property="og:url" content="{canon}"><meta property="og:image" content="{OG}"><meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="{LOGO}"><meta name="theme-color" content="#06080d"><style>{CSS}</style>
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script></head><body>
<header><div class="w"><a href="/" style="display:flex;align-items:center;gap:10px;color:#fff;text-decoration:none"><img src="{LOGO}" alt="{BIZ}"></a><span class="sp"></span><a class="btn s" href="tel:{PHONE.replace(' ','')}">Call</a><a class="btn p s" href="/?book=1">Book now</a></div></header>
{body}
<footer><div class="w"><p><b style="color:#fff">{BIZ}</b> — fully mobile valeting, detailing and ceramic coatings across Kent. Fully insured, with our own water on board.</p>
<p><a href="/">Home</a><a href="/?book=1">Book online</a><a href="/areas">Areas we cover</a><a href="/fleet-valeting">Business &amp; fleet</a><a href="/gift">Gift vouchers</a><a href="mailto:{EMAIL}">{EMAIL}</a></p><p>© {datetime.date.today().year} {BIZ}</p></div></footer>
<div class="dock"><a class="btn g" href="https://wa.me/{WA}">WhatsApp</a><a class="btn p" href="/?book=1">Book online</a></div>
</body></html>"""

def biz_ld(area_name=None):
    d = {"@type": ["AutoWash", "LocalBusiness"], "@id": SITE + "/#business", "name": BIZ, "url": SITE, "telephone": PHONE, "email": EMAIL, "image": OG, "logo": LOGO,
         "priceRange": "££", "address": {"@type": "PostalAddress", "addressRegion": "Kent", "addressCountry": "GB"}, "sameAs": SOCIAL,
         "openingHoursSpecification": [{"@type": "OpeningHoursSpecification", "dayOfWeek": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"], "opens": "08:30", "closes": "18:00"}]}
    d["areaServed"] = {"@type": "City", "name": area_name} if area_name else {"@type": "AdministrativeArea", "name": "Kent"}
    return d

def svc_cards(svcs):
    out = []
    for n, p, dur, d in svcs:
        price = f'<div class="pr"><small>from </small>£{p}</div>' if p else '<div class="pr"><small>Price on request</small></div>'
        out.append(f'<div class="card"><h3>{E(n)}</h3>{price}<div class="mu" style="font-size:14px">⏱ approx {dur}</div><p style="color:#c3cad8;font-size:15px">{E(d)}</p><a class="btn s" href="/?book=1">Book this</a></div>')
    return '<div class="grid">' + ''.join(out) + '</div>'

def base_line(t):
    m = round(miles(t))
    if m == 0: return f"We're based right here in {E(t[0])}, on the Isle of Sheppey."
    return f"We're based in Sheerness on the Isle of Sheppey, about {m} mile{'s' if m != 1 else ''} from {E(t[0])}."
def town_page(kind, t):
    K = KINDS[kind]; name, lat, lng, pc, dist = t; sl = slug(name)
    fmt = lambda s: s.format(t=name, d=dist, pc=pc, b=BIZ)
    nb = near(t)
    url = f"{SITE}/{kind}/{sl}"
    title = f"{K['h']} {name} | Mobile {K['noun']} in {name}, Kent | {BIZ}"
    desc = f"{K['h']} in {name} ({pc.split(',')[0]}). " + {'car-valeting': 'Mobile hand valets on your drive from £80 — own water on board, fully insured. Book online in 2 minutes.',
        'car-detailing': 'Machine polishing, paint correction & ceramic protection at your home. Fully insured, book online.',
        'ceramic-coating': 'Professional ceramic coatings with a verifiable warranty certificate, applied on your drive. From £330.'}[kind]
    others = [k for k in KINDS if k != kind]
    faqs = [(fmt(q), fmt(a)) for q, a in K['faq']]
    body = f"""<div class="hero"><div class="w"><div class="kick">{K['kick']} · {E(name)}</div><h1>{K['h']} in {E(name)}</h1><p class="lead">{E(fmt(K['lead']))}</p>
<div class="row"><a class="btn p" href="/?book=1">Book online</a><a class="btn g" href="https://wa.me/{WA}?text={E(('Hi, I would like a quote for ' + K['noun'] + ' in ' + name).replace(' ', '%20'))}">WhatsApp us</a><a class="btn" href="tel:{PHONE.replace(' ','')}">Call {PHONE}</a></div>
<div class="chips"><span class="chip">📍 {E(name)} · {E(pc)}</span><span class="chip">💧 Own water on board</span><span class="chip">🛡 Fully insured</span><span class="chip">⭐ 5-star rated</span></div></div></div>
<section><div class="w"><h2>{K['h']} services in {E(name)}</h2><p class="mu">{E(fmt(pick(K['intros'], kind + name)))} Prices shown are for a small car — the exact price for your vehicle shows when you book.</p>{svc_cards(K['svcs'])}</div></section>
<section><div class="w"><h2>Why {E(name)} drivers choose {BIZ}</h2><ul class="t"><li>We come to you anywhere in {E(name)}</li><li>We bring the water — you just need a power socket</li><li>Fully insured and professionally trained</li><li>Online booking with instant confirmation</li><li>Premium, pH-safe products only</li><li>Ceramic coatings with a verifiable certificate</li></ul>
<p class="mu" style="margin-top:16px">We work right across the {E(dist)} area, including {E(', '.join(x[0] for x in nb[:5]))}. If you are in {E(pc)} you are in our regular weekly coverage.</p></div></section>
<section><div class="w"><h2>{K['h']} in {E(name)} — FAQs</h2>{''.join(f'<details><summary>{E(q)}</summary><p>{E(a)}</p></details>' for q, a in faqs)}</div></section>
<section><div class="w cta"><div class="kick">Business &amp; fleet</div><h2 style="margin-top:6px">Running a fleet in {E(name)}?</h2><p class="mu">Company cars, vans and dealership stock valeted at your premises with monthly invoicing.</p><a class="btn p" href="/fleet-valeting">Fleet valeting</a></div></section>
<section><div class="w"><h3>Also in {E(name)}</h3><div class="chips">{''.join(f'<a class="chip" href="/{k}/{sl}">{KINDS[k]["h"]} in {E(name)}</a>' for k in others)}</div>
<h3 style="margin-top:18px">{K['h']} near {E(name)}</h3><div class="chips">{''.join(f'<a class="chip" href="/{kind}/{slug(x[0])}">{K["h"]} {E(x[0])}</a>' for x in nb)}</div></div></section>"""
    ld = {"@context": "https://schema.org", "@graph": [biz_ld(name),
          {"@type": "Service", "serviceType": K['h'], "name": f"{K['h']} in {name}", "provider": {"@id": SITE + "/#business"}, "areaServed": {"@type": "City", "name": name},
           "offers": [{"@type": "Offer", "name": n, "price": p, "priceCurrency": "GBP"} for n, p, _, _ in K['svcs'] if p]},
          {"@type": "FAQPage", "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faqs]},
          {"@type": "BreadcrumbList", "itemListElement": [{"@type": "ListItem", "position": 1, "name": "Home", "item": SITE}, {"@type": "ListItem", "position": 2, "name": "Areas", "item": SITE + "/areas"}, {"@type": "ListItem", "position": 3, "name": f"{K['h']} {name}", "item": url}]}]}
    return page(title, desc, url, body, ld)

def areas_page():
    by = {}
    for t in TOWNS: by.setdefault(t[4], []).append(t)  # TOWNS is already sorted nearest-first from Sheerness
    body = '<div class="hero"><div class="w"><div class="kick">Coverage</div><h1>Areas we cover across Kent</h1><p class="lead">We cover the whole of Kent. Fully mobile with our own water on board — pick your town below.</p><div class="row"><a class="btn p" href="/?book=1">Book online</a><a class="btn" href="/?areas=1">Check your postcode</a></div></div></div>'
    for d in sorted(by, key=lambda d: min(miles(t) for t in by[d])):
        body += f'<section><div class="w"><h2>{E(d)}</h2><div class="grid">'
        for t in by[d]:
            s = slug(t[0])
            body += f'<div class="card"><h3>{E(t[0])}</h3><div class="mu" style="font-size:13px">{E(t[3])}</div><div class="chips">' + ''.join(f'<a class="chip" href="/{k}/{s}">{KINDS[k]["h"]}</a>' for k in KINDS) + '</div></div>'
        body += '</div></div></section>'
    return page(f'Areas we cover | Mobile valeting & detailing across Kent | {BIZ}', 'Mobile car valeting, detailing and ceramic coatings across Kent — Maidstone, Medway, Tonbridge, Tunbridge Wells, Sevenoaks, Ashford, Canterbury, Thanet and more.', SITE + '/areas', body, {"@context": "https://schema.org", **biz_ld()})

def fleet_page():
    faqs = [('Do you invoice businesses?', 'Yes — we invoice your company monthly, made out to your business name and address, with a PDF invoice by email.'),
            ('Can you clean vehicles at our premises?', 'Yes. We bring our own water and just need access to a power socket, so we can work in your car park or yard with no disruption.'),
            ('Do you offer fleet discounts?', 'Volume pricing is available for two or more vehicles and for regular weekly, fortnightly or monthly visits.'),
            ('What vehicles do you clean?', 'Company cars, vans, pickups, dealership and hire stock — inside and out, from maintenance washes to full valets.')]
    body = f"""<div class="hero"><div class="w"><div class="kick">Business &amp; fleet</div><h1>Fleet &amp; business valeting across Kent</h1><p class="lead">Keep your company cars, vans and dealership stock looking sharp — cleaned on-site at your premises, invoiced monthly, with no downtime for your team.</p>
<div class="row"><a class="btn p" href="/?fleet=1">Get a fleet quote</a><a class="btn g" href="https://wa.me/{WA}?text=Hi%2C%20I%27d%20like%20a%20fleet%20valeting%20quote">WhatsApp us</a><a class="btn" href="tel:{PHONE.replace(' ','')}">Call {PHONE}</a></div></div></div>
<section><div class="w"><h2>Why businesses use {BIZ}</h2><ul class="t"><li>On-site at your yard, office or car park</li><li>Monthly invoicing to your company</li><li>Regular fixed weekly or monthly slots</li><li>Volume pricing for 2+ vehicles</li><li>Fully insured, own water on board</li><li>One contact, one invoice</li><li>Vans, pickups, company cars and dealership stock</li><li>Ceramic protection for new fleet vehicles</li></ul></div></section>
<section><div class="w"><h2>Fleet services</h2>{svc_cards([VALET[0], VALET[1], VALET[2], CERAMIC[0]])}</div></section>
<section><div class="w"><h2>FAQs</h2>{''.join(f'<details><summary>{E(q)}</summary><p>{E(a)}</p></details>' for q, a in faqs)}</div></section>
<section><div class="w cta"><h2>Get a fleet quote in 60 seconds</h2><p class="mu">Tell us how many vehicles and how often — we reply within one working day.</p><a class="btn p" href="/?fleet=1">Get a quote</a></div></section>
<section><div class="w"><h3>Fleet valeting across Kent</h3><div class="chips">{''.join(f'<a class="chip" href="/car-valeting/{slug(t[0])}">{E(t[0])}</a>' for t in TOWNS)}</div></div></section>"""
    ld = {"@context": "https://schema.org", "@graph": [biz_ld(), {"@type": "Service", "serviceType": "Fleet valeting", "name": "Fleet & business valeting in Kent", "provider": {"@id": SITE + "/#business"}, "areaServed": {"@type": "AdministrativeArea", "name": "Kent"}},
          {"@type": "FAQPage", "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faqs]}]}
    return page(f'Fleet & Business Valeting Kent | On-site, invoiced monthly | {BIZ}', 'Fleet and business car valeting across Kent — company cars, vans and dealership stock cleaned at your premises, invoiced monthly. Get a quote.', SITE + '/fleet-valeting', body, ld)

def main():
    urls = [(SITE + '/', '1.0'), (SITE + '/areas', '0.8'), (SITE + '/fleet-valeting', '0.8')]
    n = 0
    for kind in KINDS:
        os.makedirs(os.path.join(ROOT, kind), exist_ok=True)
        for t in TOWNS:
            open(os.path.join(ROOT, kind, slug(t[0]) + '.html'), 'w').write(town_page(kind, t)); n += 1
            urls.append((f"{SITE}/{kind}/{slug(t[0])}", '0.7'))
    open(os.path.join(ROOT, 'areas.html'), 'w').write(areas_page())
    open(os.path.join(ROOT, 'fleet-valeting.html'), 'w').write(fleet_page())
    sm = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'<url><loc>{u}</loc><lastmod>{TODAY}</lastmod><priority>{p}</priority></url>\n' for u, p in urls) + '</urlset>\n'
    open(os.path.join(ROOT, 'sitemap.xml'), 'w').write(sm)
    open(os.path.join(ROOT, 'robots.txt'), 'w').write(f"User-agent: *\nAllow: /\nDisallow: /admin/\nDisallow: /account/\nDisallow: /prototype/\n\nSitemap: {SITE}/sitemap.xml\n")
    print(f'{n} town pages + areas + fleet, {len(urls)} URLs in sitemap')

if __name__ == '__main__':
    main()
