// B Clean customer app — installability, offline shell and notifications
const C='bclean-account-v2';
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(['/account/','/account/manifest.webmanifest','/account/icon-192.png'])));self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C&&x.startsWith('bclean-account')).map(x=>caches.delete(x)))));self.clients.claim()});
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==location.origin||!u.pathname.startsWith('/account'))return;
  e.respondWith(fetch(e.request).then(r=>{const cp=r.clone();caches.open(C).then(c=>c.put(e.request,cp));return r}).catch(()=>caches.match(e.request).then(r=>r||caches.match('/account/'))))});
self.addEventListener('push',e=>{let d={};try{d=e.data.json()}catch(_){d={title:'B Clean',body:e.data?e.data.text():''}}
  e.waitUntil(self.registration.showNotification(d.title||'B Clean',{body:d.body||'',icon:'/account/icon-192.png',badge:'/account/icon-192.png',tag:d.tag,data:{url:d.url||'/account/'}}))});
self.addEventListener('notificationclick',e=>{e.notification.close();const url=(e.notification.data||{}).url||'/account/';
  e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(l=>{for(const c of l){if(c.url.includes('/account')){c.focus();return}}return clients.openWindow(url)}))});
