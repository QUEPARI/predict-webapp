const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tournamentLabel=s=>({draft:'Concept',published:'Gepubliceerd',active:'Actief',completed:'Afgerond',archived:'Gearchiveerd'}[s]||s);
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
  if(!m.home_slot||!m.away_slot||!m.start||!m.unit||(['sets','legs'].includes(m.unit)&&!m.first_to))return 'Nog aanvullen';
  if(m.status==='live'||Date.parse(m.start)<=now)return 'Uitslag nodig';
  return m.enabled?'Gepland · voorspellen open':'Gepland · voorspellen gesloten';
}
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
  let catalog,data,currentId='',busy=false,tickTimer;
  ctx.signal.addEventListener('abort',()=>clearInterval(tickTimer),{once:true});
  const dirty=()=>!!target.querySelector('[data-ko-dirty="true"]');
  window.addEventListener('beforeunload',e=>{if(dirty()){e.preventDefault();e.returnValue='';}},{signal:ctx.signal});
  async function refreshCatalog(){catalog=await rpc('knockout_catalog');if(!alive(target,ctx))return;$('ko-tour').innerHTML='<option value="">Kies een knock-outtoernooi</option>'+catalog.tournaments.map(t=>`<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');$('ko-tour').value=currentId;}
  async function read(){
    const id=currentId,next=await rpc('get_knockout_schema',{p_id:id});if(!alive(target,ctx)||id!==currentId)return;data=next;renderEditor();
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
    if(data.status==='draft'){
      const rosterForm=document.createElement('form');rosterForm.className='stack';
      rosterForm.innerHTML=`<label>Namen corrigeren (dezelfde lotingsplekken)<textarea rows="5" required>${esc(data.roster.join('\n'))}</textarea></label><button class="ghost">Deelnemersnamen opslaan</button>`;
      host.querySelector('h3').after(rosterForm);rosterForm.oninput=()=>rosterForm.dataset.koDirty='true';
      rosterForm.onsubmit=e=>{e.preventDefault();if(!dirty()||confirm('Deelnemersnamen opslaan en overige niet-opgeslagen wijzigingen laten vervallen?'))mutate('roster',null,{names:rosterForm.querySelector('textarea').value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean)});};
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
    const create=$('ko-create');create.innerHTML=`<details><summary>Nieuw knock-outtoernooi</summary><form class="stack"><label>Toernooinaam<input name="name" required maxlength="120"></label><label>Sport<select name="sport">${catalog.sports.map(s=>`<option value="${esc(s.id)}" data-slug="${esc(s.slug)}">${esc(s.name)}</option>`).join('')}</select></label><label>Deelnemers<select name="kind"><option value="players">Spelers</option><option value="teams">Teams</option></select></label><label>Aantal deelnemers<input name="count" type="number" min="2" max="128" value="8" required></label><label>Namen in lotingsvolgorde, één per regel<textarea name="roster" rows="8" required></textarea></label><p class="hint">Bij vrijstellingen gaan de eerste namen in deze lijst direct door. De resterende namen worden per twee ingedeeld. Controleer de lotingsvolgorde vóór aanmaken.</p><label>Toernooistart (Nederland)<input name="start" type="datetime-local" required></label><label>Puntenmethode<select name="mode"><option value="replacement">Exacte score vervangt winnaarspunten</option><option value="additive">Exacte score telt bovenop winnaarspunten</option></select></label><div data-rounds class="stack"></div><p data-create-message role="status"></p><button class="btn">Concepttoernooi en schema maken</button></form></details>`;
    const f=create.querySelector('form'),rules=f.querySelector('[data-rounds]'),feedback=f.querySelector('[data-create-message]');
    function updateRounds(){
      const count=Number(f.elements.count.value);if(!Number.isInteger(count)||count<2||count>128){rules.textContent='Kies 2–128 deelnemers';return;}
      const darts=f.elements.sport.selectedOptions[0]?.dataset.slug==='darts',nr=Math.ceil(Math.log2(count));
      rules.innerHTML=Array.from({length:nr},(_,i)=>`<fieldset><legend>${i===nr-1?'Finale':'Ronde '+(i+1)}</legend><label>Spelvorm<select data-unit><option value="${darts?'legs':'goals'}">${darts?'Legs':'Doelpunten'}</option>${darts?'<option value="sets">Sets</option>':''}</select></label>${darts?'<label>First-to<input data-first type="number" min="1" max="99" required></label>':''}<label>Punten juiste winnaar<input data-winner type="number" min="0" max="1000" required></label><label>Punten exacte score<input data-exact type="number" min="0" max="1000" required></label></fieldset>`).join('');
    }
    updateRounds();f.elements.count.onchange=updateRounds;f.elements.sport.onchange=updateRounds;
    f.oninput=()=>create.dataset.koDirty='true';
    f.onsubmit=async e=>{
      e.preventDefault();if(busy||!f.reportValidity())return;
      const roster=f.elements.roster.value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean);
      if(roster.length!==Number(f.elements.count.value)){feedback.textContent='Het aantal namen moet gelijk zijn aan het deelnemersaantal.';return;}
      const button=f.querySelector('button');button.disabled=true;busy=true;
      try{
        const id=await rpc('create_knockout_tournament',{p_name:f.elements.name.value.trim(),p_sport:f.elements.sport.value,p_kind:f.elements.kind.value,p_roster:roster,p_start:dutchToUTC(f.elements.start.value),p_mode:f.elements.mode.value,
          p_rules:[...rules.querySelectorAll('fieldset')].map(r=>({unit:r.querySelector('[data-unit]').value,first_to:r.querySelector('[data-first]')?Number(r.querySelector('[data-first]').value):null,winner_points:Number(r.querySelector('[data-winner]').value),exact_points:Number(r.querySelector('[data-exact]').value)}))});
        if(!alive(target,ctx))return;create.dataset.koDirty='false';currentId=id;await refreshCatalog();await read();feedback.textContent='Concept aangemaakt. Vul tijden in en publiceer als het schema gereed is.';ctx.onSaved?.();
      }catch(error){if(alive(target,ctx))feedback.textContent=error.message;}finally{busy=false;if(button.isConnected)button.disabled=false;}
    };
    $('ko-tour').onchange=()=>{if(busy||dirty()&&!confirm('Niet-opgeslagen wijzigingen laten vervallen?')){$('ko-tour').value=currentId;return;}currentId=$('ko-tour').value;if(currentId)read().catch(e=>msg.textContent=e.message);else $('ko-editor').textContent='';};
  }catch(e){if(alive(target,ctx))msg.textContent=e.message;}
}
