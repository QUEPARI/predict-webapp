import {showTournamentImage} from './tournament-images.js?v=header-20261017';
// Public user screens. Supabase remains authoritative for access, scores and deadlines.
const labels = {announced:'Vooraankondiging',published:'Gepubliceerd',active:'Actief',completed:'Afgerond',archived:'Gepauzeerd / archief',scheduled:'Gepland',postponed:'Uitgesteld',live:'Bezig',finished:'Afgerond',cancelled:'Geannuleerd'};
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date = value => value && Number.isFinite(Date.parse(value))
  ? new Intl.DateTimeFormat('nl-NL',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)) : 'Nog niet bevestigd';
const dateRange=(start,end)=>{const fmt=v=>v&&Number.isFinite(Date.parse(v))?new Intl.DateTimeFormat('nl-NL',{dateStyle:'medium'}).format(new Date(v)):'';const a=fmt(start),b=fmt(end);return a&&b?(a===b?a:a+' – '+b):a||'Datums volgen';};
const localDay=value=>{const d=new Date(value);return Number.isFinite(d.getTime())?`${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`:'';};
const current = (target,ctx) => target.isConnected && !ctx.signal.aborted && ctx.isCurrent();
const open = (m,t) => ['published','active'].includes(t.status) && m.predictions_enabled === true &&
  m.needs_review === false && m.start_time_confirmed === true && m.round_id != null &&
  m.status === 'scheduled' && m.actual_start == null && m.home_score == null && m.away_score == null &&
  Date.parse(m.scheduled_start) > Date.now() &&
  (m.score_unit === 'goals' ? m.first_to == null : ['sets','legs'].includes(m.score_unit) && Number.isInteger(m.first_to) && m.first_to >= 1 && m.first_to <= 99);

export function predictionOutcome(m,p){
 if(m.status!=='finished'||m.home_score==null||m.away_score==null)return {state:'pending',label:m.status==='cancelled'?'Geannuleerd':m.status==='postponed'?'Uitgesteld':'Wacht op uitslag'};
 if(!p)return {state:'unpredicted',label:'Niet voorspeld'};
 if(p.home_score===m.home_score&&p.away_score===m.away_score)return {state:'exact',label:'Exact goed'};
 if(Math.sign(p.home_score-p.away_score)===Math.sign(m.home_score-m.away_score))return {state:'winner',label:'Winnaar goed'};
 return {state:'wrong',label:'Onjuist'};
}

