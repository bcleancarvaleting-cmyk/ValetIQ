# ---- appended into build_live.py (exec'd) : next free slot, slider, reviews, coverage map, fleet, certificates
import sys,json
sys.path.insert(0,'/home/claude/ValetIQ-repo/docs')
from towns import TOWNS, slug as tslug, miles
KT=json.dumps([[t[0],round(t[1],4),round(t[2],4),tslug(t[0]),round(miles(t))] for t in TOWNS],separators=(',',':'))

R(".stars{color:#fbbf24;letter-spacing:2px}",
".stars{color:#fbbf24;letter-spacing:2px}"
".nfs{display:inline-flex;align-items:center;gap:10px;padding:8px 14px 8px 12px;border-radius:999px;background:rgba(8,12,22,.55);backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);border:1px solid rgba(255,255,255,.18);color:#fff;font-size:14px;margin-bottom:14px;cursor:pointer;font-family:inherit;animation:nfsIn .7s cubic-bezier(.16,1,.3,1)}.nfs{white-space:nowrap;max-width:100%}@media(max-width:420px){.nfs{font-size:12.5px;gap:8px}.nfs span{display:none}}.nfs i{width:9px;height:9px;border-radius:50%;background:#22c55e;animation:nfp 1.8s infinite;flex:none}.nfs b{font-weight:800}.nfs span{color:#7cc0ff;font-weight:700}"
"@keyframes nfp{0%{box-shadow:0 0 0 0 rgba(34,197,94,.7)}70%{box-shadow:0 0 0 10px rgba(34,197,94,0)}100%{box-shadow:0 0 0 0 rgba(34,197,94,0)}}@keyframes nfsIn{from{opacity:0;transform:translateY(8px)}}"
".ba .hd{position:absolute;top:50%;width:48px;height:48px;margin:-24px 0 0 -24px;border-radius:50%;background:#fff;box-shadow:0 6px 22px rgba(0,0,0,.5),0 0 0 5px rgba(255,255,255,.22);display:grid;place-items:center;pointer-events:none;color:#0b0f19;z-index:2}.ba .hd svg{width:26px;height:26px}.ba .ln{width:3px;margin-left:-1px;z-index:1}.ba input{touch-action:pan-y;z-index:3}.ba .lb{z-index:2}"
".covw{display:grid;grid-template-columns:1.6fr 1fr;gap:16px}@media(max-width:800px){.covw{grid-template-columns:1fr}}.covmap{height:440px;border-radius:18px;overflow:hidden;border:1px solid var(--ln);background:#070a12}@media(max-width:600px){.covmap{height:340px}}"
".covtowns{display:flex;flex-wrap:wrap;gap:6px;max-height:300px;overflow:auto;margin-top:8px}.covtowns a{font-size:12px;padding:5px 10px;border-radius:999px;background:var(--p2);border:1px solid var(--ln);color:inherit;text-decoration:none}.covtowns a:hover{border-color:var(--ac)}"
".cvdot{width:12px;height:12px;border-radius:50%;background:var(--ac,#2f8cff);box-shadow:0 0 0 3px rgba(47,140,255,.25),0 0 14px 3px rgba(47,140,255,.7)}.cvme{width:18px;height:18px;border-radius:50%;background:#22c55e;box-shadow:0 0 0 0 rgba(34,197,94,.7);animation:nfp 1.6s infinite}"
".leaflet-popup-content-wrapper,.leaflet-popup-tip{background:#0d1322!important;color:#fff!important;border:1px solid rgba(255,255,255,.12)}.leaflet-popup-content a{color:#7cc0ff!important;font-weight:700}.leaflet-container{font-family:inherit!important}"
".fleet{position:relative;overflow:hidden;border-radius:22px;padding:28px;background:linear-gradient(135deg,#0d1730,#070a12 60%);border:1px solid var(--ln)}.fleet:after{content:'';position:absolute;right:-80px;top:-80px;width:300px;height:300px;border-radius:50%;background:radial-gradient(circle,rgba(47,140,255,.35),transparent 70%)}.fleet ul{list-style:none;padding:0;margin:14px 0;display:grid;grid-template-columns:1fr 1fr;gap:8px 18px}@media(max-width:600px){.fleet ul{grid-template-columns:1fr}}.fleet li:before{content:'✓';color:#22c55e;font-weight:800;margin-right:8px}"
".rvsum{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.rvchip{display:inline-flex;align-items:center;gap:6px;font-size:12px;padding:4px 10px;border-radius:999px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);color:#dfe5f2;text-decoration:none}.rvchip .srcb{width:18px;height:18px;font-size:11px}")

