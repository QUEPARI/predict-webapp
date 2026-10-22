const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function sourceResultAllowed(m,tournament,now=Date.now()){
 const start=m.actual_start||m.start;
 return ['published','active','completed'].includes(tournament.status)&&['scheduled','live','finished'].includes(m.status)
  &&!m.bye&&!!m.home_slot&&!!m.away_slot&&!m.needs_review
  &&(m.status==='finished'||(start?Date.parse(start)<=now:Date.parse(tournament.start)<=now));
}
function resultForm(host,ctx,tournament,m,onSaved){
 const alive=()=>host.isConnected&&ctx.isCurrent()&&!ctx.signal?.aborted;
 host.innerHTML=`<form class="stack result-entry-form"><div class="two"><label>${esc(m.home)}<input name="home" aria-label="Score ${esc(m.home)}" inputmode="numeric" type="number" min="0" max="99" step="1" required value="${esc(m.home_score??'')}"></label><label>${esc(m.away)}<input name="away" aria-label="Score ${esc(m.away)}" inputmode="numeric" type="number" min="0" max="99" step="1" required value="${esc(m.away_score??'')}"></label></div><p class="hint">First to ${Number(m.first_to)} ${m.unit==='sets'?'sets':'legs'}. Je handmatige uitslag blijft behouden als de bron afwijkt.</p><label class="choice"><input type="checkbox" name="verified" required>Ik heb gecontroleerd dat de wedstrijd is afgelopen en deze eindstand klopt.</label><p role="status"></p><div class="toolbar"><button class="btn" type="submit">Uitslag opslaan</button><button class="ghost" type="button" data-result-cancel>Annuleren</button></div></form>`;
 const form=host.querySelector('form'),message=form.querySelector('[role=status]');let busy=false;
 form.oninput=()=>host.dataset.koDirty='true';
 form.querySelector('[data-result-cancel]').onclick=()=>{host.dataset.koDirty='false';host.replaceChildren();host.dispatchEvent(new CustomEvent('result-cancel',{bubbles:true}));};
 form.onsubmit=async e=>{
  e.preventDefault();if(busy||!form.reportValidity())return;
  const home=Number(form.elements.home.value),away=Number(form.elements.away.value),ft=m.first_to;
  if(![home,away].every(x=>Number.isInteger(x)&&x>=0&&x<=99)||!((home===ft&&away<ft)||(away===ft&&home<ft))){message.textContent='De winnaar moet exact '+ft+' halen; de andere score moet lager zijn.';return;}
  if(!sourceResultAllowed(m,tournament)){message.textContent='Uitslaginvoer is nog niet beschikbaar voor deze wedstrijd.';return;}
  if(!confirm(`Uitslag opslaan: ${m.home} ${home} – ${away} ${m.away}? Punten en doorplaatsing worden bijgewerkt.`))return;
  busy=true;form.querySelectorAll('input,button').forEach(x=>x.disabled=true);message.textContent='Uitslag opslaan…';
  try{const r=await ctx.supabase.rpc('admin_record_source_result',{p_match:m.id,p_home:home,p_away:away});if(r.error)throw r.error;if(!alive())return;host.dataset.koDirty='false';message.textContent='Uitslag opgeslagen.';await onSaved?.();}
  catch(error){if(alive())message.textContent='Niet opgeslagen: '+error.message;}
  finally{busy=false;if(alive())form.querySelectorAll('input,button').forEach(x=>x.disabled=false);}
 };
 form.elements.home.focus();
}
export async function loadSourceResults(host,ctx,id,onSaved){
 const alive=()=>host.isConnected&&ctx.isCurrent()&&!ctx.signal?.aborted;let round='',status='pending',revision=0;
 host.oninput=e=>e.stopPropagation();
 async function read(){
  const version=++revision,r=await ctx.supabase.rpc('get_knockout_schema',{p_id:id});if(!alive()||version!==revision)return;if(r.error)throw r.error;
  const data=r.data;if(!data?.score_source?.locked)return;
  host.innerHTML='<details class="admin-fold" open><summary>Handmatige uitslagen</summary><p class="hint">Bij een bronstoring kun je hier de eindstand invoeren. Correcties die de winnaar veranderen kunnen worden geblokkeerd als de vervolgwedstrijd al voorspellingen heeft of gestart is.</p><div class="toolbar"><label>Ronde<select data-result-round><option value="">Alle rondes</option>'+data.rounds.map(r=>`<option value="${r.order}">${esc(r.name)}</option>`).join('')+'</select></label><label>Uitslagen<select data-result-status><option value="pending">Nog in te vullen</option><option value="all">Alle wedstrijden</option></select></label></div><p role="status" data-result-feedback></p><div data-source-result-list class="stack"></div></details>';
  const roundSelect=host.querySelector('[data-result-round]'),statusSelect=host.querySelector('[data-result-status]');roundSelect.value=round;statusSelect.value=status;
  function draw(){
   const matches=data.matches.filter(m=>!m.bye&&(!round||m.round===Number(round))&&(status==='all'||m.home_score==null));
   const list=host.querySelector('[data-source-result-list]');list.innerHTML=matches.map(m=>`<article class="result-entry" data-source-result="${esc(m.id)}"><strong>${esc(m.home)} – ${esc(m.away)}</strong><span>${m.home_score!=null?esc(m.home_score)+' – '+esc(m.away_score):'Nog geen uitslag'}</span><button type="button" class="ghost mini" ${sourceResultAllowed(m,data)?'':'disabled'}>${m.home_score!=null?'Uitslag aanpassen':'Uitslag invullen'}</button>${!sourceResultAllowed(m,data)?'<span class="hint">Beschikbaar na de start, met twee bekende deelnemers.</span>':''}<div data-source-result-form></div></article>`).join('')||'<p>Geen wedstrijden binnen deze selectie.</p>';
   list.querySelectorAll('[data-source-result]').forEach(card=>{const button=card.querySelector('button'),formHost=card.querySelector('[data-source-result-form]'),m=matches.find(m=>m.id===card.dataset.sourceResult);button.onclick=()=>{button.hidden=true;resultForm(formHost,ctx,data,m,async()=>{await read();if(alive())host.querySelector('[data-result-feedback]').textContent='Uitslag opgeslagen; punten en schema bijgewerkt.';onSaved?.();});};card.addEventListener('result-cancel',()=>button.hidden=false);});
  }
  const select=()=>{if(host.querySelector('[data-ko-dirty="true"]')&&!confirm('Niet-opgeslagen uitslag laten vervallen?')){roundSelect.value=round;statusSelect.value=status;return;}round=roundSelect.value;status=statusSelect.value;draw();};roundSelect.onchange=select;statusSelect.onchange=select;draw();
 }
 try{await read();}catch(error){if(alive())host.textContent='Handmatige uitslagen laden mislukt: '+error.message;}
}
export async function showSourceResultDialog(ctx,id,matchId,onSaved){
 document.getElementById('source-result-dialog')?.close();
 const dialog=document.createElement('dialog');dialog.id='source-result-dialog';dialog.className='panel stack';dialog.style.cssText='width:min(520px,calc(100% - 24px));max-height:85vh;overflow:auto;margin:auto';dialog.innerHTML='<h2>Handmatige uitslag</h2><div data-source-dialog-form>Laden…</div><button type="button" class="ghost" data-close>Sluiten</button>';document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.querySelector('[data-close]').onclick=()=>dialog.close();dialog.addEventListener('result-cancel',()=>dialog.close());dialog.showModal();
 try{const r=await ctx.supabase.rpc('get_knockout_schema',{p_id:id});if(!dialog.isConnected||!ctx.isCurrent())return;if(r.error)throw r.error;const m=r.data?.matches.find(m=>m.id===matchId);if(!m||!sourceResultAllowed(m,r.data))throw Error('Uitslaginvoer nog niet beschikbaar.');resultForm(dialog.querySelector('[data-source-dialog-form]'),ctx,r.data,m,async()=>{dialog.close();await onSaved?.();});}
 catch(error){if(dialog.isConnected)dialog.querySelector('[data-source-dialog-form]').textContent=error.message;}
}
