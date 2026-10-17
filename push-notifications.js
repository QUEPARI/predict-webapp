const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const call=async(client,action,data={})=>{const r=await client.rpc('push_notifications',{p_action:action,p_data:data});if(r.error)throw new Error(r.error.message);return r.data;};
const supported=()=>window.isSecureContext&&'serviceWorker' in navigator&&'PushManager' in window&&'Notification' in window;
const ios=()=>/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
const standalone=()=>matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
const worker=async()=>{const r=await navigator.serviceWorker.register('./push-worker.js',{scope:'./'});await navigator.serviceWorker.ready;return r;};
const keyBytes=key=>Uint8Array.from(atob(key.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));

export async function syncPushDevice(client){
 if(!supported()||Notification.permission!=='granted')return;
 const r=await navigator.serviceWorker.getRegistration(new URL('./',location.href));const sub=await r?.pushManager.getSubscription();
 if(sub)await call(client,'subscribe',sub.toJSON());
}

// Explicit sign-out removes this device only, preserving other signed-in devices.
export async function disconnectPushDevice(client){
 if(!supported())return;
 const r=await navigator.serviceWorker.getRegistration(new URL('./',location.href));
 const sub=await r?.pushManager.getSubscription();if(!sub)return;
 await call(client,'unsubscribe',{endpoint:sub.endpoint});await sub.unsubscribe();
}

export async function loadPushSettings(host,client){
 host.innerHTML='<h2>Telefoonmeldingen</h2><p>Ontvang een melding bij een nieuw spel en om 12:00 en 18:00 Nederlandse tijd als je nog wedstrijden moet voorspellen.</p><p role="status">Meldingen laden…</p>';
 const message=host.querySelector('[role=status]');
 if(ios()&&!standalone()){message.textContent='Open Predict via het icoon op je beginscherm om meldingen aan te zetten. In Safari: Deel → Zet op beginscherm.';return;}
 if(!supported()){message.textContent='Deze browser ondersteunt geen pushmeldingen. Gebruik een recente versie van Chrome, Edge, Firefox of Predict vanaf je iPhone-beginscherm.';return;}
 try{
  const config=await call(client,'config');if(!host.isConnected)return;
  if(!config.ready){message.textContent='Pushmeldingen worden nog ingericht. Probeer het later opnieuw.';return;}
  const registration=await worker();let sub=await registration.pushManager.getSubscription();
  // A browser subscription belongs to the currently signed-in account only.
  if(sub&&Notification.permission==='granted')await call(client,'subscribe',sub.toJSON());
  if(!host.isConnected)return;
  const buttons=document.createElement('div');buttons.className='row';buttons.innerHTML='<button type="button" class="btn" data-enable-push>Meldingen aanzetten</button><button type="button" class="btn secondary" data-disable-push>Meldingen op dit apparaat uitzetten</button>';host.append(buttons);
  const enable=buttons.querySelector('[data-enable-push]'),disable=buttons.querySelector('[data-disable-push]');
  const draw=()=>{const on=!!sub&&Notification.permission==='granted';enable.hidden=on;disable.hidden=!on;message.textContent=on?'Meldingen staan aan op dit apparaat.':Notification.permission==='denied'?'Meldingen zijn geblokkeerd. Sta ze toe in de instellingen van je telefoon of browser.':'Meldingen staan nog niet aan op dit apparaat.';};draw();
  enable.onclick=async()=>{
   // Request permission directly from the tap, before awaiting network work (iOS).
   const permission=Notification.requestPermission();enable.disabled=true;
   try{if(await permission!=='granted'){draw();return;}sub=await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:keyBytes(config.public_key)});await call(client,'subscribe',sub.toJSON());draw();}
   catch{message.textContent='Meldingen aanzetten mislukt. Tik opnieuw op Meldingen aanzetten.';}
   finally{enable.disabled=false;}
  };
  disable.onclick=async()=>{disable.disabled=true;try{await disconnectPushDevice(client);sub=null;draw();}catch{message.textContent='Uitzetten mislukt. Probeer opnieuw.';}finally{disable.disabled=false;}};
 }catch{if(host.isConnected){message.textContent='Meldingen laden mislukt.';const retry=document.createElement('button');retry.className='btn secondary';retry.textContent='Opnieuw proberen';retry.onclick=()=>loadPushSettings(host,client);host.append(retry);}}
}