# next free slot in hero
R('<div class="hin">\n  <h1>','<div class="hin">\n  <div id="nfs">${nfsHTML()}</div><h1>')
# slider handle
R("""<div class="ln" style="left:50%"></div><span class="lb" style="left:8px">BEFORE</span><span class="lb" style="right:8px">AFTER</span><input type="range" min="0" max="100" value="50" oninput="const p=this.parentNode;p.querySelector('.b').style.clipPath='inset(0 '+(100-this.value)+'% 0 0)';p.querySelector('.ln').style.left=this.value+'%'" aria-label="Before and after slider">""",
"""<div class="ln" style="left:50%"></div><div class="hd" style="left:50%"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l-6 6 6 6M15 6l6 6-6 6"/></svg></div><span class="lb" style="left:8px">BEFORE</span><span class="lb" style="right:8px">AFTER</span><input type="range" min="0" max="100" value="50" step="0.1" oninput="baSet(this)" onpointerdown="this.parentNode._u=1" ontouchstart="this.parentNode._u=1" aria-label="Before and after slider">""")
# live reviews from Google/Facebook
R("sbc.from('gallery_items').select('*').eq('business_id',biz.id).eq('show',true).order('sort').order('created_at',{ascending:false}).limit(12)]);",
"sbc.from('gallery_items').select('*').eq('business_id',biz.id).eq('show',true).order('sort').order('created_at',{ascending:false}).limit(12),sbc.from('ext_reviews').select('source,author,avatar,rating,text,posted_at,url').eq('business_id',biz.id).gte('rating',4).neq('text','').order('posted_at',{ascending:false}).limit(40)]);")
R("const[sv,pl,sl,ga]=await Promise.all(","const[sv,pl,sl,ga,er]=await Promise.all(")
R("show:true}));render();refCapture();","show:true}));t.reviews=mapRv(er&&er.data);render();refCapture();nextFree();clearInterval(window._nfi);window._nfi=setInterval(nextFree,300000);")
R("sl:sl.data,ga:t.gallery}))","sl:sl.data,ga:t.gallery,er:er&&er.data||[]}))")
R("T().gallery=c.ga||[];window.__bcCached=1","T().gallery=c.ga||[];T().reviews=mapRv(c.er);window.__bcCached=1")
R("S.appStrip=st.appStrip===true;","S.appStrip=st.appStrip===true;S.reviewStats=st.reviewStats||null;S.fleet=st.fleet||{};")
R("""return`<section class="rvm"><div class="wrap row" style="margin-bottom:14px"><b class="disp" style="font-size:18px">${avg}★</b><span class="mu tiny">from ${rv.length} reviews across ${[...new Set(rv.map(x=>(SRC[x.source]||SRC.site).n))].join(', ')}</span><span class="sp"></span>${links}</div>""",
"""const RS=S.reviewStats||{},parts=[['google',RS.google],['facebook',RS.facebook]].filter(x=>x[1]&&x[1].count&&x[1].rating),tot=parts.reduce((a,x)=>a+ +x[1].count,0),avg2=tot?(parts.reduce((a,x)=>a+x[1].rating*x[1].count,0)/tot).toFixed(1):avg;
 const chips=parts.map(([k,v])=>`<a class="rvchip" href="${esc(v.url||(S.reviewSources||{})[k]||'#')}" target="_blank" rel="noopener"><span class="srcb" style="background:${SRC[k].c}">${SRC[k].l}</span>${(+v.rating).toFixed(1)}★ · ${v.count} on ${SRC[k].n}</a>`).join('');
 return`<section class="rvm"><div class="wrap rvsum" style="margin-bottom:14px"><b class="disp" style="font-size:20px">${avg2}<span style="color:#fbbf24">★</span></b><span class="mu tiny">from ${tot||rv.length} reviews${parts.length?' on '+parts.map(p=>SRC[p[0]].n).join(' & '):' across '+[...new Set(rv.map(x=>(SRC[x.source]||SRC.site).n))].join(', ')}</span>${chips}<span class="sp"></span>${links}</div>""")