export async function loadTournamentCatalog(target,ctx) {
  try {
    const [tours,entries] = await Promise.all([
      ctx.supabase.from('tournaments').select('id,name,status,starts_at,ends_at').neq('status','draft').order('starts_at').order('id'),
      ctx.supabase.from('tournament_entries').select('tournament_id').eq('user_id',ctx.userId)
    ]);
    if (!current(target,ctx)) return;
    if (tours.error || entries.error) throw new Error((tours.error || entries.error).message);
    const joined = new Set((entries.data || []).map(e=>e.tournament_id));
    const all=[...(tours.data||[])].sort((a,b)=>(Date.parse(a.starts_at)||Infinity)-(Date.parse(b.starts_at)||Infinity)||a.name.localeCompare(b.name));
    const card=t=>{return `<article class="panel tournament-tile"><button class="tournament-tile-link" aria-label="${esc(t.name)} · ${joined.has(t.id)?'Wedstrijden en voorspellingen':'Bekijk toernooi'}" data-online-open="${esc(t.id)}"><span class="tournament-art" data-tour-art="${esc(t.id)}" aria-hidden="true"></span><span class="tournament-tile-body"><h2>${esc(t.name)}</h2>${joined.has(t.id)?'':`<span class="muted mini">${esc(labels[t.status]||t.status)}</span>`}${t.status==='announced'?'<span class="mini">Binnenkort · deelname opent later</span>':`<span class="prediction-count mini" data-tour-count="${esc(t.id)}" role="status">Open wedstrijden laden…</span>`}<span class="mini muted game-dates">${esc(dateRange(t.starts_at,t.ends_at))}</span></span><span class="tile-arrow" aria-hidden="true">›</span></button></article>`;};
    const mine=all.filter(t=>joined.has(t.id)&&t.status!=='archived'),available=all.filter(t=>!joined.has(t.id)&&['announced','published','active'].includes(t.status));
    target.innerHTML=`<h1>Mijn spellen</h1><div class="grid" data-my-tournaments>${mine.map(card).join('')||'<p>Je doet nog niet mee aan een toernooi.</p>'}</div><h2 class="available-title">Beschikbare spellen</h2><div class="grid" data-open-tournaments>${available.map(card).join('')||'<p>Geen andere open toernooien beschikbaar.</p>'}</div>`;
    let countTimer;
    const updateCounts=async()=>{try{const r=await ctx.supabase.rpc('get_tournament_prediction_counts');if(!current(target,ctx))return;if(r.error||!Array.isArray(r.data?.tournaments))throw Error('Aantallen niet beschikbaar');const counts=new Map(r.data.tournaments.map(c=>[c.id,c]));target.querySelectorAll('[data-tour-count]').forEach(el=>{const c=counts.get(el.dataset.tourCount)||{open_count:0,remaining_count:0};el.innerHTML=`<span>${Number(c.open_count)} wedstrijden open om te voorspellen</span>${joined.has(el.dataset.tourCount)?`<strong class="prediction-attention ${c.remaining_count>0?'remaining':c.open_count>0?'complete':''}">${c.remaining_count>0?'Nog '+Number(c.remaining_count)+' te voorspellen':c.open_count>0?'Alle open wedstrijden voorspeld ✓':'Geen open wedstrijden'}</strong>`:''}`;});const delay=Date.parse(r.data.next_deadline)-Date.parse(r.data.server_now);if(Number.isFinite(delay)&&delay>0)countTimer=setTimeout(updateCounts,Math.min(delay+100,2147483647));}catch(e){if(current(target,ctx))target.querySelectorAll('[data-tour-count]').forEach(el=>el.textContent='Aantal open wedstrijden niet beschikbaar.');}};
    ctx.signal.addEventListener('abort',()=>clearTimeout(countTimer),{once:true});updateCounts();
    target.querySelectorAll('[data-tour-art]').forEach(el=>showTournamentImage(el,ctx.supabase,el.dataset.tourArt));
    target.querySelectorAll('[data-online-open]').forEach(b=>b.onclick=()=>ctx.onOpen(b.dataset.onlineOpen));
  } catch (error) {showError(target,ctx,error,()=>loadTournamentCatalog(target,ctx));}
}

function showError(target,ctx,error,retry) {
  if (!current(target,ctx)) return;
  target.replaceChildren();
  const message=document.createElement('p'); message.setAttribute('role','alert');
  message.textContent='Ophalen mislukt: '+(error.message || 'Controleer je verbinding.');
  const button=document.createElement('button'); button.className='btn secondary';button.textContent='Opnieuw proberen';button.onclick=retry;
  target.append(message,button);
}

