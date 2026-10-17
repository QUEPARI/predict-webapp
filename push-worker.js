// Push only: deliberately no fetch handler or page cache, so updates stay fresh.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('push',event=>{
 let data={};try{data=event.data?.json()||{};}catch{}
 event.waitUntil(self.registration.showNotification(typeof data.title==='string'?data.title:'Predict',{
  body:typeof data.body==='string'?data.body:'Er staat een nieuw bericht voor je klaar.',
  icon:new URL('./icons/predict-192.png',self.registration.scope).href,
  badge:new URL('./icons/predict-192.png',self.registration.scope).href,
  tag:typeof data.tag==='string'?data.tag:'predict',
  data:{url:self.registration.scope},
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{const base=self.registration.scope;for(const client of await self.clients.matchAll({type:'window',includeUncontrolled:true})){if(client.url.startsWith(base)&&'focus' in client){await client.focus();return;}}await self.clients.openWindow(base);})());
});