R("""<p>“${esc(x.text)}”</p><div class="tiny mu">${esc(x.name)}${x.town?' · '+esc(x.town):''}</div></div>`};""",
"""<p>“${esc(x.text.length>260?x.text.slice(0,250).replace(/\\s+\\S*$/,'')+'…':x.text)}”</p><div class="tiny mu row" style="gap:8px">${x.avatar?`<img src="${esc(x.avatar)}" alt="" referrerpolicy="no-referrer" loading="lazy" style="width:22px;height:22px;border-radius:50%">`:''}${esc(x.name)}${x.town?' · '+esc(x.town):''}</div></div>`};""")
# coverage + fleet sections before gift vouchers
R(""" <section class="s"><div class="grid g2"><div class="card col"><div class="kick">Gift vouchers</div>""",
""" ${coverHTML(t)}${fleetHTML(t)}<section class="s"><div class="grid g2"><div class="card col"><div class="kick">Gift vouchers</div>""")
# footer links
R("""<a href="javascript:void 0" onclick="policies()">Terms</a>""","""<a href="/areas">Areas we cover</a><a href="javascript:void 0" onclick="fleetForm()">Business &amp; fleet</a><a href="javascript:void 0" onclick="policies()">Terms</a>""")
# URL params
R("function lbReturn(){const q=new URLSearchParams(location.search);",
"function lbReturn(){const q=new URLSearchParams(location.search);if(q.get('cert')){const c=q.get('cert');history.replaceState(null,'',location.pathname);showCert(c);return}if(q.get('fleet')){history.replaceState(null,'',location.pathname);setTimeout(fleetForm,300);return}if(q.get('areas')){history.replaceState(null,'',location.pathname);setTimeout(()=>{const e=$('s-cover');if(e)e.scrollIntoView({behavior:'smooth'})},600);return}")

