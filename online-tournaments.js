export function predictionValidationMessage(match,homeValue,awayValue){
 const values=[homeValue,awayValue];
 if(values.some(v=>String(v).trim()===''))return 'Vul beide scores in.';
 const [home,away]=values.map(Number);
 if(![home,away].every(n=>Number.isInteger(n)&&n>=0&&n<=99))return 'Gebruik hele getallen van 0 t/m 99.';
 if(match.score_unit==='goals')return '';
 const ft=Number(match.first_to);
 if(!Number.isInteger(ft)||ft<1)return 'Het wedstrijdformaat is nog niet bekend.';
 if((home===ft&&away<ft)||(away===ft&&home<ft))return '';
 if(home===away)return 'Gelijkspel is niet mogelijk. Eén speler moet precies '+ft+' halen.';
 return 'De winnaar moet precies '+ft+' halen; de andere score moet lager zijn.';
}
import {renderArchivedTournament} from './tournament-archive.js?v=archive-20261022';
import {showTournamentImage} from './tournament-images.js?v=header-20261017';
// Public user screens. Supabase remains authoritative for access, scores and deadlines.
const labels = {announced:'Vooraankondiging',published:'Gepubliceerd',active:'Actief',completed:'Afgerond',archived:'Gepauzeerd / archief',scheduled:'Gepland',postponed:'Uitgesteld',live:'Bezig',finished:'Afgerond',cancelled:'Geannuleerd'};
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date = value => value && Number.isFinite(Date.parse(value))
  ? new Intl.DateTimeFormat('nl-NL',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)) : 'NNB';
const resultDate=value=>value&&Number.isFinite(Date.parse(value))?new Intl.DateTimeFormat('nl-NL',{day:'numeric',month:'short',year:'numeric'}).format(new Date(value)):'';
const dateRange=(start,end)=>{const fmt=v=>v&&Number.isFinite(Date.parse(v))?new Intl.DateTimeFormat('nl-NL',{dateStyle:'medium'}).format(new Date(v)):'';const a=fmt(start),b=fmt(end);return a&&b?(a===b?a:a+' – '+b):a||'Datums volgen';};
const localDay=value=>{const d=new Date(value);return Number.isFinite(d.getTime())?`${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`:'';};
const current = (target,ctx) => target.isConnected && !ctx.signal.aborted && ctx.isCurrent();
const open = (m,t) => ['published','active'].includes(t.status) && m.predictions_enabled === true &&
  m.needs_review === false && m.round_id != null &&
  m.status === 'scheduled' && m.actual_start == null && m.home_score == null && m.away_score == null &&
  (m.start_time_confirmed === true && Date.parse(m.scheduled_start) > Date.now() || m.scheduled_start == null && t.source_automatic === true && Date.parse(t.starts_at) > Date.now() && m.participants_known === true) &&
  (m.score_unit === 'goals' ? m.first_to == null : ['sets','legs'].includes(m.score_unit) && Number.isInteger(m.first_to) && m.first_to >= 1 && m.first_to <= 99);

export function predictionOutcome(m,p){
 if(m.status!=='finished'||m.home_score==null||m.away_score==null)return {state:'pending',label:m.status==='cancelled'?'Geannuleerd':m.status==='postponed'?'Uitgesteld':'Wacht op uitslag'};
 if(!p)return {state:'unpredicted',label:'Niet voorspeld'};
 if(p.home_score===m.home_score&&p.away_score===m.away_score)return {state:'exact',label:'Exact goed'};
 if(Math.sign(p.home_score-p.away_score)===Math.sign(m.home_score-m.away_score))return {state:'winner',label:'Winnaar goed'};
 return {state:'wrong',label:'Onjuist'};
}

