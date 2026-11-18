// B Clean Admin — minimal service worker (installability + offline shell). Data always comes live from Supabase.
const C='bclean-admin-v33';
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(['/admin/','/admin/manifest.webmanifest','/admin/icon-192.png'])));self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x)))));self.clients.claim()});
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==location.origin)return;
  e.respondWith(fetch(e.request).then(r=>{const cp=r.clone();caches.open(C).then(c=>c.put(e.request,cp));return r}).catch(()=>caches.match(e.request).then(r=>r||caches.match('/admin/'))))});
self.addEventListener('push',e=>{let d={};try{d=e.data.json()}catch(_){d={title:'B Clean',body:e.data?e.data.text():''}}
  e.waitUntil(self.registration.showNotification(d.title||'B Clean',{body:d.body||'',icon:'/admin/icon-192.png',badge:'/admin/icon-192.png',tag:d.tag,data:{url:d.url||'/admin/'}}))});
self.addEventListener('notificationclick',e=>{e.notification.close();const url=(e.notification.data||{}).url||'/admin/';
  e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(l=>{for(const c of l){if(c.url.includes('/admin')){c.focus();c.navigate&&c.navigate(url);return}}return clients.openWindow(url)}))});
