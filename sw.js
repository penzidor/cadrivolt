// No private pages, requests, or tokens are cached by this worker.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('push',event=>{
 let data={};try{data=event.data?.json()||{};}catch{}
 const base=new URL(self.registration.scope);let target=new URL(base);
 try{const candidate=new URL(data.url,base);if(candidate.origin===base.origin&&candidate.pathname.startsWith(base.pathname))target=candidate;}catch{}
 event.waitUntil(self.registration.showNotification(data.title||'Du nouveau sur Cadrivolt',{
  body:data.body||'Ouvre Cadrivolt pour consulter tes notifications.',icon:new URL('images/cadrivolt-logo.png',base).href,
  tag:data.tag||'cadrivolt',data:{url:target.href}
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  const base=new URL(self.registration.scope);let target=new URL(base);
  try{const candidate=new URL(event.notification.data?.url||base,base);if(candidate.origin===base.origin&&candidate.pathname.startsWith(base.pathname))target=candidate;}catch{}
  const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  for(const client of windows){const current=new URL(client.url);if(current.origin===base.origin&&current.pathname.startsWith(base.pathname)){await client.navigate(target.href);await client.focus();return;}}
  await self.clients.openWindow(target.href);
 })());
});
