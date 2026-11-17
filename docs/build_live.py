import re
s=open('/home/claude/valetiq/index.html').read()
def R(a,b,n=1):
    global s
    assert s.count(a)==n,(a[:80],s.count(a));s=s.replace(a,b)
# conditional gallery + reviews sections
lines=s.split('\n')
for i,l in enumerate(lines):
    if l.startswith(' <section class="s"><div class="shead"><div><div class="kick">Our work</div>'):
        lines[i]=' ${t.gallery.filter(g=>g.show).length?`'+l.strip()+'`:\'\'}'
    if l.startswith(' <section class="s"><div class="shead"><div><div class="kick">Reviews</div>'):
        j=i
s='\n'.join(lines)
R(""" <section class="s"><div class="shead"><div><div class="kick">Reviews</div>""",""" ${rv.length?`<section class="s"><div class="shead"><div><div class="kick">Reviews</div>""")
R("""<div class="tiny mu">${esc(x.name)} · ${esc(x.town||'')} · ${esc(x.service)}</div></div>`).join('')}</div></section>""","""<div class="tiny mu">${esc(x.name)} · ${esc(x.town||'')} · ${esc(x.service)}</div></div>`).join('')}</div></section>`:''}""")
R("""<div class="pr"><small class="mu">from </small>${gbp(s.p[0])}</div>""","""<div class="pr">${s.poa?'<small class="mu" style="font-size:15px">Price on request</small>':`<small class="mu">from </small>${gbp(s.p[0])}`}</div>""")
R("<title>valetIQ — B Clean platform prototype</title>","<title>B Clean Valeting — Mobile valeting & detailing in Kent</title>\n<meta name=\"description\" content=\"Premium mobile car valeting and detailing across Kent. Maintenance valets, full valets, deep cleans, paint correction and ceramic coatings — on your drive.\">\n<meta name=\"theme-color\" content=\"#07080a\">")
# LIVE overrides appended before init
live=r"""
/* ================= LIVE (Stage 1) ================= */
const CFG={name:'B Clean',heroWhite:'B Clean',heroBlue:'Valeting',phone:'07934 852609',whatsapp:'07934 852609',email:'bcleanvaleting@outlook.com',facebook:'https://www.facebook.com/share/192dtBBr77/?mibextid=wwXIfr',instagram:'',tiktok:'',google:''};
function liveDB(){const t=mkTenant('bclean',CFG.name,'Kent',{heroWhite:CFG.heroWhite,heroBlue:CFG.heroBlue,phone:CFG.phone,whatsapp:CFG.whatsapp,email:CFG.email,excluded:[],surcharges:[]});const S=t.settings;
 S.chat.on=false;S.offers=[];S.social={whatsapp:!!CFG.whatsapp,facebook:!!CFG.facebook,instagram:!!CFG.instagram,tiktok:!!CFG.tiktok};
 S.stats=[{type:'custom',v:'Kent',l:'fully mobile service'},{type:'custom',v:'100%',l:'fully insured'},{type:'custom',v:'20%',l:'off pre-paid plans'},{type:'custom',v:'7 days',l:'online enquiries'}];
 S.reviewSources={google:CFG.google,facebook:CFG.facebook,trustpilot:''};
 t.services.filter(x=>x.cat==='Additional Services').forEach(x=>x.poa=true);
 t.gallery=[];t.reviews=[];return{v:'live',current:'bclean',tenants:{bclean:t},platform:{plans:[],tickets:[]},acct:null}}
function save(){}
function renderBar(){$('demobar').style.display='none'}
function render(){applyBrand();renderBar();renderSite();document.title=CFG.name+' Valeting — Mobile valeting & detailing in Kent'}
function go(r){if(r==='book')return requestBooking(BK&&BK.svc,BK&&BK.offer);if(r==='account')return toast('Customer accounts are coming soon');render();scrollTo(0,0)}
function svcMore(id){const t=T(),s=t.services.find(x=>x.id===id);modal(`<div class="kick">${esc(s.cat)} · ${durLabel(s)}</div><h2>${esc(s.name)}</h2><p class="mu">${esc(s.desc)}</p><h4>What's included</h4><ul>${s.inc.map(i=>`<li>${esc(i)}</li>`).join('')}</ul><p><b>${s.poa?'Price on request':'From '+gbp(s.p[0])}</b> <span class="mu tiny">— final price depends on vehicle size and condition; we'll confirm before booking.</span></p><button class="btn pri block" onclick="closeModal();requestBooking('${s.id}')">Request this service</button>`)}
function requestBooking(svcId,note){const t=T(),S=t.settings;const times=S.slots.filter(x=>x.on).map(x=>x.t);
 modal(`<h2>Request a booking</h2><p class="mu tiny">Send us your details and preferred time — we'll confirm your slot and price on WhatsApp. Online booking with instant confirmation is coming soon.</p>
 <label class="f">Service <b>*</b></label><select id="rqs">${CATS.map(c=>`<optgroup label="${c}">${t.services.filter(x=>x.active&&x.cat===c).map(x=>`<option value="${x.id}" ${x.id===svcId?'selected':''}>${esc(x.name)}${x.poa?'':' — from '+gbp(x.p[0])}</option>`).join('')}</optgroup>`).join('')}<option value="plan" ${svcId==='plan'?'selected':''}>Pre-paid plan (20% off)</option></select>
 <div class="grid g2"><div><label class="f">Vehicle size</label><select id="rqz">${SIZES.map((z,i)=>`<option>${z}</option>`).join('')}</select></div><div><label class="f">Make & model</label><input id="rqm" placeholder="e.g. VW Golf"></div><div><label class="f">Postcode <b>*</b></label><input id="rqp" style="text-transform:uppercase" placeholder="ME15 6RT"></div><div><label class="f">Your name <b>*</b></label><input id="rqn"></div><div><label class="f">Preferred date</label><input id="rqd" type="date" min="${TODAY()}"></div><div><label class="f">Preferred time</label><select id="rqt"><option>Any time</option>${times.map(x=>`<option>${x}</option>`).join('')}</select></div></div>
 <label class="f">Anything else?</label><textarea id="rqx" placeholder="Parking, pets, problem areas…">${note?esc(note):''}</textarea>
 <div id="rqr" class="tiny" style="margin-top:8px"></div>
 <div class="grid g2" style="margin-top:12px"><button class="btn pri" style="background:#25D366;border-color:#25D366;color:#03140a" onclick="sendRequest('wa')">${dico('wa',1)} Send on WhatsApp</button><button class="btn" onclick="sendRequest('email')">${dico('mail')} Send by email</button></div>`)}
function sendRequest(how){const t=T(),S=t.settings;if(!val('rqp')||!val('rqn'))return toast('Please add your name and postcode');const a=areaCheck(t,val('rqp'));if(!a.ok){$('rqr').innerHTML=`<span style="color:#fca5a5">${esc(a.msg)} Message us anyway and we'll see what we can do.</span>`;}
 const sv=val('rqs')==='plan'?'Pre-paid plan (20% off)':t.services.find(x=>x.id===val('rqs')).name;
 const msg=`Hi ${S.name}, I'd like to book:\n• Service: ${sv}\n• Vehicle: ${val('rqm')||'—'} (${val('rqz')})\n• Postcode: ${fmtPC(val('rqp'))}\n• Preferred: ${val('rqd')?fd(val('rqd')):'flexible'}, ${val('rqt')}\n• Name: ${val('rqn')}${val('rqx')?'\n• Notes: '+val('rqx'):''}`;
 const url=how==='wa'?`https://wa.me/${intl(S.whatsapp)}?text=${encodeURIComponent(msg)}`:`mailto:${S.email}?subject=${encodeURIComponent('Booking request — '+sv)}&body=${encodeURIComponent(msg)}`;
 location.href=url}
function buyPlan(pid){const t=T(),p=t.plans.find(x=>x.id===pid);const sv=t.services.find(x=>x.id===p.serviceId);requestBooking('plan',`Interested in the ${p.name} (${p.counts.join(' or ')} × ${sv.name}, ${planOff(t,p)}% off).`)}
function buyVoucher(){const S=T().settings;location.href=`https://wa.me/${intl(S.whatsapp)}?text=${encodeURIComponent('Hi '+S.name+", I'd like to buy a gift voucher.")}`}
function leaveReview(){const S=T().settings;const u=S.reviewSources.google||S.reviewSources.facebook;if(u)location.href=u;else toast('Thanks! Review links are coming soon.')}
function takeOffer(id){const o=(T().settings.offers||[]).find(x=>x.id===id);requestBooking(o&&o.serviceId,o?`Offer: ${o.title} — ${o.text}`:null)}

/* ---- load live content from the valetIQ database ---- */
async function loadLive(){try{if(!window.supabase||!window.VALETIQ)return;const V=window.VALETIQ;const sbc=window.supabase.createClient(V.supabaseUrl,V.supabaseKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const{data:biz,error}=await sbc.from('businesses').select('id,name,settings').eq('slug',V.business).single();if(error||!biz)return;
 const[sv,pl,sl]=await Promise.all([sbc.from('services').select('*').eq('business_id',biz.id).order('sort'),sbc.from('plans').select('*').eq('business_id',biz.id),sbc.from('time_slots').select('*').eq('business_id',biz.id).order('start_time')]);
 applyLive(biz,sv.data,pl.data,sl.data)}catch(e){console.warn('Live content not loaded',e)}}
function applyLive(biz,sv,pl,sl){const st=biz.settings||{};const t=T();const S=t.settings;const so=st.social||{};
 Object.assign(CFG,{name:biz.name,heroWhite:st.heroWhite||biz.name,heroBlue:st.heroBlue||'',phone:st.phone||CFG.phone,whatsapp:st.whatsapp||CFG.whatsapp,email:st.email||CFG.email,facebook:so.facebook||'',instagram:so.instagram||'',tiktok:so.tiktok||'',google:so.google||''});
 Object.assign(S,{name:biz.name,heroWhite:CFG.heroWhite,heroBlue:CFG.heroBlue,heroDesc:st.heroDesc||S.heroDesc,phone:CFG.phone,whatsapp:CFG.whatsapp,email:CFG.email,depositPct:st.depositPct??20,prepaidOff:st.prepaidOff??20});
 S.social={whatsapp:!!CFG.whatsapp,facebook:!!CFG.facebook,instagram:!!CFG.instagram,tiktok:!!CFG.tiktok};S.reviewSources={google:CFG.google,facebook:CFG.facebook,trustpilot:''};
 if(Array.isArray(st.stats))S.stats=st.stats.slice(0,4).map(x=>({type:'custom',v:x.v,l:x.l}));
 if(Array.isArray(st.faq))S.faq=st.faq;['terms','cancel','refund'].forEach(k=>{if(st[k])S[k]=st[k]});
 S.heroSlides=(st.heroSlides||[]).filter(h=>h&&h.url).map(h=>({img:h.url,caption:''}));
 S.offers=(st.offers||[]).map(o=>({id:o.id,title:o.title||'Offer',text:o.text||'',serviceId:o.serviceId,code:'',expires:o.expires||'',active:!!o.active}));
 if(sl&&sl.length)S.slots=sl.map(x=>({t:x.start_time.slice(0,5),on:x.enabled}));
 if(sv&&sv.length)t.services=sv.map(s=>{const sm=+s.price_small||0,md=s.price_medium!=null?+s.price_medium:sm,lg=s.price_large!=null?+s.price_large:md;return{id:s.id,cat:s.category,name:s.name,p:[sm,md,lg],mins:s.duration_mins,days:s.days,label:s.day_label,redeem:s.redeemable,active:s.active,desc:s.description,inc:s.includes||[],img:s.image_url||null,poa:s.price_on_request}});
 if(pl)t.plans=pl.filter(p=>t.services.some(s=>s.id===p.service_id)).map(p=>({id:p.id,name:p.name,serviceId:p.service_id,eligible:p.eligible||[],counts:p.counts||[12],months:p.months||12,off:p.discount_pct,desc:p.description,active:p.active,featured:p.featured}));
 render()}
window.addEventListener('load',loadLive);
"""
R("\ntry{DB=JSON.parse(localStorage.getItem(LS))}catch(e){}if(!DB||DB.v!==6)DB=seedAll();\nrender();",live+"\nDB=liveDB();\nrender();")
# hide gift voucher / referral card links that need accounts: referral "Get my code" -> request
R("""<button class="btn" style="align-self:start" onclick="go('account')">Get my code</button>""","""<button class="btn" style="align-self:start" onclick="go('account')">Coming soon</button>""")
R("✓ One payment, ${n} booking credits added instantly<br>✓ Book online — each visit uses one credit<br>✓ Stamp book shows used & remaining<br>","✓ One payment for the whole year<br>✓ Book your visits whenever suits you<br>")
R("function render(){applyBrand();renderBar();renderSite();","function render(){applyBrand();renderBar();renderSite();[...document.querySelectorAll('h2')].filter(h=>/Install the/.test(h.textContent)).forEach(h=>h.closest('section').remove());[...document.querySelectorAll('.kick')].filter(k=>/Refer a friend/.test(k.textContent)).forEach(k=>{const c=k.closest('.card');const g=c.parentNode;c.remove();g.classList.remove('g2')});")
R('''${so.facebook?`<a href="https://facebook.com" title="Facebook">f</a>`:''}${so.instagram?`<a href="https://instagram.com" title="Instagram">IG</a>`:''}${so.tiktok?`<a href="https://tiktok.com" title="TikTok">TT</a>`:''}''','''${so.facebook?`<a href="${esc(CFG.facebook)}" title="Facebook">f</a>`:''}${so.instagram?`<a href="${esc(CFG.instagram)}" title="Instagram">IG</a>`:''}${so.tiktok?`<a href="${esc(CFG.tiktok)}" title="TikTok">TT</a>`:''}''')
s=s.replace('<meta name="theme-color" content="#07080a">','<meta name="theme-color" content="#07080a">\n<script defer src="/config.js"></script>\n<script defer src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>',1)
open('/home/claude/live/index.html','w').write(s)
print('built',len(s))
