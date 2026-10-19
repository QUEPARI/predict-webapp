import {scoreSourceFields,bindScoreSource,invokeMastercaller} from './score-source.js?v=mastercaller-lock-20261019';
import {roundTable,readRoundTable,unitSelect,roundNames} from './round-settings.js?v=refinements-20261017';
import {layoutBracket} from './bracket.js?v=hub-20261017';
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tournamentLabel=s=>({draft:'Concept',announced:'Vooraankondiging',published:'Gepubliceerd',active:'Actief',completed:'Afgerond',archived:'Gepauzeerd / archief'}[s]||s);
export const dutchTime=value=>value?new Intl.DateTimeFormat('nl-NL',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Amsterdam'}).format(new Date(value)):'Nog niet bekend';
export function dutchInput(value){
  if(!value)return '';
  const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Amsterdam',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(value)).map(x=>[x.type,x.value]));
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}
export function dutchToUTC(value){
  if(!value)return null;
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value))throw Error('Ongeldige datum of tijd');
  const wall=Date.parse(value+'Z'),found=[];
  for(const offset of [60,120]){const candidate=new Date(wall-offset*60000).toISOString();if(dutchInput(candidate)===value)found.push(candidate);}
  if(found.length!==1)throw Error(found.length?'Deze tijd komt tweemaal voor door wintertijd. Kies een ondubbelzinnige tijd.':'Deze tijd bestaat niet door de overgang naar zomertijd, of de datum is ongeldig.');
  return found[0];
}
export function knockoutStatus(m,now=Date.now()){
  if(m.bye)return 'Vrijstelling';
  if(m.status==='finished')return 'Afgerond';
  if(m.status==='cancelled')return 'Geannuleerd';
  if(m.status==='postponed')return 'Uitgesteld';
  if(m.status==='live')return 'Uitslag nodig';
  if(m.names_missing||!m.home_slot||!m.away_slot||!m.start||!m.unit||(['sets','legs'].includes(m.unit)&&!m.first_to))return 'Nog aanvullen';
  if(m.status==='live'||Date.parse(m.start)<=now)return 'Uitslag nodig';
  return m.enabled?'Gepland · voorspellen open':'Gepland · voorspellen gesloten';
}
export function predictionState(m,t,now=Date.now()){
 let reason='';
 if(m.bye)reason='vrijstelling';
 else if(m.status==='finished')reason='wedstrijd afgerond';
 else if(m.status==='cancelled')reason='wedstrijd geannuleerd';
 else if(m.status==='postponed')reason='wedstrijd uitgesteld';
 else if(m.status==='live'||m.actual_start)reason='wedstrijd gestart';
 else if(m.names_missing||!m.home_slot||!m.away_slot)reason='tegenstander of naam nog onbekend';
 else if(!m.start)reason='begintijd ontbreekt';
 else if(Date.parse(m.start)<=now)reason='deadline verstreken';
 else if(!['published','active'].includes(t))reason='toernooi niet vrijgegeven';
 else if(m.needs_review||!m.unit||(['legs','sets'].includes(m.unit)&&!m.first_to))reason='wedstrijdgegevens nog aanvullen';
 else if(!m.enabled)reason='door beheerder gesloten';
 return {open:!reason,label:reason?'Voorspellen gesloten — '+reason:'Voorspellen open'};
}
const won=(m,side)=>m.status==='finished'&&(m.winner_slot!=null?m.winner_slot===m[side+'_slot']:side==='home'?m.home_score>m.away_score:m.away_score>m.home_score);
const person=(m,side)=>`<div class="ko-person ${won(m,side)?'ko-winner':''}"><span>${esc(m[side+'_slot']||'—')}.</span><span>${esc(m[side])}${won(m,side)?'<i class="winner-mark" aria-label="Winnaar">✓</i>':''}</span>${m[side+'_score']!=null?`<b>${m[side+'_score']}</b>`:''}</div>`;
const alive=(target,ctx)=>target.isConnected&&!ctx.signal.aborted&&ctx.isCurrent();
export async function loadKnockoutSchema(target,ctx,id,prefetched){
  try{
    const r=prefetched?{data:prefetched}:await ctx.supabase.rpc('get_knockout_schema',{p_id:id});if(!alive(target,ctx))return;if(r.error)throw r.error;
    if(!r.data){target.textContent='Voor dit bestaande toernooi is nog geen knock-outschema ingericht. Bestaande wedstrijden staan hieronder.';return;}
    drawSchema(target,r.data);return r.data;
  }catch(e){if(alive(target,ctx))target.textContent='Schema laden mislukt: '+e.message;}
}
function drawSchema(target,data,admin=false){
 target.innerHTML=`<h2>Volledig toernooischema</h2><div class="ko-bracket compact-public">${data.rounds.map(r=>`<section class="stack ko-round"><h3>${esc(r.name)}</h3>${data.matches.filter(m=>m.round===r.order&&!m.bye).map(m=>`<article class="panel ko-node" data-node="${esc(m.id)}">${person(m,'home')}${person(m,'away')}<small>${esc(m.start?new Intl.DateTimeFormat('nl-NL',{dateStyle:'short',timeStyle:'short',...(admin?{timeZone:'Europe/Amsterdam'}:{})}).format(new Date(m.start)):'Nog niet bekend')}</small></article>`).join('')}</section>`).join('')}</div>`;
 layoutBracket(target.querySelector('.ko-bracket'),data);
}
export async function loadKnockoutAdmin(target,ctx){
  target.innerHTML='<h2>Knock-outtoernooien</h2><p>Maak een toernooi handmatig of laat Mastercaller (test) het schema, de planning en uitslagen leveren.</p><div id="ko-create"></div><label for="ko-tour">Toernooi beheren</label><select id="ko-tour"><option value="">Kies een knock-outtoernooi</option></select><p id="ko-message" role="status"></p><div id="ko-editor" class="stack"></div>';
  const $=x=>target.querySelector('#'+x),msg=$('ko-message');
  const rpc=async(name,args)=>{const r=await ctx.supabase.rpc(name,args);if(r.error)throw Error(r.error.message);return r.data;};
  let catalog,data,currentId='',busy=false,tickTimer,requestedId='';
  document.addEventListener('predict-knockout-select',event=>{if(busy||dirty()&&!event.detail?.confirmed&&!confirm('Niet-opgeslagen schemawijzigingen laten vervallen?'))return;requestedId=typeof event.detail==='object'?event.detail.id:event.detail;if(catalog?.tournaments.some(t=>t.id===requestedId)){currentId=requestedId;$('ko-tour').value=currentId;read().catch(e=>msg.textContent=e.message);scopeEditor();}},{signal:ctx.signal});
  ctx.signal.addEventListener('abort',()=>clearInterval(tickTimer),{once:true});
  function scopeEditor(){const scoped=!!target.dataset.tournament;target.classList.toggle('scoped-schema',scoped);$('ko-create').hidden=scoped;$('ko-tour').hidden=scoped;target.querySelector('label[for=ko-tour]').hidden=scoped;}
  const dirty=()=>!!target.querySelector('[data-ko-dirty="true"]');
  window.addEventListener('beforeunload',e=>{if(dirty()){e.preventDefault();e.returnValue='';}},{signal:ctx.signal});
  async function refreshCatalog(){catalog=await rpc('knockout_catalog');if(!alive(target,ctx))return;$('ko-tour').innerHTML='<option value="">Kies een knock-outtoernooi</option>'+catalog.tournaments.map(t=>`<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');$('ko-tour').value=currentId;}
  async function read(){
    const id=currentId,next=await rpc('get_knockout_schema',{p_id:id});if(!alive(target,ctx)||id!==currentId)return;data=next;data.matches.forEach(m=>m.names_missing=!!((m.home_slot&&!data.roster[m.home_slot-1])||(m.away_slot&&!data.roster[m.away_slot-1])));renderEditor();
  }
  async function mutate(action,match,values={}){
    if(busy)return;
    const card=match?target.querySelector(`[data-ko-match="${match}"]`):null;
    const say=(text,error=false)=>{const local=match?target.querySelector(`[data-ko-match="${match}"] [data-save-message]`):action==='roster'?target.querySelector('[data-roster-message]'):action==='rounds'?target.querySelector('[data-round-settings-message]'):msg;if(local){local.textContent=text;local.className=error?'error':'success';local.setAttribute('role',error?'alert':'status');}if(error&&local)local.scrollIntoView({block:'nearest'});};
    let written=false;const unsaved=card&&action!=='result'?Object.fromEntries(['home','away','winner'].map(name=>[name,card.querySelector(`[name="${name}"]`)?.value])):null;busy=true;say('Opslaan…');
    const controls=[...target.querySelectorAll('input,select,textarea,button')].map(x=>[x,x.disabled]);controls.forEach(([x])=>x.disabled=true);
    const expanded=[...target.querySelectorAll('#ko-cards details[open]')].map(x=>x.closest('article').dataset.koMatch),filter=$('ko-filter')?.value,round=$('ko-round-filter')?.value;
    try{await rpc('edit_knockout',{p_tournament:currentId,p_action:action,p_match:match,p_values:values});written=true;if(!alive(target,ctx))return;await read();
      if(unsaved){const next=target.querySelector(`[data-ko-match="${match}"]`);Object.entries(unsaved).forEach(([name,value])=>{const field=next?.querySelector(`[name="${name}"]`);if(field&&value!=null)field.value=value;});if(next&&['home','away'].some(name=>{const f=next.querySelector(`[name="${name}"]`);return f&&f.value!==f.defaultValue;}))next.dataset.koDirty='true';}
      expanded.forEach(id=>{const d=target.querySelector(`[data-ko-match="${id}"] details`);if(d)d.open=true;});if(round!=null)$('ko-round-filter').value=round;if(filter){$('ko-filter').value=action==='result'?'all':filter;$('ko-filter').onchange();}
      say('✓ '+({schedule:'Begintijd opgeslagen; actuele status staat bij de wedstrijd',undo_postpone:'Uitstel ongedaan gemaakt; voorspellen blijft gesloten',reset_result:'Uitslag ongedaan gemaakt; voorspellen blijft gesloten',result:'Uitslag opgeslagen',open:'Voorspellen geopend',close:'Voorspellen gesloten',start:'Werkelijke start opgeslagen',postpone:'Uitstel opgeslagen',cancel:'Annulering opgeslagen',roster:'Deelnemersnamen opgeslagen',rounds:'Conceptinstellingen opgeslagen',publish:'Toernooi gepubliceerd'}[action]||'Opgeslagen'));
      if(action==='rounds'&&$('ko-settings'))$('ko-settings').open=true;
      msg.textContent='Opgeslagen.';ctx.onSaved?.();
    }catch(e){if(alive(target,ctx)){say((written?'Opgeslagen, maar opnieuw laden mislukt: ':'Opslaan mislukt: ')+e.message,true);if(card){const field=/reden/i.test(e.message)?card.querySelector('[name=reason]'):/tijd|datum|deadline/i.test(e.message)?card.querySelector('[name=start]'):null;if(field)field.setAttribute('aria-invalid','true');}}}
    finally{busy=false;controls.forEach(([x,disabled])=>{if(x.isConnected)x.disabled=disabled;});}
  }
  function renderEditor(){
    const host=$('ko-editor'),openedFolds=[...host.querySelectorAll('.admin-fold[open]')].map(el=>el.id);
    if(data.score_source?.locked){clearInterval(tickTimer);host.innerHTML='<p class="notice" data-source-readonly>Mastercaller beheert dit toernooi. Schema, deelnemers, planning en uitslagen zijn alleen-lezen.</p><div data-source-schema></div>';drawSchema(host.querySelector('[data-source-schema]'),data,true);return;}
    host.innerHTML=`${['draft','announced'].includes(data.status)?'<button class="btn" id="ko-publish">Publiceren en complete wedstrijden openen</button>':''}<div class="toolbar ko-filters"><label>Status<select id="ko-filter"><option value="pending">Nog af te handelen</option><option value="all">Alle wedstrijden</option><option>Uitslag nodig</option><option>Nog aanvullen</option><option>Afgerond</option><option>Uitgesteld</option></select></label><label>Ronde<select id="ko-round-filter"><option value="">Alle rondes</option>${data.rounds.map(r=>`<option value="${r.order}">${esc(r.name)}</option>`).join('')}</select></label></div><div id="ko-cards" class="stack"></div><div id="ko-full"></div>`;
    {
      const editable=['draft','announced'].includes(data.status);
      const settings=document.createElement('details');settings.id='ko-settings';settings.className='admin-fold';
      const values=data.rounds.map(r=>{const m=data.matches.find(m=>m.round===r.order)||{};return {...r,unit:r.unit||m.unit||'legs',first_to:r.first_to===undefined?m.first_to:r.first_to};}),units=[...new Set(values.map(r=>r.unit))];
      settings.innerHTML=`<summary>Ronde-instellingen en punten</summary><p class="hint">Tussentijds opslaan kan met lege velden. Vul ze vóór publiceren in.</p><form class="stack"><div class="two"><label>Van (Nederland)<input name="start" type="datetime-local" value="${esc(dutchInput(data.start))}"></label><label>Tot (Nederland)<input name="end" type="datetime-local" value="${esc(dutchInput(data.end))}"></label></div><label>Puntenmethode<select name="mode"><option value="replacement">Exacte score vervangt winnaarspunten</option><option value="additive">Exacte score telt bovenop winnaarspunten</option></select></label>${unitSelect(units[0],units.length>1)}${roundTable(values,{goals:units[0]==='goals'})}<button class="btn">Conceptinstellingen opslaan</button><p role="status" data-round-settings-message></p></form>`;
      const form=settings.querySelector('form');if(!editable){settings.querySelector('.hint').textContent='De ronde-instellingen staan vast na publicatie.';form.querySelectorAll('input,select,button').forEach(el=>el.disabled=true);}form.elements.mode.value=data.scoring_mode||'replacement';form.oninput=()=>form.dataset.koDirty='true';
      form.onsubmit=e=>{e.preventDefault();if(!form.reportValidity())return;if([...target.querySelectorAll('[data-ko-dirty="true"]')].some(el=>el!==form)){msg.textContent='Sla eerst de andere gewijzigde gegevens op.';return;}try{mutate('rounds',null,{start:dutchToUTC(form.elements.start.value),end:dutchToUTC(form.elements.end.value),mode:form.elements.mode.value,rules:readRoundTable(form,form.querySelector('[data-tournament-unit]').value).map(r=>({...r,exact_points:r.exact_points}))});}catch(error){form.querySelector('[data-round-settings-message]').textContent=error.message;}};
      host.querySelector('#ko-filter').closest('.ko-filters').before(settings);
      if(data.publication_issues?.length){const issues=document.createElement('div');issues.className='notice';issues.setAttribute('role','status');issues.innerHTML='<strong>Nog invullen vóór publiceren</strong><ul>'+data.publication_issues.map(issue=>'<li>'+esc(issue)+'</li>').join('')+'</ul>';settings.before(issues);}
    }
    $('ko-full').remove();
    {
      const rosterForm=document.createElement('form');rosterForm.className='stack';rosterForm.id='ko-roster';
      const seen=new Set();
      const entrant=(slot,label,winner=false)=>{
        if(!slot||seen.has(slot))return `<div class="ko-person ${winner?'ko-winner':''}"><span>${slot||'—'}.</span><span>${esc(label)}</span></div>`;
        seen.add(slot);
        return `<label class="ko-person ${winner?'ko-winner':''}"><span>${slot}.</span><input aria-label="${slot}. Naam" data-slot="${slot}" maxlength="80" value="${esc(data.roster[slot-1])}" placeholder="Naam"></label>`;
      };
      rosterForm.innerHTML=`<h3>Namen invullen in het schema</h3><p>Vul spelers of teams op hun officiële lotingsplek in. Een winnaarverwijzing wordt automatisch ingevuld na de uitslag. Lege plekken mag je tussentijds opslaan. Naamcorrecties wijzigen geen schemaplekken, scores of voorspellingen.</p><div class="ko-bracket">${data.rounds.map(r=>`<section class="stack ko-round"><h4>${esc(r.name)}</h4>${data.matches.filter(m=>m.round===r.order&&!m.bye).map(m=>`<article class="panel ko-node" data-node="${esc(m.id)}">${entrant(m.home_slot,m.home,won(m,'home'))}${entrant(m.away_slot,m.away,won(m,'away'))}</article>`).join('')}</section>`).join('')}</div><button type="submit" class="btn">Deelnemersnamen opslaan</button><p data-roster-message role="status"></p>`;
      // Preserve edit access if a historical bracket contains an unusual slot arrangement.
      if(seen.size!==data.roster.length){for(let slot=1;slot<=data.roster.length;slot++){if(!seen.has(slot))rosterForm.insertAdjacentHTML('beforeend',entrant(slot,''));}}
      const rosterSection=document.createElement('details');rosterSection.className='admin-fold';rosterSection.id='ko-roster-section';rosterSection.innerHTML='<summary>Namen invullen in het schema</summary>';rosterForm.querySelector('h3').remove();rosterSection.append(rosterForm);host.prepend(rosterSection);layoutBracket(rosterForm.querySelector('.ko-bracket'),data);rosterForm.oninput=()=>rosterForm.dataset.koDirty='true';
      rosterForm.onsubmit=e=>{e.preventDefault();if([...target.querySelectorAll('[data-ko-dirty="true"]')].some(x=>x!==rosterForm)&&!confirm('Andere niet-opgeslagen wijzigingen laten vervallen?'))return;
        const names=[...data.roster];rosterForm.querySelectorAll('[data-slot]').forEach(input=>names[Number(input.dataset.slot)-1]=input.value.trim());mutate('roster',null,{names});};
    }
    const now=Date.parse(data.server_now||new Date().toISOString()),receivedAt=Date.now();
    const cards=$('ko-cards'),matchSection=document.createElement('details');matchSection.className='admin-fold';matchSection.id='ko-matches-section';matchSection.innerHTML='<summary>Wedstrijden</summary>';const filter=$('ko-filter').closest('.ko-filters');filter.before(matchSection);matchSection.append(filter,cards);
    const groups=new Map(),ordered=[...data.matches].sort((a,b)=>a.round-b.round||(a.start?Date.parse(a.start):Infinity)-(b.start?Date.parse(b.start):Infinity)||a.number-b.number);
    for(const m of ordered){
      if(!groups.has(m.round)){const group=document.createElement('section');group.className='manage-round stack';group.dataset.manageRound=m.round;group.innerHTML='<h4>'+esc(data.rounds.find(r=>r.order===m.round)?.name||'Ronde '+m.round)+'</h4>';groups.set(m.round,group);cards.append(group);}
      const card=document.createElement('article');card.className='panel ko-match';card.dataset.koMatch=m.id;card.dataset.koStatus=knockoutStatus(m,now);
      const state=predictionState(m,data.status,now);
      card.innerHTML=`<details><summary><small class="round-tag">${esc(data.rounds.find(r=>r.order===m.round)?.name||'Ronde '+m.round)}</small><strong>${esc(m.home)} – ${esc(m.away)}</strong><span>${m.home_score!=null?m.home_score+'–'+m.away_score:esc(dutchTime(m.start))}</span><span data-ko-status>${esc(knockoutStatus(m,now))}</span><span data-ko-open class="pill ${state.open?'is-open':'is-closed'}">${esc(state.label)}</span><span class="edit-hint">Bewerken</span></summary></details><p data-save-message role="status"></p>`;
      groups.get(m.round).append(card);if(m.bye){card.hidden=true;continue;}
      const form=document.createElement('form');form.className='stack ko-match-form';form.noValidate=true;
      form.innerHTML=`<div class="schedule-compact"><label>Begintijd (Nederland)<input name="start" type="datetime-local" value="${esc(dutchInput(m.start))}"></label><button class="ghost" ${m.status==='finished'?'disabled title="Maak eerst de uitslag ongedaan"':''}>Begintijd opslaan</button></div><div class="toolbar"><button type="button" class="ghost" data-action="open">Voorspellen vrijgeven / heropenen</button><button type="button" class="ghost" data-action="close">Direct sluiten</button><button type="button" class="ghost" data-action="start">Werkelijk gestart</button><button type="button" class="ghost" data-action="postpone">Uitstellen</button>${m.status==='postponed'?'<button type="button" class="ghost" data-action="undo_postpone">Uitstel ongedaan maken</button>':''}<button type="button" class="ghost" data-action="cancel">Annuleren</button>${m.status==='finished'?'<button type="button" class="ghost" data-action="reset_result">Uitslag ongedaan maken</button>':''}</div>`;
      card.querySelector('details').append(form);
      const say=(text,field)=>{const message=card.querySelector('[data-save-message]');message.textContent=text;message.className='error';message.setAttribute('role','alert');if(field){field.setAttribute('aria-invalid','true');field.focus();}message.scrollIntoView({block:'nearest'});};
      form.oninput=()=>{card.dataset.koDirty='true';form.querySelectorAll('[aria-invalid]').forEach(x=>x.removeAttribute('aria-invalid'));};form.onchange=form.oninput;
      const known=!!m.home_slot&&!!m.away_slot&&!m.names_missing;
      const terminal=['finished','cancelled'].includes(m.status);
      const buttons=form.querySelectorAll('[data-action]');buttons.forEach(b=>{if(b.dataset.action==='open')b.disabled=!known||terminal||!m.start||Date.parse(m.start)<=now||!['published','active'].includes(data.status)||!!m.actual_start||m.needs_review;else if(b.dataset.action==='start')b.disabled=!known||terminal||!!m.actual_start;else if(b.dataset.action==='reset_result')b.disabled=m.status!=='finished';else b.disabled=m.status==='finished';});
      function onlyThisDraft(){return ![...target.querySelectorAll('[data-ko-dirty="true"]')].some(x=>x!==card)||confirm('Andere niet-opgeslagen wijzigingen laten vervallen?');}
      form.onsubmit=e=>{e.preventDefault();if(!onlyThisDraft())return;try{const start=dutchToUTC(form.elements.start.value);if(!start){say('Vul een datum en tijd in.',form.elements.start);return;}if(!form.reportValidity())return;mutate('schedule',m.id,{start,unit:m.unit,first_to:m.first_to});}catch(error){say(error.message,form.elements.start);}};
      buttons.forEach(b=>b.onclick=()=>{if(onlyThisDraft()&&confirm(b.textContent+'?'))mutate(b.dataset.action,m.id,{});});
    }
    $('ko-filter').onchange=()=>{cards.querySelectorAll('article').forEach(card=>{const m=data.matches.find(m=>m.id===card.dataset.koMatch),value=$('ko-filter').value,state=knockoutStatus(m,Date.now()+(now-receivedAt));card.hidden=!!m.bye||($('ko-round-filter').value!==''&&String(m.round)!==$('ko-round-filter').value)||(value==='pending'?!predictionState(m,data.status,Date.now()+(now-receivedAt)).open&&!['Uitslag nodig','Nog aanvullen','Uitgesteld'].includes(state):value!=='all'&&state!==value);});groups.forEach(group=>group.hidden=![...group.querySelectorAll('article')].some(c=>!c.hidden));};
    $('ko-round-filter').onchange=()=>$('ko-filter').onchange();
    openedFolds.forEach(id=>{const el=$(id);if(el)el.open=true;});
    $('ko-filter').onchange();
    clearInterval(tickTimer);const clockOffset=now-Date.now();
    tickTimer=setInterval(()=>{
      if(!alive(target,ctx)){clearInterval(tickTimer);return;}
      [...cards.querySelectorAll('article')].forEach(card=>{const m=data.matches.find(m=>m.id===card.dataset.koMatch);const state=knockoutStatus(m,Date.now()+clockOffset);card.dataset.koStatus=state;card.querySelector('[data-ko-status]').textContent=state;const p=predictionState(m,data.status,Date.now()+clockOffset);card.querySelector('[data-ko-open]').textContent=p.label;card.querySelector('[data-ko-open]').className='pill '+(p.open?'is-open':'is-closed');if(!p.open&&Date.parse(m.start)<=Date.now()+clockOffset){const b=card.querySelector('[data-action=open]');if(b)b.disabled=true;}});
      $('ko-filter').onchange();
    },1000);
    if($('ko-publish'))$('ko-publish').onclick=()=>{if((!dirty()||confirm('Niet-opgeslagen wijzigingen laten vervallen?'))&&confirm('Publiceren vergrendelt de puntentelling en opent complete toekomstige wedstrijden. Doorgaan?'))mutate('publish',null);};
  }
  try{
    await refreshCatalog();if(!alive(target,ctx))return;
    const create=$('ko-create');create.innerHTML=`<details><summary>Nieuw knock-outtoernooi</summary><form class="stack"><label>Toernooinaam<input name="name" required maxlength="120"></label><label>Sport<select name="sport">${catalog.sports.map(s=>`<option value="${esc(s.id)}" data-slug="${esc(s.slug)}">${esc(s.name)}</option>`).join('')}</select></label>${scoreSourceFields()}<div data-mc-create-options hidden><p class="hint">Deelnemers, ronden, spelvorm en beschikbare planning komen uit de uitslagen- en bracket-tab. Nieuwe eindstanden worden automatisch verwerkt.</p><div class="two"><label>Punten juiste winnaar<input name="mcWinner" type="number" min="0" max="1000" value="1"></label><label>Punten exacte score<input name="mcExact" type="number" min="0" max="1000" value="3"></label></div></div><div data-manual-create class="stack"><label>Toernooisjabloon<select name="template"></select></label><label>Deelnemers<select name="kind"><option value="players">Spelers</option><option value="teams">Teams</option></select></label><label>Aantal deelnemers<input name="count" type="number" min="2" max="128" value="8" required></label><p class="hint">Je maakt eerst een concept. Startdatum, first-to en punten mogen nog leeg blijven; die zijn verplicht bij publiceren. Vul namen later op de juiste schemaplek in.</p><div class="two"><label>Van (Nederland)<input name="start" type="datetime-local"></label><label>Tot (Nederland)<input name="end" type="datetime-local"></label></div><label>Status<select name="publication"><option value="draft">Concept</option><option value="announced">Vooraankondiging</option></select></label><label>Puntenmethode<select name="mode"><option value="replacement">Exacte score vervangt winnaarspunten</option><option value="additive">Exacte score telt bovenop winnaarspunten</option></select></label><div data-rounds class="stack"></div><label>Naam eigen sjabloon<input name="templateName" maxlength="80" placeholder="Bijvoorbeeld clubkampioenschap"></label><button type="button" data-save-template class="ghost">Format als sjabloon bewaren</button></div><p data-create-message role="status"></p><button type="submit" class="btn">Leeg toernooischema maken</button></form></details>`;
    const f=create.querySelector('form'),rules=f.querySelector('[data-rounds]'),feedback=f.querySelector('[data-create-message]');
    let chosenTemplate=null;const bindSource=bindScoreSource(f,()=>f.elements.sport.selectedOptions[0]?.dataset.slug==='darts');
    function updateSource(){bindSource();const automatic=f.elements.scoreSource.value==='mastercaller_test';const manual=f.querySelector('[data-manual-create]');manual.hidden=automatic;manual.querySelectorAll('input,select,button').forEach(el=>el.disabled=automatic);f.querySelector('[data-mc-create-options]').hidden=!automatic;f.elements.name.required=!automatic;f.querySelector('button[type=submit]').textContent=automatic?'Toernooi uit Mastercaller maken':'Leeg toernooischema maken';}
    f.elements.scoreSource.addEventListener('change',updateSource);
    function freezeCreate(flag){f.querySelectorAll('input,select,button').forEach(el=>el.disabled=flag);if(!flag){updateSource();if(f.elements.scoreSource.value==='manual')f.elements.kind.disabled=!!chosenTemplate;}}
    function updateRounds(){
      const count=Number(f.elements.count.value);if(!Number.isInteger(count)||count<2||count>128){rules.textContent='Kies 2–128 deelnemers';return;}
      const darts=f.elements.sport.selectedOptions[0]?.dataset.slug==='darts',nr=Math.ceil(Math.log2(count));
      rules.innerHTML=unitSelect(darts?'legs':'goals')+roundTable(roundNames(count),{goals:!darts});
    }
    function templateOptions(){
      const darts=f.elements.sport.selectedOptions[0]?.dataset.slug==='darts';
      f.elements.template.innerHTML='<option value="">Vrij knock-outformat</option>'+(catalog.templates||[]).filter(t=>t.sport_id===f.elements.sport.value).map(t=>`<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');
      updateSource();chosenTemplate=null;f.elements.count.readOnly=false;f.elements.kind.disabled=false;updateRounds();
    }
    function readRules(){return readRoundTable(rules,rules.querySelector('[data-tournament-unit]')?.value);}
    f.elements.template.onchange=()=>{
      chosenTemplate=(catalog.templates||[]).find(t=>t.id===f.elements.template.value);
      f.elements.count.readOnly=!!chosenTemplate;
      if(chosenTemplate){f.elements.count.value=chosenTemplate.participant_count;f.elements.kind.value=chosenTemplate.participant_kind;if(chosenTemplate.scoring_mode)f.elements.mode.value=chosenTemplate.scoring_mode;}
      f.elements.kind.disabled=!!chosenTemplate;updateRounds();
      if(chosenTemplate){const units=[...new Set(chosenTemplate.rules.map(r=>r.unit))],unit=units[0]||'legs';rules.innerHTML=unitSelect(unit,units.length>1)+roundTable(roundNames(Number(f.elements.count.value)).map((r,i)=>({...r,...chosenTemplate.rules[i]})),{goals:unit==='goals'});}
    };
    f.elements.publication.onchange=()=>{f.elements.start.required=f.elements.end.required=f.elements.publication.value==='announced';};
    document.addEventListener('predict-knockout-templates-changed',async()=>{try{const chosen=f.elements.template.value;await refreshCatalog();if(!alive(target,ctx))return;if(create.dataset.koDirty!=='true')templateOptions();else{const options=f.elements.template;const oldValue=options.value;const fragment=(catalog.templates||[]).filter(t=>t.sport_id===f.elements.sport.value&&!options.querySelector(`option[value="${t.id}"]`));fragment.forEach(t=>options.add(new Option(t.name,t.id)));options.value=oldValue;}}catch(error){feedback.textContent=error.message;}},{signal:ctx.signal});
    templateOptions();f.elements.count.onchange=()=>{if(!chosenTemplate)updateRounds();};f.elements.sport.onchange=templateOptions;
    f.querySelector('[data-save-template]').onclick=async()=>{
      if(busy)return;
      if(!f.elements.templateName.value.trim()){feedback.textContent='Vul een naam voor het sjabloon in.';return;}
      if(readRules().some(r=>r.winner_points==null||r.exact_points==null||(['legs','sets'].includes(r.unit)&&r.first_to==null))){feedback.textContent='Vul het volledige formaat en de punten in om een sjabloon te bewaren.';return;}
      if(!Number.isInteger(Number(f.elements.count.value))||Number(f.elements.count.value)<2||Number(f.elements.count.value)>128||![...rules.querySelectorAll('input')].every(input=>input.reportValidity()))return;
      busy=true;freezeCreate(true);
      try{const id=await rpc('save_knockout_template',{p_name:f.elements.templateName.value.trim(),p_sport:f.elements.sport.value,p_kind:f.elements.kind.value,p_count:Number(f.elements.count.value),p_rules:readRules(),p_mode:f.elements.mode.value});await refreshCatalog();if(!alive(target,ctx))return;templateOptions();f.elements.template.value=id;f.elements.template.onchange();feedback.textContent='Sjabloon opgeslagen bij deze sport. Namen en tijden worden niet bewaard.';}
      catch(error){if(alive(target,ctx))feedback.textContent=error.message;}finally{busy=false;if(alive(target,ctx))freezeCreate(false);}
    };
    f.oninput=()=>create.dataset.koDirty='true';
    f.onsubmit=async e=>{
      e.preventDefault();if(busy||!f.reportValidity())return;if(target.querySelector('#ko-editor [data-ko-dirty="true"]')&&!confirm('Niet-opgeslagen wijzigingen in het vorige schema laten vervallen?'))return;
      const roster=Array(Number(f.elements.count.value)).fill('');
      busy=true;freezeCreate(true);
      try{
        const useSource=f.elements.scoreSource.value==='mastercaller_test';
        if(useSource){
          const result=await invokeMastercaller(ctx.supabase,{action:'create',url:f.elements.mastercallerUrl.value.trim(),name:f.elements.name.value.trim(),winner_points:Number(f.elements.mcWinner.value),exact_points:Number(f.elements.mcExact.value)});
          if(!alive(target,ctx))return;create.dataset.koDirty='false';currentId=result.id;await refreshCatalog();await read();create.querySelector('details').open=false;
          document.dispatchEvent(new CustomEvent('predict-admin-schema-created',{detail:{id:result.id,name:result.name}}));scopeEditor();msg.textContent='Mastercaller-toernooi aangemaakt: '+result.participants+' deelnemers. Automatische synchronisatie actief.';ctx.onSaved?.();return;
        }
        const id=await rpc('create_knockout_game',{p_name:f.elements.name.value.trim(),p_sport:f.elements.sport.value,p_kind:f.elements.kind.value,p_roster:roster,p_start:dutchToUTC(f.elements.start.value),p_mode:f.elements.mode.value,
          p_rules:readRules(),p_end:dutchToUTC(f.elements.end.value),p_status:f.elements.publication.value,...(useSource?{p_source:'mastercaller_test',p_url:f.elements.mastercallerUrl.value.trim()}: {})});
        if(!alive(target,ctx))return;create.dataset.koDirty='false';currentId=id;await refreshCatalog();await read();create.querySelector('details').open=false;$('ko-editor').scrollIntoView({block:'start'});document.dispatchEvent(new CustomEvent('predict-admin-schema-created',{detail:{id,name:f.elements.name.value.trim()}}));scopeEditor();msg.textContent='Concept aangemaakt. Namen, tijden en punten kun je later aanvullen.';ctx.onSaved?.();
      }catch(error){if(alive(target,ctx))feedback.textContent=error.message;}finally{busy=false;if(alive(target,ctx))freezeCreate(false);}
    };
    document.dispatchEvent(new CustomEvent('predict-knockout-ready'));
    requestedId=requestedId||target.dataset.tournament||'';scopeEditor();
    if(requestedId&&catalog.tournaments.some(t=>t.id===requestedId)){currentId=requestedId;$('ko-tour').value=currentId;await read();}
    $('ko-tour').onchange=()=>{if(busy||dirty()&&!confirm('Niet-opgeslagen wijzigingen laten vervallen?')){$('ko-tour').value=currentId;return;}currentId=$('ko-tour').value;if(currentId)read().catch(e=>msg.textContent=e.message);else $('ko-editor').textContent='';};
  }catch(e){if(alive(target,ctx))msg.textContent=e.message;}
}
