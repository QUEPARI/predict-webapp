const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function scoreSourceFields(){return `<label>Uitslagen<select name="scoreSource"><option value="manual">Handmatige invoer</option><option value="mastercaller_test">Scores ophalen via Mastercaller (test)</option></select></label><div data-mastercaller-fields hidden><label>Mastercaller-uitslagenlink<input name="mastercallerUrl" type="url" placeholder="https://mastercaller.nl/toernooien/european-championship/2026/uitslagen"></label><p class="hint">Ophalen via GitHub. Automatisch vóór de start elke 4 uur; tijdens wedstrijden elke 15 minuten totdat de eindstand bekend is. Bij tijd NNB kun je met bekende spelers alvast voorspellen tot de toernooistart. Beschikbaarheid hangt af van Mastercaller.</p></div>`;}
export async function invokeMastercaller(client,body){
 const result=await client.functions.invoke('sync-mastercaller',{body});
 if(result.error){let message=result.error.message;try{const detail=await result.error.context?.json();if(detail?.error)message=detail.error;}catch{}throw Error(message||'Mastercaller ophalen mislukt.');}
 if(result.data?.error)throw Error(result.data.error);return result.data;
}
export async function awaitMastercallerCreation(client,result,{signal,isCurrent=()=>true,onStatus=()=>{}}={}){
 if(!result.job_id)return result;
 onStatus(result.message||'GitHub haalt het toernooi op. Dit kan enkele minuten duren.');
 for(let attempt=0;attempt<240;attempt++){
  await new Promise((resolve,reject)=>{if(signal?.aborted)return reject(Error('Aanvraag opgeslagen; wachten gestopt.'));const abort=()=>{clearTimeout(timer);reject(Error('Aanvraag opgeslagen; wachten gestopt.'));};const timer=setTimeout(()=>{signal?.removeEventListener('abort',abort);resolve();},3000);signal?.addEventListener('abort',abort,{once:true});});
  if(!isCurrent())throw Error('Aanvraag opgeslagen; wachten gestopt.');
  const r=await client.rpc('get_mastercaller_creation_status',{p_job:result.job_id});
  if(r.error)throw Error('Aanvraag opgeslagen, maar de status kon niet worden geladen. Het toernooi wordt op de achtergrond aangemaakt.');
  if(r.data?.status==='done')return r.data;
  if(r.data?.status==='failed')throw Error(r.data.error||'Mastercaller ophalen mislukt. Probeer later opnieuw.');
 }
 throw Error('De aanvraag staat nog in de wachtrij. Het toernooi verschijnt automatisch in Spellen beheren zodra de bron is opgehaald.');
}
export function bindScoreSource(form,isDarts=()=>true){
 const select=form.elements.scoreSource,url=form.elements.mastercallerUrl,fields=form.querySelector('[data-mastercaller-fields]');
 const update=()=>{const darts=isDarts();select.querySelector('[value=mastercaller_test]').disabled=!darts;if(!darts)select.value='manual';const enabled=select.value==='mastercaller_test';fields.hidden=!enabled;url.required=enabled;};
 select.addEventListener('change',update);update();return update;
}
export async function loadScoreSource(host,ctx,tournament,onSaved){
 const alive=()=>host.isConnected&&ctx.isCurrent()&&!ctx.signal?.aborted;
 const rpc=async(name,args)=>{const r=await ctx.supabase.rpc(name,args);if(r.error)throw r.error;return r.data;};
 try{
  let data=await rpc('get_tournament_score_source',{p_tournament:tournament});if(!alive())return;
  host.innerHTML=`<details class="admin-fold"><summary>Uitslagenbron</summary><form class="stack">${scoreSourceFields()}<button class="btn">Uitslagenbron opslaan</button><p role="status" data-source-message></p></form><div data-source-report></div><button type="button" class="ghost" data-fetch-scores>Nu scores ophalen (test)</button></details>`;
  const form=host.querySelector('form'),message=host.querySelector('[data-source-message]'),button=host.querySelector('[data-fetch-scores]');
  form.elements.scoreSource.value=data.source;form.elements.mastercallerUrl.value=data.url||'';
  const baseUpdate=bindScoreSource(form,()=>data.darts);let busy=false;
  const owner=document.createElement('p');owner.className='notice';owner.dataset.sourceOwner='';form.before(owner);
  const update=()=>{baseUpdate();form.hidden=!!data.automatic_setup;owner.hidden=!data.automatic_setup;owner.textContent='Mastercaller beheert dit toernooi automatisch. De bron staat vast: '+(data.url||'');if(data.automatic_setup){form.after(message);form.querySelectorAll('input,select,button').forEach(el=>el.disabled=true);}button.disabled=!!data.stopped;button.textContent=data.stopped?'Finale afgerond — ophalen gestopt':'Nu scores ophalen (test)';};
  update();
  function report(){const r=data.report||{},target=host.querySelector('[data-source-report]');button.hidden=data.source!=='mastercaller_test';target.innerHTML=data.source==='manual'?'<p class="hint">Uitslagen worden handmatig ingevoerd.</p>':`<p class="hint">Laatste controle: ${data.last_attempt?esc(new Intl.DateTimeFormat('nl-NL',{dateStyle:'short',timeStyle:'short'}).format(new Date(data.last_attempt))):'nog niet uitgevoerd'}</p>${r.error?`<p role="status">${esc(r.error)}</p>`:r.checked_at?`<p>${Number(r.applied)||0} verwerkt · ${Number(r.unchanged)||0} al aanwezig · ${Number(r.received)||0} opgehaald</p>`:''}${r.issues?.length?`<details><summary>${r.issues.length} meldingen controleren</summary><ul>${r.issues.map(i=>`<li>${esc(i.match)}: ${esc(i.reason)}</li>`).join('')}</ul></details>`:''}`;}
  async function perform(action){if(busy||data.stopped&&action==='fetch'||data.automatic_setup&&action==='save')return;busy=true;host.querySelectorAll('input,select,button').forEach(el=>el.disabled=true);message.textContent=action==='save'?'Opslaan…':'Scores ophalen…';
   try{
    if(action==='save')await rpc('set_tournament_score_source',{p_tournament:tournament,p_source:form.elements.scoreSource.value,p_url:form.elements.mastercallerUrl.value.trim()||null});
    else{const result=await invokeMastercaller(ctx.supabase,{tournament_id:tournament});if(result.message)message.textContent=result.message;}
    const next=await rpc('get_tournament_score_source',{p_tournament:tournament});if(!alive())return;data=next;report();
    if(action==='save'){host.closest('[data-detail]')?.setAttribute('data-ko-dirty','false');message.textContent='Uitslagenbron opgeslagen.';}
    else if(!message.textContent.includes('Wacht'))message.textContent=data.report?.error||'Controle afgerond.';
    onSaved?.();
   }catch(e){if(alive())message.textContent=e.message;}finally{busy=false;if(alive()){host.querySelectorAll('input,select,button').forEach(el=>el.disabled=false);update();}}
  }
  form.onsubmit=e=>{e.preventDefault();if(form.reportValidity())perform('save');};button.onclick=()=>perform('fetch');report();
 }catch(e){if(alive())host.textContent='Uitslagenbron niet beschikbaar: '+e.message;}
}