export async function loadPushAdmin(host,client){
 host.innerHTML='<h2>Pushmeldingen</h2><p role="status">Meldingen laden…</p>';
 try{
  const state=await call(client,'admin');if(!host.isConnected)return;
  host.innerHTML=`<h2>Pushmeldingen</h2><p>${state.ready?'Automatisch: nieuwe spelaankondigingen en om 12:00 en 18:00 Nederlandse tijd herinneringen voor ontbrekende voorspellingen.':'De verzendservice is nog niet geactiveerd.'}</p><p>${state.devices} aangemelde apparaten</p>
   <form class="stack" data-send-push><label>Soort melding<select name="kind"><option value="reminder">Herinnering ontbrekende voorspellingen</option><option value="announcement">Spelaankondiging opnieuw versturen</option><option value="custom">Aangepast bericht naar alle spelers</option></select></label>
   <label>Spel<select name="tournament"><option value="">Alle spelers</option>${state.tournaments.map(t=>`<option value="${esc(t.id)}" data-status="${esc(t.status)}">${esc(t.name)}</option>`).join('')}</select></label>
   <div class="stack" data-custom-push hidden><label>Titel<input name="title" maxlength="80"></label><label>Bericht<textarea name="body" maxlength="240" rows="3"></textarea></label></div>
   <p class="hint" data-push-audience></p><button class="btn" ${state.ready?'':'disabled'}>Melding versturen</button><p role="status" data-send-status></p></form>
   <h3>Recente verzendingen</h3><div data-push-history></div>`;
  const form=host.querySelector('form'),message=form.querySelector('[role=status]'),button=form.querySelector('button'),hint=form.querySelector('[data-push-audience]');let revision=0,requestId=crypto.randomUUID();
  const data=()=>({kind:form.elements.kind.value,tournament_id:form.elements.kind.value==='custom'?null:form.elements.tournament.value||null,title:form.elements.title.value.trim(),body:form.elements.body.value.trim(),request_id:requestId});
  const update=async()=>{const n=++revision,d=data();const custom=d.kind==='custom';if(custom){form.elements.tournament.value='';d.tournament_id=null;}form.elements.tournament.closest('label').hidden=custom;form.querySelector('[data-custom-push]').hidden=!custom;form.elements.title.required=custom;form.elements.body.required=custom;
   hint.textContent=d.kind==='reminder'?'Alleen deelnemers met ontbrekende open voorspellingen.':d.kind==='announcement'?'Alle spelers die pushmeldingen hebben aangezet.':d.tournament_id?'Deelnemers van het gekozen spel.':'Alle spelers die pushmeldingen hebben aangezet.';
   try{const r=await call(client,'preview',d);if(host.isConnected&&n===revision)hint.textContent+=` Bereik: ${r.users} gebruikers, ${r.devices} apparaten.`;}catch(e){if(n===revision)hint.textContent=e.message;}
  };
  form.elements.kind.onchange=()=>{requestId=crypto.randomUUID();update();};form.elements.tournament.onchange=()=>{requestId=crypto.randomUUID();update();};form.oninput=()=>{requestId=crypto.randomUUID();};
  const history=()=>{host.querySelector('[data-push-history]').innerHTML=state.history.length?`<ul>${state.history.map(x=>`<li>${esc(new Date(x.created_at).toLocaleString('nl-NL'))} · ${esc(x.title)} · ${x.sent} verzonden, ${x.pending} wachtend, ${x.failed} mislukt</li>`).join('')}</ul>`:'<p>Nog geen handmatige meldingen verstuurd.</p>';};history();update();
  form.onsubmit=async e=>{e.preventDefault();button.disabled=true;message.textContent='Melding klaarzetten…';try{const r=await call(client,'send',data());if(!host.isConnected)return;message.textContent=r.devices?`Melding klaargezet voor ${r.devices} apparaten. De verzending start binnen een minuut.`:'Geen apparaten die deze melding kunnen ontvangen.';requestId=crypto.randomUUID();try{const refreshed=await call(client,'admin');if(host.isConnected){state.history=refreshed.history;history();}}catch{}}catch(e){message.textContent='Versturen mislukt: '+e.message;}finally{if(host.isConnected)button.disabled=!state.ready;}};
 }catch(e){if(host.isConnected){host.innerHTML='<h2>Pushmeldingen</h2><p role="alert"></p>';host.querySelector('p').textContent='Meldingen laden mislukt: '+e.message;}}
}