NEWJS=r'''
/* ===== top review bar ===== */
function topRvBar(S){const t=(S.reviewBar||'').trim();if(!t)return'';return`<button class="rvbar" onclick="const e=document.querySelector('.rvm');if(e)e.scrollIntoView({behavior:'smooth',block:'start'})" aria-label="Read our reviews"><span class="st">★★★★★</span><span>${esc(t)}</span><span class="sb" style="background:#4285F4">G</span><span class="sb" style="background:#1877F2">f</span></button>`}
/* ===== next free slot ===== */
let NFS=null;function nfsHTML(){return NFS?`<button class="nfs" onclick="BK=null;go('book')"><i></i>Next available: <b>${NFS}</b><span>Book →</span></button>`:''}
async function nextFree(){try{if(!LIVE||!LIVE.sbc)return;const st=LIVE.biz.settings||{},id=LIVE.biz.id,from=TODAY(),to=addD(from,45);
 const[b,c,bl]=await Promise.all([LIVE.sbc.rpc('busy_times',{p_business:id,p_from:from,p_to:to}),LIVE.sbc.from('slot_closures').select('date,start_time').eq('business_id',id).gte('date',from),LIVE.sbc.from('blocked_dates').select('from_date,to_date').eq('business_id',id).gte('to_date',from)]);
 const busy=b.data||[],cl=c.data||[],blk=bl.data||[];const svs=T().services.filter(s=>s.active!==false&&!s.poa&&!(s.days>0)&&s.mins);const mins=svs.length?Math.min(...svs.map(s=>s.mins)):120;
 const buf=st.buffer??30,notice=(st.minNoticeHours??24)*3600e3,wd=Array.isArray(st.workDays)?st.workDays:[1,2,3,4,5,6];const M=x=>{const[h,m]=String(x).slice(0,5).split(':');return +h*60+ +m};
 const hs=(st.hours&&st.hours.start)||'08:30',he=(st.hours&&st.hours.end)||'18:00',fixed=st.slotMode!=='flex';
 const times=fixed?(T().settings.slots||[]).filter(x=>x.on).map(x=>x.t).sort():[...Array(Math.floor((M(he)-M(hs))/30)+1)].map((_,i)=>{const m=M(hs)+i*30;return String(Math.floor(m/60)).padStart(2,'0')+':'+String(m%60).padStart(2,'0')});
 for(let i=0;i<=45;i++){const d=addD(from,i),dow=new Date(d+'T12:00').getDay();if(!wd.includes(dow)||blk.some(x=>d>=x.from_date&&d<=x.to_date))continue;
  for(const tm of times){if(new Date(d+'T'+tm)-Date.now()<notice)continue;if(cl.some(x=>x.date===d&&String(x.start_time).slice(0,5)===tm))continue;const s0=M(tm),en=s0+mins;if(!fixed&&en>M(he))continue;
   if(busy.some(x=>x.days>0?(d>=x.date&&d<=addD(x.date,x.days-1)):(x.date===d&&s0<M(x.start_time)+(+x.duration_mins||120)+buf&&en+buf>M(x.start_time))))continue;
   const dt=new Date(d+'T'+tm),h=dt.getHours(),mm=dt.getMinutes(),t12=`${h%12||12}${mm?':'+String(mm).padStart(2,'0'):''}${h<12?'am':'pm'}`;
   const dl=i===0?'Today':i===1?'Tomorrow':dt.toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short'});
   NFS=`${dl} · ${t12}`;const e=$('nfs');if(e&&!e.firstChild)e.innerHTML=nfsHTML();else if(e)e.querySelector('b').textContent=NFS;return}}
 NFS=null;const e=$('nfs');if(e)e.innerHTML=''}catch(e){console.warn('next free',e)}}
/* ===== before/after slider ===== */
function baSet(inp){const p=inp.parentNode,v=inp.value;p.querySelector('.b').style.clipPath='inset(0 '+(100-v)+'% 0 0)';p.querySelector('.ln').style.left=v+'%';p.querySelector('.hd').style.left=v+'%'}
function baHint(){if(!window.IntersectionObserver)return;document.querySelectorAll('.ba:not([data-h])').forEach(el=>{el.dataset.h=1;const io=new IntersectionObserver(es=>{if(!es[0].isIntersecting)return;io.disconnect();const inp=el.querySelector('input');if(!inp)return;const t0=performance.now(),D=2200,key=[[0,50],[.3,18],[.68,82],[1,50]];
  const st=n=>{if(el._u)return;const p=Math.min(1,(n-t0)/D);let i=0;while(i<key.length-2&&p>key[i+1][0])i++;const[a,va]=key[i],[b,vb]=key[i+1];const k=(p-a)/(b-a),e=k<.5?2*k*k:1-Math.pow(-2*k+2,2)/2;inp.value=va+(vb-va)*e;baSet(inp);if(p<1)requestAnimationFrame(st)};setTimeout(()=>requestAnimationFrame(st),350)},{threshold:.6});io.observe(el)})}
/* ===== reviews ===== */
function mapRv(L){return(L||[]).map((x,i)=>({id:'x'+i,name:x.author||x.name,town:'',stars:x.rating||x.stars||5,text:x.text||'',source:x.source,approved:true,service:'',avatar:x.avatar||null,author:x.author,rating:x.rating}))}
/* ===== coverage map ===== */
const KT=__KT__;
function coverHTML(t){return`<section class="s" id="s-cover"><div class="shead"><div><div class="kick">Areas we cover</div><h2>We cover Kent</h2><p>Fully mobile — we bring our own water, you just provide a power socket.</p></div></div>
 <div class="card col"><b>Do you cover me?</b><form class="pcbox" style="margin-top:8px;max-width:520px" onsubmit="event.preventDefault();covCheck()"><input id="cpc" placeholder="Enter your postcode" autocomplete="postal-code"><button class="btn pri">Check</button></form><div id="cres" class="tiny" style="min-height:20px;margin-top:8px"></div>
 <div class="tiny mu" style="margin-top:10px">Tap your town:</div><div class="covtowns">${KT.map(x=>`<a href="/car-valeting/${x[3]}">${esc(x[0])}</a>`).join('')}</div><a class="tiny" href="/areas" style="display:inline-block;margin-top:10px">See all areas →</a></div></section>`}
function covCheck(){const t=T(),pc=val('cpc'),res=areaCheck(t,pc);$('cres').innerHTML=`<span style="color:${res.ok?'#86efac':'#fca5a5'}">${esc(res.msg)}</span> ${res.ok?`<button class="btn xs pri" onclick="BK=null;newBK({pc:'${esc(fmtPC(pc))}'});BK.area=areaCheck(T(),BK.pc);BK.step=2;go('book')">Book now →</button>`:`<a class="btn xs" href="https://wa.me/${intl(t.settings.whatsapp)}">Ask on WhatsApp</a>`}`}
/* ===== business / fleet ===== */
function fleetHTML(t){return`<section class="s" id="s-fleet"><div class="fleet"><div class="kick">Business &amp; fleet</div><h2 style="margin:6px 0">Fleet valeting for Kent businesses</h2><p class="mu" style="max-width:620px">Company cars, vans, dealerships and hire fleets cleaned at your premises — with no downtime for your team.</p>
 <ul><li>On-site at your yard or office</li><li>Monthly invoicing to your company</li><li>Regular fixed slots</li><li>Volume pricing for 2+ vehicles</li><li>Fully insured, own water on board</li><li>One contact, one invoice</li></ul><div class="row" style="gap:8px;position:relative;z-index:1"><button class="btn pri" onclick="fleetForm()">Get a fleet quote</button><a class="btn" href="/fleet-valeting">Learn more</a></div></div></section>`}
function fleetForm(){modal(`<div class="kick">Business &amp; fleet</div><h2>Get a fleet quote</h2><p class="mu tiny">Tell us about your vehicles — we'll come back with a price within one working day.</p>
 <label class="f">Company name</label><input id="fq_co" autocomplete="organization"><div class="grid g2"><div><label class="f">Your name <b>*</b></label><input id="fq_n" autocomplete="name"></div><div><label class="f">Phone <b>*</b></label><input id="fq_p" type="tel" autocomplete="tel"></div></div>
 <div class="grid g2"><div><label class="f">Email</label><input id="fq_e" type="email" autocomplete="email"></div><div><label class="f">Site postcode</label><input id="fq_pc" autocomplete="postal-code"></div></div>
 <div class="grid g2"><div><label class="f">How many vehicles?</label><select id="fq_v">${['2–5','6–10','11–25','26–50','50+','Just 1 for now'].map(x=>`<option>${x}</option>`).join('')}</select></div><div><label class="f">How often?</label><select id="fq_f">${['Weekly','Fortnightly','Monthly','One-off','Not sure yet'].map(x=>`<option>${x}</option>`).join('')}</select></div></div>
 <label class="f">Anything else?</label><textarea id="fq_m" placeholder="Vehicle types, services needed, access to water…"></textarea><div id="fq_err" class="tiny" style="color:#fca5a5;min-height:18px"></div><button class="btn pri block" id="fq_go" onclick="fleetSend()">Send enquiry</button>`)}
async function fleetSend(){const p={kind:'fleet',company:val('fq_co'),name:val('fq_n'),phone:val('fq_p'),email:val('fq_e'),postcode:val('fq_pc'),vehicles:val('fq_v'),frequency:val('fq_f'),message:val('fq_m')};if(!p.name||!(p.phone||p.email)){$('fq_err').textContent='Please add your name and a phone number';return}
 const b=$('fq_go');b.disabled=true;b.textContent='Sending…';try{if(!LIVE||!LIVE.sbc)throw new Error('Please try again in a moment');const{error}=await LIVE.sbc.rpc('submit_enquiry',{p_business:LIVE.biz.id,p});if(error)throw error;
  modal(`<div style="text-align:center"><div style="font-size:52px">🏢</div><h2>Thanks${p.company?', '+esc(p.company):''}!</h2><p class="mu">We've got your enquiry and will be in touch within one working day.</p><button class="btn pri" onclick="closeModal()">Done</button></div>`)}catch(e){b.disabled=false;b.textContent='Send enquiry';$('fq_err').textContent=(e&&e.message)||'Something went wrong — please call us'}}
/* ===== ceramic certificate verify ===== */
let _ctP=null;function loadCertJs(){if(window.certCanvas)return Promise.resolve();if(!_ctP)_ctP=new Promise((res,rej)=>{const s=document.createElement('script');s.src='/cert.js?v=1';s.onload=res;s.onerror=rej;document.head.appendChild(s)});return _ctP}
async function showCert(code){modal(`<div style="text-align:center;padding:30px"><div class="spin" style="margin:auto"></div><p class="mu">Checking certificate ${esc(code)}…</p></div>`,{wide:true});
 for(let i=0;i<80&&!(LIVE&&LIVE.sbc);i++)await new Promise(r=>setTimeout(r,150));
 try{await loadCertJs();const{data:c,error}=await LIVE.sbc.rpc('get_certificate',{p_code:code});if(error)throw error;
  if(!c){modal(`<div style="text-align:center"><div style="font-size:48px">⚠️</div><h2>Certificate not found</h2><p class="mu">We couldn't find certificate <b>${esc(code)}</b>. Please check the code or contact us.</p></div>`);return}
  const exp=c.expires_on||certAddYears(c.applied_on,c.warranty_years),live=!c.void&&exp>=TODAY();
  const cv=await certCanvas(c,c.design,{business:c.business,logo:(c.brand||{}).logo,showName:(c.brand||{}).showName,website:location.host.replace(/^www\./,''),phone:c.phone,email:c.email,verifyUrl:location.origin+'/cert/'+c.code});
  const url=cv.toDataURL('image/png');
  modal(`<div class="row" style="gap:10px;margin-bottom:10px"><span style="font-size:30px">${c.void?'⛔':live?'✅':'⌛'}</span><div><h3 style="margin:0">${c.void?'This certificate has been cancelled':live?'Genuine certificate':'Warranty period ended'}</h3><div class="tiny mu">${esc(c.code)} · ${esc(c.product)} · ${live?'protected until '+certFmt(exp):'ended '+certFmt(exp)}</div></div></div>
   <img src="${url}" alt="Ceramic coating certificate" style="width:100%;border-radius:12px;display:block"><div class="row" style="gap:8px;margin-top:12px"><a class="btn pri" href="${url}" download="${esc(c.code)}.png">Download certificate</a><button class="btn" onclick="BK=null;closeModal();go('book')">Book a maintenance valet</button></div>`,{wide:true})}
 catch(e){modal(`<h3>Couldn't load the certificate</h3><p class="mu">${esc((e&&e.message)||'Please try again')}</p>`)}}
setInterval(baHint,700);
'''.replace('__KT__',KT)
R("let NFS_PLACEHOLDER=0;","") if "let NFS_PLACEHOLDER=0;" in s else None
R("function bootDone(){",NEWJS+"\nfunction bootDone(){")

