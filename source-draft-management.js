const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const when=x=>x?new Intl.DateTimeFormat('nl-NL',{dateStyle:'short',timeStyle:'short'}).format(new Date(x)):'nog niet uitgevoerd';
export function sourceDraftPanel(t){
 const s=t.score_source;if(!s?.locked||!['draft','announced'].includes(t.status))return '';
 const ready=s.setup_state==='ready',pending=s.setup_pending;
 return `<section class="notice stack" data-source-lifecycle><strong>${pending?(ready?'Loting beschikbaar — klaar voor controle':s.setup_state==='error'?'Broncontrole mislukt':'Wachten op de eerste ronde'):'Publicatie voorbereiden'}</strong><p class="info-text">${esc(pending?(s.setup_error||s.setup_reason||(s.setup_state==='queued'?'De broncontrole staat ingepland.':'De eerste ronde is nog niet volledig bekend.')):'Controleer schema en punten voordat je publiceert.')}</p>${pending?`<p class="info-text">Laatste controle: ${esc(when(s.setup_checked_at))}<br>Volgende controle: ${esc(when(s.setup_next_check_at))} · elke 24 uur</p>`:''}<div class="toolbar">${t.status==='draft'?`<button type="button" class="ghost mini" data-source-action="announce" ${t.start&&t.end?'':'disabled'}>Voorvertoning tonen</button>`:'<button type="button" class="ghost mini" data-source-action="draft">Terug naar concept</button>'}${!pending||ready?'<button type="button" class="btn mini" data-review-source>Loting en spelvorm controleren</button>':''}</div><div data-source-review></div><p role="status" data-lifecycle-message></p></section>`;
}
export function bindSourceDraft(detail,t,ctx){
 const host=detail.querySelector('[data-source-lifecycle]');if(!host)return;
 const message=host.querySelector('[data-lifecycle-message]'),review=host.querySelector('[data-source-review]');let working=false;
 const alive=()=>ctx.alive()&&host.isConnected;
 async function action(kind,firstTo=null){
  if(working||ctx.isBusy())return;if(detail.dataset.koDirty==='true'){message.textContent='Sla eerst de gewijzigde gegevens op.';return;}
  working=true;ctx.onBusy(true);host.querySelectorAll('button').forEach(b=>b.disabled=true);message.textContent='Opslaan…';
  try{await ctx.rpc('admin_source_lifecycle',{p_id:t.id,p_action:kind,p_group_first_to:firstTo});if(!alive())return;await ctx.refresh();ctx.onSaved?.();}catch(e){if(alive())message.textContent=e.message;}finally{working=false;ctx.onBusy(false);if(alive()){host.querySelectorAll('button').forEach(b=>b.disabled=false);if(!t.start||!t.end)host.querySelector('[data-source-action="announce"]')?.setAttribute('disabled','');}}
 }
 host.querySelectorAll('[data-source-action]').forEach(b=>b.onclick=()=>action(b.dataset.sourceAction));
 host.querySelector('[data-review-source]')?.addEventListener('click',async()=>{
  if(working||ctx.isBusy())return;working=true;message.textContent='Loting laden…';
  try{const s=t.score_source.setup_pending?await ctx.rpc('admin_source_draft_preview',{p_id:t.id}):await ctx.rpc('get_knockout_schema',{p_id:t.id});if(!alive())return;if(!s)throw Error('Nog geen brongegevens beschikbaar. Controleer de bron opnieuw.');
   review.innerHTML=`<details open class="admin-fold"><summary>Controle vóór publicatie</summary><div class="stack"><p class="info-text">Controleer ook de puntenberekening hieronder. Publiceren opent alleen wedstrijden met bekende spelers en een geldige voorspeldeadline.</p>${s.rounds.map(r=>`<section><h4>${esc(r.name)} · ${r.first_to?'First to '+esc(r.first_to):'Spelvorm nog instellen'}</h4><ul class="info-text">${s.matches.filter(m=>m.round===r.order).map(m=>`<li>${m.group?esc(m.group)+' · ':''}${esc(m.home_name||m.home||'NNB')} – ${esc(m.away_name||m.away||'NNB')}</li>`).join('')}</ul></section>`).join('')}<form data-publish-source class="stack">${t.score_source.format_required?'<label>Groepsfase: first to (ontbreekt in de bron)<input name="firstTo" type="number" min="1" max="99" step="1" required></label>':''}<button class="btn mini">Publiceren</button></form></div></details>`;
   review.querySelector('form').onsubmit=e=>{e.preventDefault();if(!e.target.reportValidity())return;const first=e.target.elements.firstTo;action('publish',first?Number(first.value):null);};message.textContent='';
  }catch(e){if(alive())message.textContent=e.message;}finally{working=false;}
 });
}
