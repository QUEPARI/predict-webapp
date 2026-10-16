const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tournamentLabel=s=>({draft:'Concept',published:'Gepubliceerd',active:'Actief',completed:'Afgerond',archived:'Gepauzeerd / archief'}[s]||s);
export const dutchTime=value=>value?new Intl.DateTimeFormat('nl-NL',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Amsterdam'}).format(new Date(value)):'Nog in te vullen';
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
export const euroTourRules=()=>[6,6,6,6,7,8].map(first_to=>({unit:'legs',first_to}));
const alive=(target,ctx)=>target.isConnected&&!ctx.signal.aborted&&ctx.isCurrent();
export async function loadKnockoutSchema(target,ctx,id){
  try{
    const r=await ctx.supabase.rpc('get_knockout_schema',{p_id:id});if(!alive(target,ctx))return;if(r.error)throw r.error;
    if(!r.data){target.textContent='Voor dit bestaande toernooi is nog geen knock-outschema ingericht. Bestaande wedstrijden staan hieronder.';return;}
    drawSchema(target,r.data);
  }catch(e){if(alive(target,ctx))target.textContent='Schema laden mislukt: '+e.message;}
}
function drawSchema(target,data){
  target.innerHTML=`<h2>Volledig toernooischema</h2><p>Alle tijden: Nederland. Vrijstellingen leveren geen voorspelpunten op.</p><div class="ko-bracket">${data.rounds.map(r=>`<section class="stack ko-round"><h3>${esc(r.name)}</h3>${data.matches.filter(m=>m.round===r.order).map(m=>`<article class="panel stack"><div class="hint">Wedstrijd ${m.number} · ${esc(knockoutStatus(m))}</div><strong>${esc(m.home)} – ${esc(m.away)}</strong><div>${m.bye?'Automatisch door naar de volgende ronde':esc(dutchTime(m.start))}</div>${m.status==='finished'?`<div>Uitslag ${m.home_score}–${m.away_score}</div>`:''}</article>`).join('')}</section>`).join('')}</div>`;
}
export async function loadKnockoutAdmin(target,ctx){
  target.innerHTML='<h2>Knock-outtoernooien</h2><p>Maak een schema met spelers of teams. Namen en tijden beheer je zelf; er wordt geen sport-API gebruikt.</p><div id="ko-create"></div><label for="ko-tour">Toernooi beheren</label><select id="ko-tour"><option value="">Kies een knock-outtoernooi</option></select><p id="ko-message" role="status"></p><div id="ko-editor" class="stack"></div>';
  const $=x=>target.querySelector('#'+x),msg=$('ko-message');
  const rpc=async(name,args)=>{const r=await ctx.supabase.rpc(name,args);if(r.error)throw Error(r.error.message);return r.data;};
  let catalog,data,currentId='',busy=false,tickTimer,requestedId='';
  document.addEventListener('predict-knockout-select',event=>{if(busy||dirty()&&!confirm('Niet-opgeslagen schemawijzigingen laten vervallen?'))return;requestedId=event.detail;if(catalog?.tournaments.some(t=>t.id===requestedId)){currentId=requestedId;$('ko-tour').value=currentId;read().catch(e=>msg.textContent=e.message);}},{signal:ctx.signal});
  ctx.signal.addEventListener('abort',()=>clearInterval(tickTimer),{once:true});
  const dirty=()=>!!target.querySelector('[data-ko-dirty="true"]');
  window.addEventListener('beforeunload',e=>{if(dirty()){e.preventDefault();e.returnValue='';}},{signal:ctx.signal});
  async function refreshCatalog(){catalog=await rpc('knockout_catalog');if(!alive(target,ctx))return;$('ko-tour').innerHTML='<option value="">Kies een knock-outtoernooi</option>'+catalog.tournaments.map(t=>`<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');$('ko-tour').value=currentId;}
  async function read(){
    const id=currentId,next=await rpc('get_knockout_schema',{p_id:id});if(!alive(target,ctx)||id!==currentId)return;data=next;data.matches.forEach(m=>m.names_missing=!!((m.home_slot&&!data.roster[m.home_slot-1])||(m.away_slot&&!data.roster[m.away_slot-1])));renderEditor();
  }
  async function mutate(action,match,values={}){
    if(busy)return;busy=true;msg.textContent='Opslaan...';target.querySelectorAll('input,select,textarea,button').forEach(x=>x.disabled=true);
    try{await rpc('edit_knockout',{p_tournament:currentId,p_action:action,p_match:match,p_values:values});if(!alive(target,ctx))return;await read();msg.textContent='Opgeslagen.';ctx.onSaved?.();}
    catch(e){if(alive(target,ctx))msg.textContent=e.message;}
    finally{busy=false;if(alive(target,ctx))target.querySelectorAll('input,select,textarea,button').forEach(x=>x.disabled=false);}
  }
  function renderEditor(){
    const host=$('ko-editor');
    host.innerHTML=`<h3>${esc(data.name)}</h3><p>Status: ${esc(tournamentLabel(data.status))}</p>${data.status==='draft'?'<button class="btn" id="ko-publish">Publiceren en complete wedstrijden openen</button>':''}<button class="ghost" id="ko-refresh">Schema vernieuwen</button><p>Bij verstreken begintijd sluit voorspellen automatisch. “Uitslag nodig” is geen bevestiging dat de wedstrijd werkelijk begonnen is. Opslaan van een gewijzigde tijd sluit voorspellingen; vrijgeven/heropenen doe je bewust met een reden.</p><div class="row"><label>Toon<select id="ko-filter"><option value="all">Alle wedstrijden</option><option>Uitslag nodig</option><option>Nog aanvullen</option><option>Afgerond</option></select></label></div><div id="ko-cards" class="stack"></div><div id="ko-full"></div>`;
    drawSchema($('ko-full'),data);
    if(data.status!=='completed'){
      const rosterForm=document.createElement('form');rosterForm.className='stack';rosterForm.id='ko-roster';
      const seen=new Set();
      const entrant=(slot,label)=>{
        if(!slot||seen.has(slot))return `<div>${esc(label)}</div>`;
        seen.add(slot);
        const direct=data.matches.some(m=>m.bye&&m.home_slot===slot);
        return `<label>${direct?'Geplaatste deelnemer · direct in ronde 2':'Deelnemer'} · plek ${slot}<input data-slot="${slot}" maxlength="80" value="${esc(data.roster[slot-1])}" placeholder="Naam invullen"></label>`;
      };
      rosterForm.innerHTML=`<h3>Namen invullen in het schema</h3><p>Vul spelers of teams op hun officiële lotingsplek in. Een winnaarverwijzing wordt automatisch ingevuld na de uitslag. Lege plekken mag je tussentijds opslaan. Namen wijzigen kan zolang er geen voorspellingen, gestarte wedstrijden of ingestelde winnaarsvraag zijn.</p><div class="ko-bracket">${data.rounds.map(r=>`<section class="stack ko-round"><h4>${esc(r.name)}</h4>${data.matches.filter(m=>m.round===r.order&&!m.bye).map(m=>`<article class="panel stack"><strong>Wedstrijd ${m.number}</strong>${entrant(m.home_slot,m.home)}${entrant(m.away_slot,m.away)}</article>`).join('')}</section>`).join('')}</div><button class="btn">Deelnemersnamen opslaan</button>`;
      // Preserve edit access if a historical bracket contains an unusual slot arrangement.
      if(seen.size!==data.roster.length){for(let slot=1;slot<=data.roster.length;slot++){if(!seen.has(slot))rosterForm.insertAdjacentHTML('beforeend',entrant(slot,''));}}
      host.querySelector('h3').after(rosterForm);rosterForm.oninput=()=>rosterForm.dataset.koDirty='true';
      rosterForm.onsubmit=e=>{e.preventDefault();if([...target.querySelectorAll('[data-ko-dirty="true"]')].some(x=>x!==rosterForm)&&!confirm('Andere niet-opgeslagen wijzigingen laten vervallen?'))return;
        const names=[...data.roster];rosterForm.querySelectorAll('[data-slot]').forEach(input=>names[Number(input.dataset.slot)-1]=input.value.trim());mutate('roster',null,{names});};
    }
    const now=Date.parse(data.server_now||new Date().toISOString());
    const cards=$('ko-cards');
    for(const m of data.matches){
      const card=document.createElement('article');card.className='panel stack';card.dataset.koStatus=knockoutStatus(m,now);
      card.innerHTML=`<h4>Wedstrijd ${m.number}: ${esc(m.home)} – ${esc(m.away)}</h4><p data-ko-status>${esc(knockoutStatus(m,now))}</p>`;
      cards.append(card);if(m.bye)continue;
      const form=document.createElement('form');form.className='stack';
      form.innerHTML=`<label>Begintijd (Nederland)<input name="start" type="datetime-local" value="${esc(dutchInput(m.start))}"></label><div class="two"><label>Spelvorm<select name="unit">${(m.unit==='goals'?['goals']:['legs','sets']).map(u=>`<option value="${u}" ${u===m.unit?'selected':''}>${{goals:'Doelpunten',legs:'Legs',sets:'Sets'}[u]}</option>`).join('')}</select></label>${m.unit!=='goals'?`<label>First-to<input name="first" type="number" min="1" max="99" value="${esc(m.first_to)}"></label>`:''}</div><label>Reden voor wijziging / vrijgave<input name="reason" maxlength="500"></label><button class="btn">Datum en spelvorm opslaan</button><div class="row"><button type="button" data-action="open">Voorspellen vrijgeven / heropenen</button><button type="button" data-action="close">Direct sluiten</button><button type="button" data-action="start">Werkelijk gestart</button><button type="button" data-action="postpone">Uitstellen</button><button type="button" data-action="cancel">Annuleren</button></div><div class="two"><label>Score ${esc(m.home)}<input name="home" type="number" min="0" max="99" value="${esc(m.home_score)}"></label><label>Score ${esc(m.away)}<input name="away" type="number" min="0" max="99" value="${esc(m.away_score)}"></label></div>${m.unit==='goals'?`<label>Winnaar bij gelijkspel (na verlenging / strafschoppen)<select name="winner"><option value="">Kies winnaar</option>${m.home_slot?`<option value="${m.home_slot}">${esc(m.home)}</option>`:''}${m.away_slot?`<option value="${m.away_slot}">${esc(m.away)}</option>`:''}</select></label><p class="hint">Vul de score volgens de bestaande voetbalregels in, exclusief strafschoppen.</p>`:''}<button type="button" data-result>${m.status==='finished'?'Uitslag corrigeren':'Uitslag opslaan'}</button>`;
      card.append(form);form.oninput=()=>card.dataset.koDirty='true';form.onchange=()=>card.dataset.koDirty='true';
      function onlyThisDraft(){return ![...target.querySelectorAll('[data-ko-dirty="true"]')].some(x=>x!==card)||confirm('Andere niet-opgeslagen wedstrijdwijzigingen laten vervallen?');}
      form.onsubmit=e=>{e.preventDefault();if(!onlyThisDraft())return;try{mutate('schedule',m.id,{start:dutchToUTC(form.elements.start.value),unit:form.elements.unit.value,first_to:form.elements.first?Number(form.elements.first.value)||null:null,reason:form.elements.reason.value});}catch(error){msg.textContent=error.message;}};
      form.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>{if(onlyThisDraft()&&confirm(b.textContent+'?'))mutate(b.dataset.action,m.id,{reason:form.elements.reason.value});});
      form.querySelector('[data-result]').onclick=()=>{
        if(form.elements.home.value===''||form.elements.away.value===''){msg.textContent='Vul beide scores in.';return;}
        if(onlyThisDraft()&&confirm('Deze uitslag verwerken en de winnaar doorplaatsen?'))mutate('result',m.id,{home_score:Number(form.elements.home.value),away_score:Number(form.elements.away.value),winner_slot:form.elements.winner?Number(form.elements.winner.value)||null:null,reason:form.elements.reason.value});
      };
    }
    $('ko-filter').onchange=()=>cards.querySelectorAll('article').forEach(c=>c.hidden=$('ko-filter').value!=='all'&&c.dataset.koStatus!==$('ko-filter').value);
    clearInterval(tickTimer);const clockOffset=now-Date.now();
    tickTimer=setInterval(()=>{
      if(!alive(target,ctx)){clearInterval(tickTimer);return;}
      [...cards.children].forEach((card,index)=>{const state=knockoutStatus(data.matches[index],Date.now()+clockOffset);card.dataset.koStatus=state;card.querySelector('[data-ko-status]').textContent=state;});
      $('ko-filter').onchange();
    },1000);
    $('ko-refresh').onclick=()=>{if(!busy&&(!dirty()||confirm('Niet-opgeslagen wijzigingen laten vervallen?')))read().catch(e=>msg.textContent=e.message);};
    if($('ko-publish'))$('ko-publish').onclick=()=>{if((!dirty()||confirm('Niet-opgeslagen wijzigingen laten vervallen?'))&&confirm('Publiceren vergrendelt de puntentelling en opent complete toekomstige wedstrijden. Doorgaan?'))mutate('publish',null);};
  }
  try{
    await refreshCatalog();if(!alive(target,ctx))return;
    const create=$('ko-create');create.innerHTML=`<details><summary>Nieuw knock-outtoernooi</summary><form class="stack"><label>Toernooinaam<input name="name" required maxlength="120"></label><label>Sport<select name="sport">${catalog.sports.map(s=>`<option value="${esc(s.id)}" data-slug="${esc(s.slug)}">${esc(s.name)}</option>`).join('')}</select></label><label>Toernooisjabloon<select name="template"></select></label><label>Deelnemers<select name="kind"><option value="players">Spelers</option><option value="teams">Teams</option></select></label><label>Aantal deelnemers<input name="count" type="number" min="2" max="128" value="8" required></label><p class="hint">Je maakt eerst een leeg schema. Vul daarna namen rechtstreeks op de juiste schemaplek in. Vrijstellingen worden over het schema verdeeld.</p><label>Toernooistart (Nederland)<input name="start" type="datetime-local" required></label><label>Puntenmethode<select name="mode"><option value="replacement">Exacte score vervangt winnaarspunten</option><option value="additive">Exacte score telt bovenop winnaarspunten</option></select></label><div data-rounds class="stack"></div><label>Naam eigen sjabloon<input name="templateName" maxlength="80" placeholder="Bijvoorbeeld clubkampioenschap"></label><button type="button" data-save-template class="ghost">Format als sjabloon bewaren</button><p data-create-message role="status"></p><button type="submit" class="btn">Leeg toernooischema maken</button></form></details>`;
    const f=create.querySelector('form'),rules=f.querySelector('[data-rounds]'),feedback=f.querySelector('[data-create-message]');
    let chosenTemplate=null;
    function freezeCreate(flag){f.querySelectorAll('input,select,button').forEach(el=>el.disabled=flag);if(!flag)f.elements.kind.disabled=!!chosenTemplate;}
    function updateRounds(){
      const count=Number(f.elements.count.value);if(!Number.isInteger(count)||count<2||count>128){rules.textContent='Kies 2–128 deelnemers';return;}
      const darts=f.elements.sport.selectedOptions[0]?.dataset.slug==='darts',nr=Math.ceil(Math.log2(count));
      rules.innerHTML=Array.from({length:nr},(_,i)=>`<fieldset><legend>${['Finale','Halve finales','Kwartfinales','Achtste finales'][nr-i-1]||'Ronde '+(i+1)}</legend><label>Spelvorm<select data-unit><option value="${darts?'legs':'goals'}">${darts?'Legs':'Doelpunten'}</option>${darts?'<option value="sets">Sets</option>':''}</select></label>${darts?'<label>First-to<input data-first type="number" min="1" max="99" required></label>':''}<label>Punten juiste winnaar<input data-winner type="number" min="0" max="1000" required></label><label>Punten exacte score<input data-exact type="number" min="0" max="1000" required></label></fieldset>`).join('');
    }
    function templateOptions(){
      const darts=f.elements.sport.selectedOptions[0]?.dataset.slug==='darts';
      f.elements.template.innerHTML='<option value="">Vrij knock-outformat</option>'+(darts?'<option value="euro-tour">European Tour · 48 spelers</option>':'')+(catalog.templates||[]).filter(t=>t.sport_id===f.elements.sport.value).map(t=>`<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');
      chosenTemplate=null;f.elements.count.readOnly=false;f.elements.kind.disabled=false;updateRounds();
    }
    function readRules(){return [...rules.querySelectorAll('fieldset')].map(r=>({unit:r.querySelector('[data-unit]').value,first_to:r.querySelector('[data-first]')?Number(r.querySelector('[data-first]').value):null,winner_points:Number(r.querySelector('[data-winner]').value),exact_points:Number(r.querySelector('[data-exact]').value)}));}
    f.elements.template.onchange=()=>{
      chosenTemplate=f.elements.template.value==='euro-tour'?{participant_count:48,participant_kind:'players',rules:euroTourRules()}:(catalog.templates||[]).find(t=>t.id===f.elements.template.value);
      f.elements.count.readOnly=!!chosenTemplate;
      if(chosenTemplate){f.elements.count.value=chosenTemplate.participant_count;f.elements.kind.value=chosenTemplate.participant_kind;if(chosenTemplate.scoring_mode)f.elements.mode.value=chosenTemplate.scoring_mode;}
      f.elements.kind.disabled=!!chosenTemplate;updateRounds();
      if(chosenTemplate)[...rules.querySelectorAll('fieldset')].forEach((fieldset,i)=>{const rule=chosenTemplate.rules[i];fieldset.querySelector('[data-unit]').value=rule.unit;if(fieldset.querySelector('[data-first]'))fieldset.querySelector('[data-first]').value=rule.first_to;for(const [key,selector] of [['winner_points','[data-winner]'],['exact_points','[data-exact]']])if(rule[key]!=null)fieldset.querySelector(selector).value=rule[key];});
    };
    templateOptions();f.elements.count.onchange=()=>{if(!chosenTemplate)updateRounds();};f.elements.sport.onchange=templateOptions;
    f.querySelector('[data-save-template]').onclick=async()=>{
      if(busy)return;
      if(!f.elements.templateName.value.trim()){feedback.textContent='Vul een naam voor het sjabloon in.';return;}
      if(!Number.isInteger(Number(f.elements.count.value))||Number(f.elements.count.value)<2||Number(f.elements.count.value)>128||![...rules.querySelectorAll('input')].every(input=>input.reportValidity()))return;
      busy=true;freezeCreate(true);
      try{const id=await rpc('save_knockout_template',{p_name:f.elements.templateName.value.trim(),p_sport:f.elements.sport.value,p_kind:f.elements.kind.value,p_count:Number(f.elements.count.value),p_rules:readRules(),p_mode:f.elements.mode.value});await refreshCatalog();if(!alive(target,ctx))return;templateOptions();f.elements.template.value=id;f.elements.template.onchange();feedback.textContent='Sjabloon opgeslagen bij deze sport. Namen en tijden worden niet bewaard.';}
      catch(error){if(alive(target,ctx))feedback.textContent=error.message;}finally{busy=false;if(alive(target,ctx))freezeCreate(false);}
    };
    f.oninput=()=>create.dataset.koDirty='true';
    f.onsubmit=async e=>{
      e.preventDefault();if(busy||!f.reportValidity())return;
      const roster=Array(Number(f.elements.count.value)).fill('');
      busy=true;freezeCreate(true);
      try{
        const id=await rpc('create_knockout_tournament',{p_name:f.elements.name.value.trim(),p_sport:f.elements.sport.value,p_kind:f.elements.kind.value,p_roster:roster,p_start:dutchToUTC(f.elements.start.value),p_mode:f.elements.mode.value,
          p_rules:readRules()});
        if(!alive(target,ctx))return;create.dataset.koDirty='false';currentId=id;await refreshCatalog();await read();document.dispatchEvent(new CustomEvent('predict-admin-schema-created'));feedback.textContent='Leeg schema aangemaakt. Vul namen op de juiste plekken en daarna de speeltijden in.';ctx.onSaved?.();
      }catch(error){if(alive(target,ctx))feedback.textContent=error.message;}finally{busy=false;if(alive(target,ctx))freezeCreate(false);}
    };
    if(requestedId&&catalog.tournaments.some(t=>t.id===requestedId)){currentId=requestedId;$('ko-tour').value=currentId;await read();}
    $('ko-tour').onchange=()=>{if(busy||dirty()&&!confirm('Niet-opgeslagen wijzigingen laten vervallen?')){$('ko-tour').value=currentId;return;}currentId=$('ko-tour').value;if(currentId)read().catch(e=>msg.textContent=e.message);else $('ko-editor').textContent='';};
  }catch(e){if(alive(target,ctx))msg.textContent=e.message;}
}
