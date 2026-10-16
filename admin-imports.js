const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const dateOnly=d=>d.toISOString().slice(0,10);
export async function loadAdminImports(target,ctx){
  const {supabase,signal}=ctx,alive=()=>!signal.aborted&&target.isConnected&&ctx.isCurrent();
  let offset=0,total=0,rounds=[],matches=[],busy=false,lastTournament='';
  target.innerHTML='<h2>Wedstrijdgegevens controleren</h2><p>Haal DartsAPI-voorstellen op. Dit wijzigt nog geen wedstrijden of uitslagen. Controleer ieder voorstel vóór verwerking. Een nieuwe wedstrijd blijft gesloten voor voorspellingen.</p><form id="import-fetch" class="stack"><label for="import-tournament">Dartstoernooi</label><select id="import-tournament" required><option value="">Kies een toernooi</option></select><label for="import-kind">Gegevens</label><select id="import-kind"><option value="fixtures">Wedstrijdvoorstellen</option><option value="results">Uitslagen van gisteren (UTC)</option></select><label for="import-competition">Exacte toernooinaam bij DartsAPI</label><input id="import-competition" maxlength="120" required placeholder="Bijvoorbeeld: Dutch Darts Championship"><div class="two"><div class="field"><label for="import-from">Van (UTC)</label><input id="import-from" type="date" required></div><div class="field"><label for="import-to">Tot en met (UTC)</label><input id="import-to" type="date" required></div></div><p class="hint">Maximaal 32 dagen. Uitslagen komen uitsluitend uit het gisterenoverzicht van de bron; het datumfilter haalt geen oudere dagen op. Geen automatische koppeling of vrijgave.</p><button class="btn">Voorstellen ophalen</button></form><p id="import-message" role="status"></p><button class="ghost" id="import-refresh">Wachtrij vernieuwen</button><div id="import-items" class="stack"></div><div class="row"><button class="ghost" id="import-prev">Vorige voorstellen</button><span id="import-page" class="hint"></span><button class="ghost" id="import-next">Volgende voorstellen</button></div>';
  const $=id=>target.querySelector('#'+id),message=$('import-message'),select=$('import-tournament');
  function setDates(){const d=new Date();if($('import-kind').value==='results')d.setUTCDate(d.getUTCDate()-1);$('import-from').value=dateOnly(d);if($('import-kind').value==='fixtures')d.setUTCDate(d.getUTCDate()+7);$('import-to').value=dateOnly(d);}
  setDates();$('import-kind').onchange=setDates;
  function canDiscard(){return !target.querySelector('[data-import-dirty="true"]')||confirm('Niet-opgeslagen importcontroles laten vervallen?');}
  function lock(value){busy=value;target.querySelectorAll('#import-fetch input,#import-fetch select,#import-fetch button,#import-prev,#import-next,#import-refresh').forEach(x=>x.disabled=value);if(!value){$('import-prev').disabled=offset===0;$('import-next').disabled=offset+25>=total;}}
  window.addEventListener('beforeunload',e=>{if(target.querySelector('[data-import-dirty="true"]')){e.preventDefault();e.returnValue='';}},{signal});
  async function load(){
    if(!select.value){$('import-items').textContent='Kies eerst een dartstoernooi.';return;}
    lock(true);message.textContent='Wachtrij laden...';
    try{
      const tournament=select.value;
      const responses=await Promise.all([
        supabase.rpc('list_darts_imports',{p_tournament_id:tournament,p_offset:offset}),
        supabase.rpc('admin_get_tournament_rounds',{p_tournament_id:tournament}),
        supabase.rpc('admin_get_matches',{p_tournament_id:tournament})
      ]);
      if(!alive()||select.value!==tournament)return;
      if(responses.some(r=>r.error))throw Error('Wachtrij laden mislukt. Probeer opnieuw.');
      rounds=responses[1].data||[];matches=responses[2].data||[];
      const data=responses[0].data||{items:[],total:0};total=data.total||0;
      $('import-items').textContent='';
      if(!data.items?.length)$('import-items').textContent='Geen importvoorstellen voor dit toernooi.';
      for(const item of data.items||[])addCard(item);
      $('import-page').textContent=total?`${offset+1}–${Math.min(offset+25,total)} van ${total}`:'0 voorstellen';
      message.textContent='';
    }catch(error){if(alive())message.textContent=error.message;}
    finally{if(alive()){lock(false);$('import-prev').disabled=offset===0;$('import-next').disabled=offset+25>=total;}}
  }
  function addCard(item){
    const p=item.payload||{},card=document.createElement('article');card.className='panel stack';card.style.overflowWrap='anywhere';
    const active=['pending','conflict'].includes(item.state),result=item.kind==='results';
    const state={pending:'Te controleren',applied:'Verwerkt',rejected:'Afgewezen',conflict:'Conflict — geblokkeerd'}[item.state]||item.state;
    card.innerHTML=`<h3>${esc(p.home_name)} – ${esc(p.away_name)}</h3><p>${result?'Uitslagvoorstel':'Wedstrijdvoorstel'} · ${esc(state)} · ${esc(p.played_on)}</p><p class="hint">Bron: ${esc(p.competition)} · ronde: ${esc(p.round||'onbekend')} · ${esc(item.external_id)}</p>${result?`<p>Bronwinnaar ${esc(p.home_name)}: ${esc(p.home_score)}–${esc(p.away_score)}. De server zet de score om naar de wedstrijdvolgorde.</p>`:`<p>Bronstart: ${esc(p.scheduled_start||'onbekend')}. Datum bevestigd: ${p.date_confirmed?'ja':'nee'}.</p>`}<p class="hint">${esc(item.review_note||'Controleer toernooi-editie, speeldag, deelnemers, ronde en spelvorm met de bron. Alleen normaal uitgespeelde wedstrijden verwerken; geen walk-over of opgave.')}</p>`;
    if(active){
      const form=document.createElement('form');form.className='stack';
      form.innerHTML=`${result?`<label>Lokale wedstrijd<select name="match" required><option value="">Kies gecontroleerde wedstrijd</option>${matches.map(m=>`<option value="${esc(m.match_id)}">${esc(m.home_name)} – ${esc(m.away_name)} · ${esc(m.scheduled_start)} · ${esc(m.score_unit)}</option>`).join('')}</select></label>`:''}<label>Gecontroleerde ronde<select name="round" aria-label="Gecontroleerde ronde" required><option value="">Kies ronde</option>${rounds.map(r=>`<option value="${esc(r.round_id)}">${esc(r.round_name)}</option>`).join('')}</select></label><label>Gecontroleerde score-eenheid<select name="unit" required><option value="">Kies spelvorm</option><option value="sets">Sets</option><option value="legs">Legs</option></select></label>${!result?'<label>Benodigd aantal sets of legs<input name="first" type="number" min="1" max="99" step="1" required></label>':''}<label class="choice"><input name="attested" type="checkbox" required> Ik heb toernooi, ronde, spelvorm en normaal wedstrijdverloop gecontroleerd.</label><button class="btn" ${item.state==='conflict'?'disabled':''}>${result?'Uitslag gecontroleerd verwerken':'Wedstrijdconcept maken'}</button><button class="ghost" type="button" data-reject>Voorstel afwijzen</button><p role="status" data-feedback></p>`;
      form.onchange=()=>card.dataset.importDirty='true';
      async function review(action){
        if(action==='apply'&&!form.reportValidity())return;
        if(action==='reject'&&!confirm('Dit bronvoorstel afwijzen?'))return;
        const buttons=form.querySelectorAll('button');buttons.forEach(b=>b.disabled=true);
        const feedback=form.querySelector('[data-feedback]');feedback.textContent='Verwerken...';
        try{
          const r=await supabase.rpc('review_darts_import',{p_item_id:item.id,p_action:action,p_match_id:result?form.elements.match.value||null:null,
            p_round_id:form.elements.round.value||null,p_unit:form.elements.unit.value||null,p_first_to:result?null:Number(form.elements.first.value)||null,p_attested:form.elements.attested.checked});
          if(!alive()||!card.isConnected)return;
          if(r.error)throw Error(r.error.message);
          card.dataset.importDirty='false';
          if(r.data?.state==='conflict'){feedback.textContent='Conflict: '+(r.data.reason||'Afzonderlijke controle nodig. Bestaande gegevens zijn behouden.');form.querySelector('.btn').disabled=true;form.querySelector('[data-reject]').disabled=false;return;}
          form.textContent=r.data?.state==='rejected'?'Voorstel afgewezen.':result?'Uitslag verwerkt of bestaande uitslag bevestigd.':'Wedstrijdconcept gemaakt. Controleer starttijd en formaat in Wedstrijden; voorspellingen blijven gesloten.';
          if(r.data?.state==='applied')ctx.onApplied?.();
        }catch(error){if(alive()&&card.isConnected){feedback.textContent=error.message;buttons.forEach(b=>b.disabled=false);if(item.state==='conflict')form.querySelector('.btn').disabled=true;}}
      }
      form.onsubmit=e=>{e.preventDefault();review('apply');};form.querySelector('[data-reject]').onclick=()=>review('reject');card.append(form);
    }
    $('import-items').append(card);
  }
  select.onchange=()=>{if(busy||!canDiscard()){select.value=lastTournament;return;}lastTournament=select.value;offset=0;load();};
  $('import-refresh').onclick=()=>{if(!busy&&canDiscard())load();};
  $('import-prev').onclick=()=>{if(!busy&&canDiscard()){offset=Math.max(0,offset-25);load();}};
  $('import-next').onclick=()=>{if(!busy&&canDiscard()){offset+=25;load();}};
  $('import-fetch').onsubmit=async e=>{
    e.preventDefault();if(busy||!canDiscard())return;lock(true);message.textContent='Bron ophalen en controleren...';
    try{
      const r=await supabase.functions.invoke('sync-darts-data',{body:{tournament_id:select.value,kind:$('import-kind').value,competition:$('import-competition').value.trim(),from:$('import-from').value,to:$('import-to').value}});
      if(!alive())return;
      if(r.error){let detail='Ophalen mislukt. Controleer bronconfiguratie of probeer later opnieuw.';try{detail=(await r.error.context.json()).error||detail;}catch{}throw Error(detail);}
      offset=0;await load();if(alive())message.textContent=`${r.data.queued} nieuwe voorstellen; ${r.data.unchanged} ongewijzigd. Wedstrijden en uitslagen zijn niet aangepast.`;
    }catch(error){if(alive())message.textContent=error.message;}
    finally{if(alive())lock(false);}
  };
  try{
    const catalog=await supabase.rpc('admin_list_tournaments');if(!alive())return;if(catalog.error)throw Error('Toernooien laden mislukt. Open Beheer opnieuw.');
    select.innerHTML='<option value="">Kies een toernooi</option>'+(catalog.data||[]).map(t=>`<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');
    $('import-items').textContent='Kies eerst een dartstoernooi.';
  }catch(error){if(alive())message.textContent=error.message;}
}