export async function loadTournamentCatalog(target,ctx) {
 try{
  const response=await ctx.supabase.rpc('get_active_tournament_catalog');if(!current(target,ctx))return;if(response.error)throw response.error;
  const all=response.data?.tournaments||[],joined=new Set(all.filter(t=>t.joined).map(t=>t.id));
  const card=(t,archived=false)=>`<article class="panel tournament-tile"><button type="button" class="tournament-tile-link" data-online-open="${esc(t.id)}"><span class="tournament-art" data-tour-art="${esc(t.id)}" aria-hidden="true"></span><span class="tournament-tile-body"><h2>${esc(t.name)}</h2>${archived?'<span class="mini">Definitief eindklassement</span>':t.status==='announced'?'<span class="mini">Binnenkort · deelname opent later</span>':`<span class="prediction-count mini" data-tour-count="${esc(t.id)}" role="status">Open wedstrijden laden…</span>`}<span class="mini muted game-dates">${esc(dateRange(t.starts_at,t.ends_at))}</span></span><span class="tile-arrow" aria-hidden="true">›</span></button></article>`;
  const mine=all.filter(t=>t.joined).sort((a,b)=>(Date.parse(b.starts_at)||-Infinity)-(Date.parse(a.starts_at)||-Infinity)),available=all.filter(t=>!t.joined&&['announced','published','active'].includes(t.status));
  target.innerHTML=`<h1>Mijn spellen</h1><div class="grid" data-my-tournaments>${mine.map(t=>card(t)).join('')||'<p>Je doet nog niet mee aan een toernooi.</p>'}</div><h2 class="available-title">Beschikbare spellen</h2><div class="grid" data-open-tournaments>${available.map(t=>card(t)).join('')||'<p>Geen andere open toernooien beschikbaar.</p>'}</div><details class="admin-fold game-archive" data-player-archive><summary>Spelarchief (${Number(response.data?.archive_count)||0})</summary><div class="grid" data-archive-list></div></details>`;
  function bind(host){host.querySelectorAll('[data-tour-art]').forEach(el=>showTournamentImage(el,ctx.supabase,el.dataset.tourArt));host.querySelectorAll('[data-online-open]').forEach(b=>b.onclick=()=>ctx.onOpen(b.dataset.onlineOpen));}bind(target);
  let loaded=false,loading=false;const archive=target.querySelector('[data-player-archive]'),archiveHost=target.querySelector('[data-archive-list]');
  async function readArchive(){if(loading||loaded)return;loading=true;archiveHost.textContent='Archief laden…';try{const r=await ctx.supabase.rpc('get_tournament_archive_catalog');if(!current(target,ctx))return;if(r.error)throw r.error;archiveHost.innerHTML=(r.data||[]).map(t=>card(t,true)).join('')||'<p>Nog geen definitieve klassementen.</p>';bind(archiveHost);loaded=true;}catch(error){if(current(target,ctx)){archiveHost.innerHTML='<p role="alert"></p><button class="ghost">Opnieuw proberen</button>';archiveHost.querySelector('p').textContent=error.message;archiveHost.querySelector('button').onclick=readArchive;}}finally{loading=false;}}
  archive.ontoggle=()=>{if(archive.open)readArchive();};
  let timer;const counts=async()=>{try{const r=await ctx.supabase.rpc('get_tournament_prediction_counts');if(!current(target,ctx))return;if(r.error)throw r.error;const map=new Map((r.data?.tournaments||[]).map(t=>[t.id,t]));target.querySelectorAll('[data-tour-count]').forEach(el=>{const c=map.get(el.dataset.tourCount)||{open_count:0,remaining_count:0};el.innerHTML=c.completed?'<strong>Toernooi afgelopen</strong>':`<span>${Number(c.open_count)||0} wedstrijden open om te voorspellen</span>${joined.has(el.dataset.tourCount)?`<strong class="prediction-attention ${c.remaining_count>0?'remaining':c.open_count>0?'complete':''}">${c.remaining_count>0?'Nog '+Number(c.remaining_count)+' te voorspellen':c.open_count>0?'Alle open wedstrijden voorspeld ✓':'Geen open wedstrijden'}</strong>`:''}`;});const next=Date.parse(r.data?.next_deadline)-Date.parse(r.data?.server_now);if(next>0)timer=setTimeout(counts,Math.min(next+100,2147483647));}catch{if(current(target,ctx))target.querySelectorAll('[data-tour-count]').forEach(el=>el.textContent='Aantal open wedstrijden niet beschikbaar.');}};ctx.signal.addEventListener('abort',()=>clearTimeout(timer),{once:true});if(all.length)counts();
 }catch(error){showError(target,ctx,error,()=>loadTournamentCatalog(target,ctx));}
}

