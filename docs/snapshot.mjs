// Saves a copy of the website's public content (business settings, services, plans, time slots, gallery, reviews)
// to /snapshot.json, so the website still shows real prices and photos if Supabase is slow or down.
// Run by .github/workflows/snapshot.yml every hour; only commits when something changed.
import fs from 'node:fs';
const cfg = fs.readFileSync(new URL('../config.js', import.meta.url), 'utf8');
const url = cfg.match(/supabaseUrl:\s*'([^']+)'/)[1], key = cfg.match(/supabaseKey:\s*'([^']+)'/)[1], slug = cfg.match(/business:\s*'([^']+)'/)[1];
const get = async (path) => { const r = await fetch(`${url}/rest/v1/${path}`, { headers: { apikey: key } }); if (!r.ok) throw new Error(`${path}: ${r.status} ${await r.text()}`); return r.json(); };
const [biz] = await get(`businesses?select=id,name,settings&slug=eq.${slug}`);
if (!biz) throw new Error('business not found');
const b = `business_id=eq.${biz.id}`;
const [sv, pl, sl, ga, er] = await Promise.all([
  get(`services?select=*&${b}&order=sort`),
  get(`plans?select=*&${b}`),
  get(`time_slots?select=*&${b}&order=start_time`),
  get(`gallery_items?select=*&${b}&show=eq.true&order=sort,created_at.desc&limit=12`),
  get(`ext_reviews?select=source,author,avatar,rating,text,posted_at,url&${b}&rating=gte.4&text=neq.&order=posted_at.desc&limit=40`),
]);
const data = { biz, sv, pl, sl, ga: ga.map(g => ({ id: g.id, title: g.title, before: g.before_url, after: g.after_url, date: g.done_on, loc: g.location, show: true })), er };
const file = new URL('../snapshot.json', import.meta.url);
const old = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null;
if (old) delete old.t;
if (old && JSON.stringify(old) === JSON.stringify(data)) { console.log('No change'); process.exit(0); }
fs.writeFileSync(file, JSON.stringify({ t: Date.now(), ...data }));
console.log('Snapshot updated');