# we carry water only — customers provide a power socket
R("fully insured and self-sufficient, with our own water and power.'","fully insured, with our own water on board.'")
R("{k:'water, electric, power',a:'No need — we\\'re fully self-sufficient with our own water and power.'","{k:'water, electric, power',a:'We bring our own water — we just need access to a power socket near the car.'")
R("We need access to water and electricity, or we will bring our own (please let us know).","We bring our own water, but need access to a power socket within reach of the vehicle.")
R("['Do I need to provide water and power?','No — we are fully self-sufficient, though access to an outside tap is always helpful.']","['Do I need to provide water and power?','We bring our own water — we just need access to a power socket near the car.']")
R("['Turned up on time, fully self-sufficient and the interior is like new. Great value.',5]","['Turned up on time, brought their own water and the interior is like new. Great value.',5]")

R('<meta charset="utf-8">','<meta charset="utf-8"><meta name="google-site-verification" content="4R4QseL6JL9ga6bITPFnNC0Otcp4xOnaQ28lyqzb-04" />',1) if s.count('<meta charset="utf-8">')==1 else R('<meta charset="UTF-8">','<meta charset="UTF-8"><meta name="google-site-verification" content="4R4QseL6JL9ga6bITPFnNC0Otcp4xOnaQ28lyqzb-04" />',1)