export async function loadTournamentDetail(host,ctx,page=0,notice='',view={tab:'predictions',round:''}) {
  const target=document.createElement('section');target.className='stack tournament-detail';target.textContent='Toernooi laden...';host.replaceChildren(target);
  try {
    const [tour,entry] = await Promise.all([
      ctx.supabase.from('tournaments').select('id,name,status,starts_at,ends_at').eq('id',ctx.tournamentId).single(),
      ctx.supabase.from('tournament_entries').select('tournament_id').eq('tournament_id',ctx.tournamentId).eq('user_id',ctx.userId)
    ]);
    if (!current(target,ctx)) return;
    if (tour.error || entry.error || !tour.data) throw new Error((tour.error || entry.error)?.message || 'Toernooi niet beschikbaar.');
    const t=tour.data,joined=!!entry.data?.length;
    if(t.status==='announced'){target.innerHTML=`<div class="tournament-title"><h1>${esc(t.name)}</h1></div><p class="mini muted">${esc(dateRange(t.starts_at,t.ends_at))}</p><div class="panel stack"><h2>Vooraankondiging</h2><p>Dit spel komt eraan. Deelnemen en voorspellen worden na publicatie beschikbaar.</p></div>`;return;}
    const size=50;
    const [matches,rounds,points,scoring,rules,bracketResponse] = await Promise.all([
      (async()=>{const all=[];for(let offset=0;;offset+=500){const r=await ctx.supabase.from('matches').select('id,round_id,home_name,away_name,scheduled_start,actual_start,status,home_score,away_score,score_unit,first_to,start_time_confirmed,needs_review,predictions_enabled',{count:'exact'}).eq('tournament_id',t.id).order('scheduled_start').order('id').range(offset,offset+499);if(r.error)return r;all.push(...(r.data||[]));if((r.data||[]).length<500||all.length>=r.count)return {data:all};}})(),
      ctx.supabase.from('tournament_rounds').select('id,name,round_order').eq('tournament_id',t.id).order('round_order'),
      joined ? ctx.supabase.rpc('get_my_match_points',{p_tournament_id:t.id}) : Promise.resolve({data:[]}),
      ctx.supabase.from('tournament_scoring').select('scoring_mode').eq('tournament_id',t.id),
      ctx.supabase.from('round_scoring').select('round_id,winner_points,exact_score_points').eq('tournament_id',t.id),
      ctx.supabase.rpc('get_knockout_schema',{p_id:t.id})
    ]);
    if (!current(target,ctx)) return;
    const failure=[matches,rounds,points,scoring,rules].find(r=>r.error)?.error;
    if (failure) throw new Error(failure.message);
    const bracket=!bracketResponse.error&&Array.isArray(bracketResponse.data?.matches)&&Array.isArray(bracketResponse.data?.rounds)?bracketResponse.data:null;
    const byes=new Set((bracket?.matches||[]).filter(m=>m.bye).map(m=>m.id));
    const allMatches=(matches.data||[]).filter(m=>!byes.has(m.id));
    const selected=allMatches.filter(m=>!view.round||m.round_id===view.round);
    const resultMatches=selected.filter(m=>m.home_score!=null);
    const visiblePredictions=()=>selected.filter(m=>localDay(m.scheduled_start)===localDay(new Date())||open(m,t));
    let activeMatches=view.tab==='results'?resultMatches:visiblePredictions();
    page=Math.max(0,Math.min(page,Math.ceil(activeMatches.length/size)-1));
    const list=selected;
    const predictionMatches=selected;
    const shownResults=resultMatches;
    const predictions=joined && list.length ? await ctx.supabase.from('match_predictions')
      .select('match_id,home_score,away_score').eq('user_id',ctx.userId).in('match_id',list.map(m=>m.id)) : {data:[]};
    if (!current(target,ctx)) return;
    if (predictions.error) throw new Error(predictions.error.message);
    const myPredictions=new Map((predictions.data || []).map(p=>[p.match_id,p]));
    const myPoints=new Map((points.data || []).map(p=>[p.match_id,p]));
    const roundNames=new Map((rounds.data || []).map(r=>[r.id,r.name]));
    const roundRules=new Map((rules.data || []).map(r=>[r.round_id,r]));
    const scoringMode=scoring.data?.[0]?.scoring_mode;
    const total=(points.data || []).reduce((sum,r)=>sum+Number(r.earned_points),0);
    target.innerHTML=`
      <div class="tournament-title"><h1>${esc(t.name)}</h1></div>
      <p role="status" id="online-notice">${esc(notice)}</p>
      ${joined ? `<div class="participation-line">Punten uit afgeronde wedstrijden: ${esc(total)}.</div>` :
      `<div class="panel stack"><p>Neem deel om je voorspellingen centraal op te slaan.</p>
        ${['published','active'].includes(t.status) ? '<button class="btn" id="online-join">Deelnemen aan dit toernooi</button>' : '<p>Dit toernooi staat niet meer open voor nieuwe deelnemers.</p>'}</div>`}
      <nav class="detail-tabs" aria-label="Toernooionderdelen">${[['predictions','Voorspellingen'],['results','Uitslagen'],['schema','Schema'],['champion','Toernooiwinnaar'],['ranking','Klassement'],['pools','Poules'],['rules','Spelregels & puntentelling']].map(([id,label])=>`<button type="button" data-detail-tab="${id}">${label}</button>`).join('')}</nav><div data-round-controls class="match-controls"><h2 data-list-title>Wedstrijden</h2><select id="online-round" aria-label="Ronde"><option value="">Alle rondes</option>${(rounds.data||[]).map(r=>`<option value="${esc(r.id)}" ${view.round===r.id?'selected':''}>${esc(r.name)}</option>`).join('')}</select></div><section data-detail-panel="predictions">
      <div class="grid online-matches">${predictionMatches.map(m=>{
        const p=myPredictions.get(m.id),earned=myPoints.get(m.id);
        const allowed=joined && open(m,t),closed=!open(m,t),outcome=predictionOutcome(m,p);
        return `<article class="panel compact-match ${closed?'prediction-'+outcome.state+' match-comparable':''}" data-online-match="${esc(m.id)}">
          <div class="match-heading"><small class="muted">${esc(roundNames.get(m.round_id)||'Ronde onbekend')}${m.score_unit!=='goals'&&Number.isInteger(m.first_to)?' – First to '+m.first_to:''}${m.status!=='scheduled'?' · '+esc(labels[m.status]||m.status):''}</small><div class="match-meta"><span class="pill ${allowed?'is-open':'is-closed'}" data-open-state>${allowed?'Open':'Gesloten'}</span><small>${esc(date(m.scheduled_start))}</small></div></div>
          ${joined ? `<form class="prediction-inline" data-online-predict="${esc(m.id)}"><div class="two">
            <div class="field"><label for="online-home-${esc(m.id)}">${esc(m.home_name)}</label><input id="online-home-${esc(m.id)}" aria-label="Score ${esc(m.home_name)}" name="home" inputmode="numeric" type="number" min="0" max="99" step="1" required value="${esc(p?.home_score ?? '')}" ${allowed?'':'disabled'}></div>
            <div class="field"><label for="online-away-${esc(m.id)}">${esc(m.away_name)}</label><input id="online-away-${esc(m.id)}" aria-label="Score ${esc(m.away_name)}" name="away" inputmode="numeric" type="number" min="0" max="99" step="1" required value="${esc(p?.away_score ?? '')}" ${allowed?'':'disabled'}></div>
            </div><p role="status" data-prediction-message></p><button class="btn" aria-live="polite" ${allowed?(p?'disabled':''):'hidden disabled'}>${p?'Opgeslagen':'Opslaan'}</button></form>` : `<div class="teams">${esc(m.home_name)} – ${esc(m.away_name)}</div>`}
          <table class="score-summary" data-score-summary ${allowed?'hidden':''}><thead><tr><th>Jouw voorspelling</th><th class="result-column">Uitslag</th><th>Punten</th></tr></thead><tbody><tr><td>${p?p.home_score+'–'+p.away_score:'—'}</td><td class="result-column">${m.home_score!=null?m.home_score+'–'+m.away_score:'—'}</td><td>${earned?.earned_points??'—'}</td></tr></tbody></table>
          <div class="closed-match-footer" ${closed?'':'hidden'}><small data-prediction-outcome>${esc(outcome.label)}</small><button type="button" class="name-link" data-compare-match="${esc(m.id)}">Vergelijk poule</button></div>
        </article>`;
      }).join('') || ''}</div><p data-empty-predictions>Geen wedstrijden vandaag of open om te voorspellen in deze ronde.</p>
      <div class="row"><button class="btn secondary" id="online-previous" ${page===0?'disabled':''}>Vorige</button>
        <span>Pagina ${page+1}</span><button class="btn secondary" id="online-next" ${(page+1)*size >= activeMatches.length?'disabled':''}>Volgende</button></div></section><section data-detail-panel="results"><h2>Uitslagen per ronde</h2><div class="table-wrap"><table><thead><tr><th>Ronde / wedstrijd</th><th>Jouw voorspelling</th><th class="result-column">Uitslag</th><th>Punten</th></tr></thead><tbody>${shownResults.map(m=>{const p=myPredictions.get(m.id);return `<tr><td>${esc(roundNames.get(m.round_id)||'—')}<br>${esc(m.home_name)} – ${esc(m.away_name)}</td><td>${p?p.home_score+'–'+p.away_score:'—'}</td><td class="result-column">${m.home_score}–${m.away_score}</td><td>${myPoints.get(m.id)?.earned_points??'—'}</td></tr>`;}).join('')||'<tr><td colspan="4">Nog geen uitslagen in deze ronde.</td></tr>'}</tbody></table></div></section><section data-detail-panel="pools"><h2>Mijn poules</h2><div id="private-pools" class="stack" role="region" aria-label="Privépoules"></div></section><section data-detail-panel="schema"></section><section data-detail-panel="champion"></section><section data-detail-panel="ranking"><h2>Klassement</h2><div data-ranking></div></section>`;
    const champion=target.querySelector('[data-detail-panel="champion"]');champion.className='panel stack';
    import('./tournament-management.js?v=refinements-20261017').then(({loadChampionPrediction})=>{if(current(target,ctx))loadChampionPrediction(champion,ctx,t.id,joined).then(data=>{if(!current(target,ctx)||!data)return;const button=target.querySelector('[data-detail-tab=champion]');button.hidden=!data.enabled;if(!data.enabled&&view.tab==='champion')showTab('predictions');});}).catch(()=>{if(current(target,ctx))champion.textContent='Winnaarsvraag laden mislukt.';});
    const rulesPanel=document.createElement('section');rulesPanel.dataset.detailPanel='rules';rulesPanel.className='panel stack';target.append(rulesPanel);
    const renderRules=(bracket)=>{const rds=rounds.data||[];rulesPanel.innerHTML='<h2>Spelregels & puntentelling</h2><p>Voorspel vóór de individuele begintijd. Eén voorspelling telt voor het toernooi en alle bijbehorende poules. Vrijstellingen leveren geen punten op. Voetbal: eindstand vóór strafschoppen; gelijkspel toegestaan.</p><p>'+esc(scoringMode==='additive'?'Exacte score telt bovenop de punten voor de juiste winnaar.':'Exacte score vervangt de punten voor de juiste winnaar.')+'</p><div class="table-wrap"><table><thead><tr><th>Ronde</th><th>Spelvorm</th><th>Juiste winnaar</th><th>Exacte score</th></tr></thead><tbody>'+rds.map(r=>{const rule=roundRules.get(r.id),games=bracket?.matches?.filter(m=>m.round===r.round_order)||list.filter(m=>m.round_id===r.id),formats=[...new Set(games.map(m=>{const unit=m.unit||m.score_unit;return unit==='goals'?'Doelpunten':(unit==='sets'?'Sets':'Legs')+' · first-to '+(m.first_to??'—');}))];return `<tr><td>${esc(r.name)}</td><td>${esc(formats.join(' / ')||'Nog niet vastgelegd')}</td><td>${rule?.winner_points??'—'}</td><td>${rule?.exact_score_points??'—'}</td></tr>`;}).join('')+'</tbody></table></div><p class="hint">De eventuele winnaarbonus en sluiting staan bij Toernooiwinnaar. Een gesloten wedstrijd wordt niet opnieuw geopend door alleen een tijd te wijzigen.</p>';};renderRules(bracket);
    const schema=target.querySelector('[data-detail-panel="schema"]');schema.className='panel stack';
    import('./knockout.js?v=refinements-20261017').then(({loadKnockoutSchema})=>{if(current(target,ctx))loadKnockoutSchema(schema,ctx,t.id,bracket).then(data=>{if(current(target,ctx)&&data)renderRules(data);});});
    const pager=target.querySelector('#online-next').closest('.row');pager.dataset.pagination='';target.append(pager);
    function updatePage(tab=view.tab){
      activeMatches=tab==='results'?resultMatches:visiblePredictions();
      page=Math.max(0,Math.min(page,Math.ceil(activeMatches.length/size)-1));
      const visibleIds=new Set(activeMatches.slice(page*size,(page+1)*size).map(m=>m.id));
      target.querySelectorAll('[data-online-match]').forEach(card=>card.hidden=!visibleIds.has(card.dataset.onlineMatch));
      target.querySelector('[data-empty-predictions]').hidden=visiblePredictions().length>0;
      pager.hidden=!['predictions','results'].includes(tab)||activeMatches.length<=size;
      target.querySelectorAll('[data-detail-panel=results] tbody tr').forEach((row,i)=>row.hidden=i<page*size||i>=(page+1)*size);
      target.querySelector('#online-previous').disabled=page===0;target.querySelector('#online-next').disabled=(page+1)*size>=activeMatches.length;
      pager.querySelector('span').textContent='Pagina '+(page+1);
    }
    let rankingLoaded=false,poolsLoaded=false;
    async function showTab(tab){
      if(view.tab!==tab&&['predictions','results'].includes(tab))page=0;updatePage(tab);
      view.tab=tab;target.querySelectorAll('[data-detail-panel]').forEach(p=>p.hidden=p.dataset.detailPanel!==tab);target.querySelectorAll('[data-detail-tab]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.detailTab===tab)));target.querySelector('[data-round-controls]').hidden=!['predictions','results'].includes(tab);target.querySelector('[data-list-title]').textContent=tab==='results'?'Uitslagen':'Wedstrijden';pager.hidden=!['predictions','results'].includes(tab)||activeMatches.length<=size;
      if(tab==='pools'&&!poolsLoaded){poolsLoaded=true;ctx.onPools?.(target.querySelector('#private-pools'),joined);}
      if(tab==='ranking'&&!rankingLoaded){rankingLoaded=true;loadTournamentRankings(target.querySelector('[data-ranking]'),ctx,t.id);}
    }
    target.querySelectorAll('[data-detail-tab]').forEach(b=>b.onclick=()=>showTab(b.dataset.detailTab));
    const hasDraft=()=>!!target.querySelector('[data-ko-dirty="true"]')||[...target.querySelectorAll('input')].some(i=>i.value!==i.defaultValue);
    const discard=()=>!hasDraft() || confirm('Niet-opgeslagen wijzigingen laten vervallen?');
    window.addEventListener('beforeunload',event=>{
      if(current(target,ctx)&&hasDraft()){event.preventDefault();event.returnValue='';}
    },{signal:ctx.signal});
    showTab(view.tab);
    let dayTimer;
    const watchDay=()=>{const midnight=new Date();midnight.setHours(24,0,0,0);dayTimer=setTimeout(()=>{if(current(target,ctx)){updatePage();watchDay();}},Math.max(100,midnight.getTime()-Date.now()+50));};
    watchDay();ctx.signal.addEventListener('abort',()=>clearTimeout(dayTimer),{once:true});
    target.querySelector('#online-round').onchange=e=>{if(discard()){view.round=e.target.value;loadTournamentDetail(host,ctx,0,'',view);}else e.target.value=view.round;};
    target.querySelector('#online-previous').onclick=()=>{page--;updatePage();};
    target.querySelector('#online-next').onclick=()=>{page++;updatePage();};
    const join=target.querySelector('#online-join');
    if (join) join.onclick=async()=>{
      join.disabled=true;
      try {
        const {error}=await ctx.supabase.rpc('join_tournament',{p_tournament_id:t.id});
        if (!current(target,ctx)) return;
        if (error) throw new Error(error.message);
        await loadTournamentDetail(host,ctx,page,'Je neemt nu deel aan dit toernooi.',view);
      } catch(error) {if(current(target,ctx)){target.querySelector('#online-notice').textContent=error.message;join.disabled=false;}}
    };
    async function compareMatch(m){try{const {showMatchPoolComparison}=await import('./pool-comparison.js?v=match-popup-20261017');if(current(target,ctx))showMatchPoolComparison(ctx,t.id,m);}catch(error){if(current(target,ctx))target.querySelector('#online-notice').textContent='Vergelijken laden mislukt. Probeer opnieuw.';}}
    target.querySelectorAll('[data-online-match]').forEach(card=>{const m=list.find(m=>m.id===card.dataset.onlineMatch);card.querySelector('[data-compare-match]').onclick=()=>compareMatch(m);card.addEventListener('click',e=>{if(!open(m,t)&&!e.target.closest('button,input,select,a'))compareMatch(m);});});
    target.querySelectorAll('[data-online-predict]').forEach(form=>{
      const m=list.find(m=>m.id===form.dataset.onlinePredict);
      const message=form.querySelector('[data-prediction-message]');
      const button=form.querySelector('button');
      const syncSaved=()=>{
        const saved=myPredictions.has(m.id)&&['home','away'].every(name=>form.elements[name].value===form.elements[name].defaultValue);
        button.textContent=saved?'Opgeslagen':'Opslaan';button.disabled=!open(m,t)||saved;
      };
      form.addEventListener('input',()=>{message.textContent='';message.className='';syncSaved();});

      const disable=()=>{
        form.querySelectorAll('input,button').forEach(e=>e.disabled=true);
        const card=form.closest('article'),outcome=predictionOutcome(m,myPredictions.get(m.id));card.classList.add('match-comparable','prediction-'+outcome.state);card.querySelector('.closed-match-footer').hidden=false;card.querySelector('[data-prediction-outcome]').textContent=outcome.label;const state=card.querySelector('[data-open-state]');state.textContent='Gesloten';state.className='pill is-closed';form.querySelector('button').hidden=true;const summary=form.closest('article').querySelector('[data-score-summary]');if(summary)summary.hidden=false;updatePage();
      };
      if (open(m,t)) {
        // Keep fields from appearing editable after the deadline, including long-open tabs.
        let timer;
        const expire=()=>{
          if (!current(target,ctx)) return;
          const remaining=Date.parse(m.scheduled_start)-Date.now();
          if(remaining<=0){disable();message.textContent='De individuele deadline is verstreken.';}
          else timer=setTimeout(expire,Math.min(remaining,2147483647));
        };
        expire();ctx.signal.addEventListener('abort',()=>clearTimeout(timer),{once:true});
      }
      form.onsubmit=async event=>{
        event.preventDefault();
        if (!open(m,t)) {disable();message.textContent='Deze wedstrijd is gesloten. Vernieuw voor de actuele status.';return;}
        const home=Number(form.elements.home.value),away=Number(form.elements.away.value);
        if (![home,away].every(n=>Number.isInteger(n)&&n>=0&&n<=99) ||
          (m.score_unit!=='goals' && !((home===m.first_to && away<m.first_to)||(away===m.first_to && home<m.first_to)))) {
          message.textContent=m.score_unit==='goals'?'Vul een geldige eindstand voor dit wedstrijdformaat in.':`Score ongeldig: maximale aantal punten voor de winnaar is ${m.first_to}`;return;
        }
        button.disabled=true;button.textContent='Opslaan…';message.textContent='';
        const fields=[...form.querySelectorAll('input')];fields.forEach(i=>i.disabled=true);
        try {
          const {error}=await ctx.supabase.rpc('submit_match_prediction',{p_match_id:m.id,p_home_score:home,p_away_score:away});
          if (!current(target,ctx)) return;
          if(error) throw new Error(error.message);
          // Preserve unsaved input on other cards; only update the submitted form.
          form.elements.home.value=form.elements.home.defaultValue=String(home);form.elements.away.value=form.elements.away.defaultValue=String(away);myPredictions.set(m.id,{home_score:home,away_score:away});const cell=form.closest('article').querySelector('[data-score-summary] td');if(cell)cell.textContent=home+'–'+away;
          syncSaved();message.textContent='';message.className='';
        } catch(error) {if(current(target,ctx)){button.textContent='Opslaan';message.textContent='Opslaan mislukt: '+error.message;message.className='error';}}
        finally {if(current(target,ctx)){const allowed=open(m,t);syncSaved();fields.forEach(i=>i.disabled=!allowed);if(!allowed)disable();}}
      };
    });
  } catch(error) {showError(target,ctx,error,()=>loadTournamentDetail(host,ctx,page,'',view));}
}

// Existing membership RLS and leaderboard RPC remain authoritative for private pools.
async function loadTournamentRankings(host,ctx,tournamentId){
 const panel=document.createElement('section');panel.className='stack';host.replaceChildren(panel);
 const valid=()=>current(panel,ctx);
 const {renderLeaderboard,loadTournamentComparison,loadPoolComparison}=await import('./pool-comparison.js?v=match-popup-20261017');
 panel.innerHTML='<h3>Toernooiklassement</h3><div data-global-ranking role="status">Klassement laden…</div><h3>Mijn pouleklassementen</h3><div data-pool-rankings class="stack" role="region" aria-label="Mijn pouleklassementen">Poules laden…</div>';
 const global=panel.querySelector('[data-global-ranking]'),poolsHost=panel.querySelector('[data-pool-rankings]');
 const report=(host,error,retry)=>{host.innerHTML='<p role="alert"></p><button type="button" class="ghost">Opnieuw proberen</button>';host.querySelector('p').textContent=error.message||'Ophalen mislukt.';host.querySelector('button').onclick=retry;};
 async function loadGlobal(){try{const r=await ctx.supabase.rpc('get_tournament_leaderboard',{p_tournament_id:tournamentId,p_pool_id:null,p_round_id:null});if(!valid())return;if(r.error)throw r.error;renderLeaderboard(global,r.data||[],(host,member,name)=>loadTournamentComparison(host,ctx,tournamentId,member,name),{userId:ctx.userId});}catch(error){if(valid())report(global,error,loadGlobal);}}
 async function loadPools(){try{const [memberships,pools]=await Promise.all([ctx.supabase.from('pool_members').select('pool_id').eq('user_id',ctx.userId),ctx.supabase.from('pools').select('id,name,tournament_id').eq('tournament_id',tournamentId).order('name')]);if(!valid())return;if(memberships.error||pools.error)throw memberships.error||pools.error;
   const ids=new Set((memberships.data||[]).map(m=>m.pool_id)),mine=(pools.data||[]).filter(p=>p.tournament_id===tournamentId&&ids.has(p.id));poolsHost.replaceChildren();if(!mine.length){poolsHost.textContent='Je doet voor dit toernooi nog niet mee aan een poule.';return;}
   for(const pool of mine){const details=document.createElement('details');details.className='pool-ranking';const summary=document.createElement('summary');summary.textContent=pool.name;const content=document.createElement('div');content.className='stack';details.append(summary,content);poolsHost.append(details);let loaded=false,loading=false;
    async function load(){if(loading)return;loading=true;content.textContent='Klassement laden…';try{const r=await ctx.supabase.rpc('get_tournament_leaderboard',{p_tournament_id:tournamentId,p_pool_id:pool.id,p_round_id:null});if(!valid()||!details.isConnected)return;if(r.error)throw r.error;loaded=true;renderLeaderboard(content,r.data||[],(host,member,name)=>loadPoolComparison(host,ctx,pool,member,name),{userId:ctx.userId});}catch(error){if(valid()&&details.isConnected)report(content,error,load);}finally{loading=false;}}
    details.ontoggle=()=>{if(details.open&&!loaded)load();};
   }
  }catch(error){if(valid())report(poolsHost,error,loadPools);}}
 await Promise.all([loadGlobal(),loadPools()]);
}