function renderTournamentIntro(target,ctx,t,onPreview,onJoin,onPools){
  const upcoming=Date.parse(t.starts_at)>Date.now();
  target.classList.add('tournament-intro');
  target.innerHTML=`<article class="intro-card"><div class="tournament-art" data-intro-art></div><div><h1>${esc(t.name)}</h1><p class="muted">${esc(dateRange(t.starts_at,t.ends_at))}</p><p class="mini">Start toernooi: ${esc(date(t.starts_at))}</p></div></article>
    <section class="intro-hero"><div class="tournament-art intro-art" data-intro-art></div><div class="intro-countdown"><p data-countdown-title>${upcoming?'Toernooi begint over':'Toernooi begonnen'}</p><div class="countdown-digits" data-countdown aria-label="Tijd tot toernooistart"></div></div></section>
    <section class="intro-invitation"><h2>Voorspel de wedstrijden.<br>Speel mee met ${esc(t.name)}.</h2><p class="muted">Daag je vrienden uit en volg samen het klassement.</p><button class="btn intro-join" id="intro-join">Speel mee <span aria-hidden="true">→</span></button><p role="status" data-intro-message></p>${onPools?'<button class="btn secondary" data-intro-pools>Poules</button>':''}${onPreview&&t.status!=='announced'?'<button class="ghost" data-intro-preview>Bekijk schema en spelregels</button>':''}</section>
    <section class="intro-explanation panel"><h2>Zo werkt het</h2><p>Vul je scorevoorspellingen in vóór de wedstrijddeadline. Verdien punten voor de juiste winnaar en de exacte score.</p><p>Je voorspellingen tellen mee voor het toernooi en je poules. Maak na deelname een poule of sluit je aan bij vrienden.</p></section>`;
  target.querySelectorAll('[data-intro-art]').forEach(el=>showTournamentImage(el,ctx.supabase,t.id,t.name));
  const button=target.querySelector('#intro-join'),message=target.querySelector('[data-intro-message]');let busy=false,timer;
  const canJoin=()=>['published','active'].includes(t.status)&&!(Date.parse(t.ends_at)<=Date.now());
  function tick(){if(!current(target,ctx)){clearInterval(timer);return;}
    const left=Math.max(0,Date.parse(t.starts_at)-Date.now()),digits=target.querySelector('[data-countdown]');
    if(left>0){const sec=Math.floor(left/1000);digits.innerHTML=[[Math.floor(sec/86400),'dagen'],[Math.floor(sec/3600)%24,'uur'],[Math.floor(sec/60)%60,'min'],[sec%60,'sec']].map(([n,label])=>`<span><strong>${String(n).padStart(2,'0')}</strong><small>${label}</small></span>`).join('');}
    else{digits.hidden=true;target.querySelector('[data-countdown-title]').textContent=Date.parse(t.ends_at)<=Date.now()?'Toernooi afgelopen':Number.isFinite(Date.parse(t.starts_at))?'Toernooi begonnen':'Starttijd NNB';}
    button.hidden=!canJoin();button.disabled=busy;
    if(!busy&&!canJoin())message.textContent=t.status==='announced'?'Binnenkort · deelname opent later':'Dit toernooi staat niet meer open voor nieuwe deelnemers.';
  }
  button.onclick=async()=>{if(busy||!canJoin())return;busy=true;button.disabled=true;message.textContent='Deelnemen…';try{await onJoin();}catch(error){if(current(target,ctx))message.textContent='Deelnemen mislukt: '+error.message;}finally{busy=false;if(current(target,ctx))button.disabled=!canJoin();}};
  target.querySelector('[data-intro-preview]')?.addEventListener('click',onPreview);
  target.querySelector('[data-intro-pools]')?.addEventListener('click',onPools);
  tick();timer=setInterval(tick,1000);ctx.signal.addEventListener('abort',()=>clearInterval(timer),{once:true});
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
    const archive=await ctx.supabase.rpc('get_tournament_archive',{p_id:ctx.tournamentId});
    if(!current(target,ctx))return;if(archive.error)throw archive.error;if(archive.data?.archived){renderArchivedTournament(target,ctx,archive.data);return;}
    const [tour,entry] = await Promise.all([
      ctx.supabase.from('tournaments').select('id,name,status,starts_at,ends_at').eq('id',ctx.tournamentId).single(),
      ctx.supabase.from('tournament_entries').select('tournament_id').eq('tournament_id',ctx.tournamentId).eq('user_id',ctx.userId)
    ]);
    if (!current(target,ctx)) return;
    if (tour.error || entry.error || !tour.data) throw new Error((tour.error || entry.error)?.message || 'Toernooi niet beschikbaar.');
    const t={...tour.data},joined=!!entry.data?.length;
    if(!joined&&!view.preview){
      renderTournamentIntro(target,ctx,t,()=>loadTournamentDetail(host,ctx,0,'',{...view,tab:'schema',preview:true}),async()=>{
        const {error}=await ctx.supabase.rpc('join_tournament',{p_tournament_id:t.id});
        if(error)throw Error(error.message);
        if(current(target,ctx))await loadTournamentDetail(host,ctx,0,'Je neemt nu deel aan dit toernooi.',{tab:'predictions',round:''});
      },ctx.onPools&&['published','active'].includes(t.status)?()=>loadTournamentDetail(host,ctx,0,'',{...view,tab:'pools',preview:true}):null);return;
    }
    if(t.status==='announced'){renderTournamentIntro(target,ctx,t,null,null);return;}

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
    t.source_automatic=!!bracket?.score_source?.automatic_setup;
    const known=new Set((bracket?.matches||[]).filter(m=>m.home_slot&&m.away_slot&&!m.bye).map(m=>m.id));
    (matches.data||[]).forEach(m=>m.participants_known=known.has(m.id));
    const byes=new Set((bracket?.matches||[]).filter(m=>m.bye).map(m=>m.id));
    const allMatches=(matches.data||[]).filter(m=>!byes.has(m.id));
    const ended=Date.parse(t.ends_at)<=Date.now()||t.status==='completed'||allMatches.length>0&&allMatches.every(m=>m.status==='finished'&&m.home_score!=null&&m.away_score!=null);
    if(ended&&view.tab==='predictions')view.tab='results';
    const selected=allMatches.filter(m=>!view.round||m.round_id===view.round);
    const resultMatches=selected.filter(m=>m.home_score!=null).sort((a,b)=>(Date.parse(b.actual_start||b.scheduled_start)||-Infinity)-(Date.parse(a.actual_start||a.scheduled_start)||-Infinity));
    const notStarted=m=>m.status==='scheduled'&&m.actual_start==null&&m.home_score==null&&m.away_score==null&&(m.scheduled_start==null||Date.parse(m.scheduled_start)>Date.now());
    const predictionOrder=()=>[...selected].sort((a,b)=>Number(notStarted(b))-Number(notStarted(a)));
    const visiblePredictions=()=>predictionOrder().filter(m=>localDay(m.scheduled_start)===localDay(new Date())||open(m,t));
    let activeMatches=view.tab==='results'?resultMatches:visiblePredictions();
    page=Math.max(0,Math.min(page,Math.ceil(activeMatches.length/size)-1));
    const list=selected;
    const predictionMatches=predictionOrder();
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
      <nav class="detail-tabs" aria-label="Toernooionderdelen">${[['predictions','Voorspellingen'],['results','Uitslagen'],['schema','Schema'],['champion','Toernooiwinnaar'],['ranking','Klassement'],['pools','Poules'],['rules','Spelregels']].filter(([id])=>!ended||id!=='predictions').map(([id,label])=>`<button type="button" data-detail-tab="${id}">${label}</button>`).join('')}</nav><div data-round-controls class="match-controls"><h2 data-list-title>Wedstrijden</h2><select id="online-round" aria-label="Ronde"><option value="">Alle rondes</option>${(rounds.data||[]).map(r=>`<option value="${esc(r.id)}" ${view.round===r.id?'selected':''}>${esc(r.name)}</option>`).join('')}</select></div><section data-detail-panel="predictions">
      <div class="grid online-matches">${predictionMatches.map(m=>{
        const p=myPredictions.get(m.id),earned=myPoints.get(m.id);
        const allowed=joined && open(m,t),closed=!open(m,t),outcome=predictionOutcome(m,p);
        return `<article class="panel compact-match ${closed?'prediction-'+outcome.state+' match-comparable':'prediction-open'}" data-online-match="${esc(m.id)}">
          <div class="match-heading"><small class="muted">${esc(roundNames.get(m.round_id)||'Ronde onbekend')}${m.score_unit!=='goals'&&Number.isInteger(m.first_to)?' – First to '+m.first_to:''}</small><div class="match-meta"><span class="pill ${allowed?'is-open':'is-closed'}" data-open-state hidden></span><small>${esc(date(m.scheduled_start))}</small></div></div>
          <div class="match-contest"><strong>${esc(m.home_name).replace(' ','<br>')}</strong><span class="match-final-score" aria-label="Uitslag">${m.home_score!=null?m.home_score+' - '+m.away_score:'–'}</span><strong>${esc(m.away_name).replace(' ','<br>')}</strong></div>
          ${joined ? `<form class="prediction-inline prediction-autosave" data-online-predict="${esc(m.id)}" ${closed?'hidden':''}><div class="two">
            <div class="field"><label class="sr-only" for="online-home-${esc(m.id)}">${esc(m.home_name)}</label><input id="online-home-${esc(m.id)}" aria-label="Score ${esc(m.home_name)}" class="score-tone score-tone-open" name="home" inputmode="numeric" type="number" min="0" max="99" step="1" required value="${esc(p?.home_score ?? '')}" ${allowed?'':'disabled'}></div>
            <div class="field"><label class="sr-only" for="online-away-${esc(m.id)}">${esc(m.away_name)}</label><input id="online-away-${esc(m.id)}" aria-label="Score ${esc(m.away_name)}" class="score-tone score-tone-open" name="away" inputmode="numeric" type="number" min="0" max="99" step="1" required value="${esc(p?.away_score ?? '')}" ${allowed?'':'disabled'}></div>
            </div><p role="status" data-prediction-message></p><button type="button" class="btn secondary" data-retry-prediction hidden>Opnieuw proberen</button></form>` : ''}
          <div class="closed-score-summary" data-score-summary ${closed?'':'hidden'}><span class="prediction-chip score-tone score-tone-${outcome.state}" data-saved-score><span class="sr-only">Jouw voorspelling: </span><span data-saved-value>${p?p.home_score+' - '+p.away_score:'—'}</span></span><span class="match-points">${earned?.earned_points??'—'} pt</span></div>
        </article>`;
      }).join('') || ''}</div><p data-empty-predictions>Geen wedstrijden vandaag of open om te voorspellen in deze ronde.</p>
      <div class="row"><button class="btn secondary" id="online-previous" ${page===0?'disabled':''}>Vorige</button>
        <span>Pagina ${page+1}</span><button class="btn secondary" id="online-next" ${(page+1)*size >= activeMatches.length?'disabled':''}>Volgende</button></div></section><section data-detail-panel="results"><div class="results-wrap"><table class="results-table"><thead><tr><th>Ronde / wedstrijd</th><th><span class="results-full-label">Jouw voorspelling</span><span class="results-short-label">Jij</span></th><th class="result-column">Uitslag</th><th><abbr title="Punten">Pt</abbr></th></tr></thead><tbody>${shownResults.map(m=>{const p=myPredictions.get(m.id);return `<tr><td>${esc(roundNames.get(m.round_id)||'—')}${m.scheduled_start?' · '+esc(resultDate(m.scheduled_start)):''}<br>${esc(m.home_name)} – ${esc(m.away_name)}</td><td>${p?`<span class="score-tone score-tone-${predictionOutcome(m,p).state}">${p.home_score} - ${p.away_score}</span>`:'—'}</td><td class="result-column">${m.home_score} - ${m.away_score}</td><td>${myPoints.get(m.id)?.earned_points??'—'}</td></tr>`;}).join('')||'<tr><td colspan="4">Nog geen uitslagen in deze ronde.</td></tr>'}</tbody></table></div></section><section data-detail-panel="pools"><h2>Mijn poules</h2><div id="private-pools" class="stack" role="region" aria-label="Privépoules"></div></section><section data-detail-panel="schema"></section><section data-detail-panel="champion"></section><section data-detail-panel="ranking"><h2>Klassement</h2><div data-ranking></div></section>`;
    const champion=target.querySelector('[data-detail-panel="champion"]');champion.className='panel stack';
    import('./tournament-management.js?v=layout-findings-20261023').then(({loadChampionPrediction})=>{if(current(target,ctx))loadChampionPrediction(champion,ctx,t.id,joined).then(data=>{if(!current(target,ctx)||!data)return;const button=target.querySelector('[data-detail-tab=champion]');button.hidden=!data.enabled;if(!data.enabled&&view.tab==='champion')showTab('predictions');});}).catch(()=>{if(current(target,ctx))champion.textContent='Winnaarsvraag laden mislukt.';});
    const rulesPanel=document.createElement('section');rulesPanel.dataset.detailPanel='rules';rulesPanel.className='panel stack';target.append(rulesPanel);
    const renderRules=(bracket)=>{const rds=rounds.data||[];rulesPanel.innerHTML='<h2>Spelregels</h2><p>Voorspel vóór de individuele begintijd. Bij Mastercaller-wedstrijden met tijd NNB kun je alvast voorspellen tot de toernooistart; zodra de tijd bekend is geldt de wedstrijdtijd. Eén voorspelling telt voor het toernooi en alle bijbehorende poules. Vrijstellingen leveren geen punten op. Voetbal: eindstand vóór strafschoppen; gelijkspel toegestaan.</p><p>'+esc(scoringMode==='additive'?'Exacte score telt bovenop de punten voor de juiste winnaar.':'Exacte score vervangt de punten voor de juiste winnaar.')+'</p><div class="table-wrap"><table class="rules-table"><thead><tr><th>Ronde</th><th>Spelvorm</th><th>Juiste winnaar</th><th>Exacte score</th></tr></thead><tbody>'+rds.map(r=>{const rule=roundRules.get(r.id),games=bracket?.matches?.filter(m=>m.round===r.round_order)||list.filter(m=>m.round_id===r.id),formats=[...new Set(games.map(m=>{const unit=m.unit||m.score_unit;return unit==='goals'?'Doelpunten':(unit==='sets'?'Sets':'Legs')+' · first-to '+(m.first_to??'—');}))];return `<tr><td>${esc(r.name)}</td><td>${esc(formats.join(' / ')||'Nog niet vastgelegd')}</td><td>${rule?.winner_points??'—'}</td><td>${rule?.exact_score_points??'—'}</td></tr>`;}).join('')+'</tbody></table></div><p class="hint">De eventuele winnaarbonus en sluiting staan bij Toernooiwinnaar. Een gesloten wedstrijd wordt niet opnieuw geopend door alleen een tijd te wijzigen.</p>';};renderRules(bracket);
    const schema=target.querySelector('[data-detail-panel="schema"]');schema.className='panel stack';
    import('./knockout.js?v=polish-20261023').then(({loadKnockoutSchema})=>{if(current(target,ctx))loadKnockoutSchema(schema,ctx,t.id,bracket).then(data=>{if(current(target,ctx)&&data)renderRules(data);});});
    const pager=target.querySelector('#online-next').closest('.row');pager.dataset.pagination='';target.append(pager);
    function updatePage(tab=view.tab){
      activeMatches=tab==='results'?resultMatches:visiblePredictions();
      const grid=target.querySelector('.online-matches'),cards=new Map([...grid.children].map(card=>[card.dataset.onlineMatch,card]));
      predictionOrder().forEach((m,i)=>{const card=cards.get(m.id);if(card&&grid.children[i]!==card)grid.insertBefore(card,grid.children[i]||null);});
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
      if(ended&&tab==='predictions')tab='results';
      if(view.tab!==tab&&['predictions','results'].includes(tab))page=0;updatePage(tab);
      view.tab=tab;target.querySelectorAll('[data-detail-panel]').forEach(p=>p.hidden=p.dataset.detailPanel!==tab);target.querySelectorAll('[data-detail-tab]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.detailTab===tab)));target.querySelector('[data-round-controls]').hidden=!['predictions','results'].includes(tab);target.querySelector('[data-list-title]').textContent=tab==='results'?'Uitslagen':'Wedstrijden';pager.hidden=!['predictions','results'].includes(tab)||activeMatches.length<=size;
      if(tab==='pools'&&!poolsLoaded){poolsLoaded=true;ctx.onPools?.(target.querySelector('#private-pools'),joined);}
      if(tab==='ranking'&&!rankingLoaded){rankingLoaded=true;loadTournamentRankings(target.querySelector('[data-ranking]'),ctx,t.id);}
    }
    target.querySelectorAll('[data-detail-tab]').forEach(b=>b.onclick=()=>showTab(b.dataset.detailTab));
    const pendingSaves=[];
    const hasDraft=()=>!!target.querySelector('[data-ko-dirty="true"]')||[...target.querySelectorAll('input')].some(i=>i.value!==i.defaultValue);
    const discard=()=>!hasDraft() || confirm('Niet-opgeslagen wijzigingen laten vervallen?');
    window.addEventListener('beforeunload',event=>{
      if(current(target,ctx)&&hasDraft()){event.preventDefault();event.returnValue='';}
    },{signal:ctx.signal});
    showTab(view.tab);
    let dayTimer;
    const watchDay=()=>{const midnight=new Date();midnight.setHours(24,0,0,0);dayTimer=setTimeout(()=>{if(current(target,ctx)){updatePage();watchDay();}},Math.max(100,midnight.getTime()-Date.now()+50));};
    watchDay();ctx.signal.addEventListener('abort',()=>clearTimeout(dayTimer),{once:true});
    target.querySelector('#online-round').onchange=async e=>{const round=e.target.value;await Promise.all(pendingSaves.map(save=>save()));if(!current(target,ctx))return;if(discard()){view.round=round;loadTournamentDetail(host,ctx,0,'',view);}else e.target.value=view.round;};
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
    async function compareMatch(m){try{const {showMatchPoolComparison}=await import('./pool-comparison.js?v=layout-findings-20261023');if(current(target,ctx))showMatchPoolComparison(ctx,t.id,m,predictionOutcome(m,myPredictions.get(m.id)).label);}catch(error){if(current(target,ctx))target.querySelector('#online-notice').textContent='Vergelijken laden mislukt. Probeer opnieuw.';}}
    target.querySelectorAll('[data-online-match]').forEach(card=>{const m=list.find(m=>m.id===card.dataset.onlineMatch);const accessible=()=>{if(!open(m,t)){card.tabIndex=0;card.setAttribute('role','button');card.setAttribute('aria-label',m.home_name+' – '+m.away_name+'. Vergelijk voorspellingen in je poule');}};accessible();card.addEventListener('click',e=>{if(!open(m,t)&&!e.target.closest('button,input,select,a'))compareMatch(m);});card.addEventListener('keydown',e=>{if(e.target===card&&!open(m,t)&&['Enter',' '].includes(e.key)){e.preventDefault();compareMatch(m);}});});
    target.querySelectorAll('[data-online-predict]').forEach(form=>{
      const m=list.find(m=>m.id===form.dataset.onlinePredict);
      const message=form.querySelector('[data-prediction-message]');
      const button=form.querySelector('button');
      let debounce,deadlineTimer,inFlight=null,revision=0,stopped=false;
      const values=()=>[form.elements.home.value,form.elements.away.value];
      const validation=()=>predictionValidationMessage(m,...values());
      const valid=()=>!validation();
      const saved=()=>!inFlight&&myPredictions.has(m.id)&&['home','away'].every(name=>form.elements[name].value===form.elements[name].defaultValue);
      const say=(text,error=false)=>{message.textContent=text;message.className=error?'prediction-validation error score-tone score-tone-wrong':'mini muted';message.setAttribute('aria-live',error?'assertive':'polite');form.querySelectorAll('input').forEach(input=>input.setAttribute('aria-invalid',String(error))); };
      const disable=()=>{
        stopped=true;clearTimeout(debounce);clearTimeout(deadlineTimer);
        form.querySelectorAll('input,button').forEach(e=>e.disabled=true);
        const card=form.closest('article'),outcome=predictionOutcome(m,myPredictions.get(m.id));card.classList.remove('prediction-open');card.classList.add('match-comparable','prediction-'+outcome.state);card.tabIndex=0;card.setAttribute('role','button');card.setAttribute('aria-label',m.home_name+' – '+m.away_name+'. Vergelijk voorspellingen in je poule');form.hidden=true;card.querySelector('[data-saved-score]').className='prediction-chip score-tone score-tone-'+outcome.state;button.hidden=true;card.querySelector('[data-score-summary]').hidden=false;updatePage();
      };
      async function save(){
        clearTimeout(debounce);
        if(inFlight){const succeeded=await inFlight;if(succeeded&&current(target,ctx)&&valid()&&!saved())return save();return;}
        if(!current(target,ctx)||stopped)return;
        if(!open(m,t)){disable();return;}
        if(!valid()){say(validation(),true);return;}if(saved())return;
        const [home,away]=values().map(Number),requestRevision=revision;
        button.hidden=true;form.dataset.koDirty='true';say('Opslaan…');
        inFlight=(async()=>{
          try{
            const {error}=await ctx.supabase.rpc('submit_match_prediction',{p_match_id:m.id,p_home_score:home,p_away_score:away});
            if(!current(target,ctx))return;if(error)throw Error(error.message);
            // A response must never overwrite more recent typing in this card.
            form.elements.home.defaultValue=String(home);form.elements.away.defaultValue=String(away);
            myPredictions.set(m.id,{home_score:home,away_score:away});
            form.closest('article').querySelector('[data-saved-value]').textContent=home+' - '+away;
            if(requestRevision===revision){form.elements.home.value=String(home);form.elements.away.value=String(away);say('Opgeslagen ✓');}return true;
          }catch(error){if(current(target,ctx)&&requestRevision===revision){say('Niet opgeslagen — '+error.message,true);button.hidden=false;}return false;}
        })();
        await inFlight;inFlight=null;
        form.dataset.koDirty=String(!saved());if(saved())say('Opgeslagen ✓');
        if(!current(target,ctx)||stopped)return;
        if(!open(m,t)){disable();return;}
        if(revision!==requestRevision&&!saved()&&valid()){clearTimeout(debounce);debounce=setTimeout(save,650);}
      }
      pendingSaves.push(save);
      form.addEventListener('input',()=>{revision++;clearTimeout(debounce);button.hidden=true;form.dataset.koDirty=String(!saved());
        if(saved()){say('Opgeslagen ✓');return;}
        if(!valid()){say(validation(),true);return;}
        say('Nog niet opgeslagen');debounce=setTimeout(save,650);
      });
      form.addEventListener('focusout',()=>{if(valid()&&!saved())save();});
      form.onsubmit=e=>{e.preventDefault();save();};button.onclick=save;
      if(saved())say('Opgeslagen ✓');
      if(open(m,t)){
        const expire=()=>{if(!current(target,ctx))return;const remaining=Date.parse(m.scheduled_start||t.starts_at)-Date.now();if(remaining<=0)disable();else deadlineTimer=setTimeout(expire,Math.min(remaining,2147483647));};expire();
      }
      ctx.signal.addEventListener('abort',()=>{stopped=true;clearTimeout(debounce);clearTimeout(deadlineTimer);},{once:true});

    });
  } catch(error) {showError(target,ctx,error,()=>loadTournamentDetail(host,ctx,page,'',view));}
}

// Existing membership RLS and leaderboard RPC remain authoritative for private pools.
async function loadTournamentRankings(host,ctx,tournamentId){
 const panel=document.createElement('section');panel.className='stack';host.replaceChildren(panel);
 const valid=()=>current(panel,ctx);
 const {renderLeaderboard,loadTournamentComparison,loadPoolComparison}=await import('./pool-comparison.js?v=layout-findings-20261023');
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