# /book/<service-slug> opens booking with that service picked
R("if(q.get('book')&&liveOn()){history.replaceState(null,'',location.pathname);return liveBook(null)}",
  "if(q.get('book')&&liveOn()){history.replaceState(null,'',location.pathname);const sv=q.get('svc'),sl=n=>String(n||'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,''),hit=sv&&T().services.find(x=>x.id===sv||sl(x.name)===sv);return liveBook(hit?hit.id:null)}")

# /booking (and /book-now) is a real page that opens booking straight away — for Google's "Book" button
R("if(q.get('book')&&liveOn()){","if((q.get('book')||/^\\/(booking|book-now)\\/?$/.test(location.pathname))&&liveOn()){")

# thin review bar at the very top (trust bar → hero → bookings)
R('app.innerHTML=`${appStrip(S)}<div class="wrap">\n <header class="snav">','app.innerHTML=`${topRvBar(S)}${appStrip(S)}<div class="wrap">\n <header class="snav">')
R("S.appStrip=st.appStrip===true;","S.appStrip=st.appStrip===true;S.reviewBar=st.reviewBar===undefined?'100+ 5-star reviews on Google & Facebook':st.reviewBar;")
R(".stars{color:#fbbf24;letter-spacing:2px}",".stars{color:#fbbf24;letter-spacing:2px}.rvbar{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;padding:7px 12px;border:0;border-bottom:1px solid rgba(255,255,255,.08);background:linear-gradient(90deg,#06090f,#0e1626 50%,#06090f);color:#e8edf7;font-family:inherit;font-weight:600;font-size:12.5px;line-height:1.2;cursor:pointer;position:relative;overflow:hidden;white-space:nowrap}.rvbar .st{color:#fbbf24;letter-spacing:1px;font-size:12px}.rvbar .sb{display:inline-grid;place-items:center;width:16px;height:16px;border-radius:4px;color:#fff;font:800 10px/1 Arial}.rvbar:after{content:'';position:absolute;top:0;bottom:0;width:80px;left:-100px;background:linear-gradient(90deg,transparent,rgba(255,255,255,.12),transparent);animation:rvsh 4.5s ease-in-out infinite}@keyframes rvsh{0%,60%{left:-100px}100%{left:110%}}@media(max-width:430px){.rvbar{font-size:12px;gap:6px;padding:7px 8px}.rvbar .sb{display:none}.rvbar .st{letter-spacing:0}}")

# push Google reviews: every "Leave a review" goes straight to the Google review box
R("S.appStrip=st.appStrip===true;","S.appStrip=st.appStrip===true;S.gReview=(st.reviewLinks&&st.reviewLinks.googlePlaceId)?'https://search.google.com/local/writereview?placeid='+encodeURIComponent(st.reviewLinks.googlePlaceId):(st.reviewUrl||(st.social&&st.social.google)||'');")
R("function leaveReview(){modal(","function leaveReview(){const g=T().settings.gReview;if(g){window.open(g,'_blank','noopener');return}modal(")
R("""${chips}<span class="sp"></span>${links}</div>""","""${chips}<span class="sp"></span>${S.gReview?`<a class="btn xs pri" href="${esc(S.gReview)}" target="_blank" rel="noopener">⭐ Leave us a Google review</a>`:links}</div>""")

# review header: Google chip + review button side by side on mobile
R("""${chips}<span class="sp"></span>${S.gReview?`<a class="btn xs pri" href="${esc(S.gReview)}" target="_blank" rel="noopener">⭐ Leave us a Google review</a>`:links}</div>""",
  """<div class="rvact">${chips}${S.gReview?`<a class="btn xs pri" href="${esc(S.gReview)}" target="_blank" rel="noopener">⭐ Leave a Google review</a>`:links}</div></div>""")
R(".rvsum{display:flex;align-items:center;gap:10px;flex-wrap:wrap}",".rvsum{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.rvact{display:flex;align-items:center;gap:8px;flex-wrap:nowrap;margin-left:auto}.rvact>*{white-space:nowrap}@media(max-width:600px){.rvact{margin-left:0;width:100%}.rvact .rvchip{font-size:11.5px;padding:6px 9px}.rvact .btn{font-size:12px;padding:7px 11px}}")
