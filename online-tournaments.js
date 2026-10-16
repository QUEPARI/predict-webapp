// Public user screens. Supabase remains authoritative for access, scores and deadlines.
const labels = {published:'Gepubliceerd',active:'Actief',completed:'Afgerond',archived:'Gepauzeerd / archief',scheduled:'Gepland',postponed:'Uitgesteld',live:'Bezig',finished:'Afgerond',cancelled:'Geannuleerd'};
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date = value => value && Number.isFinite(Date.parse(value))
  ? new Intl.DateTimeFormat('nl-NL',{dateStyle:'medium',timeStyle:'short',timeZone:'Europe/Amsterdam'}).format(new Date(value)) : 'Nog niet bevestigd';
const current = (target,ctx) => target.isConnected && !ctx.signal.aborted && ctx.isCurrent();
const open = (m,t) => ['published','active'].includes(t.status) && m.predictions_enabled === true &&
  m.needs_review === false && m.start_time_confirmed === true && m.round_id != null &&
  m.status === 'scheduled' && m.actual_start == null && m.home_score == null && m.away_score == null &&
  Date.parse(m.scheduled_start) > Date.now() &&
  (m.score_unit === 'goals' ? m.first_to == null : ['sets','legs'].includes(m.score_unit) && Number.isInteger(m.first_to) && m.first_to >= 1 && m.first_to <= 99);

export async function loadTournamentCatalog(target,ctx) {
  try {
    const [tours,entries] = await Promise.all([
      ctx.supabase.from('tournaments').select('id,name,status,starts_at').neq('status','draft').order('starts_at').order('id'),
      ctx.supabase.from('tournament_entries').select('tournament_id').eq('user_id',ctx.userId)
    ]);
    if (!current(target,ctx)) return;
    if (tours.error || entries.error) throw new Error((tours.error || entries.error).message);
    const joined = new Set((entries.data || []).map(e=>e.tournament_id));
    const list = (tours.data || []).filter(t=>ctx.mode !== 'home' || joined.has(t.id));
    target.innerHTML = `<h1>${ctx.mode === 'home' ? 'Mijn toernooien' : 'Toernooien'}</h1>
      <p class="sub">${ctx.mode === 'home' ? 'Je deelnames en voorspellingen, opgeslagen in Predict.' : 'Kies een toernooi. Je kunt ook zonder privépoule deelnemen.'}</p>
      <div class="grid">${list.map(t=>`<article class="panel stack"><h2>${esc(t.name)}</h2>
        <div>${esc(labels[t.status] || t.status)}${joined.has(t.id) ? ' · Je doet mee' : ''}</div>
        <div class="muted mini">Toernooistart: ${esc(date(t.starts_at))}</div>
        <button class="btn" data-online-open="${esc(t.id)}">${joined.has(t.id) ? 'Wedstrijden en voorspellingen' : 'Bekijk toernooi'}</button></article>`).join('') ||
        `<p>${ctx.mode === 'home' ? 'Je doet nog niet mee aan een toernooi. Kies een toernooi via Toernooien of accepteer een poule-uitnodiging.' : 'Er zijn nog geen gepubliceerde toernooien.'}</p>`}</div>`;
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

export async function loadTournamentDetail(host,ctx,page=0,notice='') {
  const target=document.createElement('section');target.className='stack';target.textContent='Toernooi laden...';host.replaceChildren(target);
  try {
    const [tour,entry] = await Promise.all([
      ctx.supabase.from('tournaments').select('id,name,status').eq('id',ctx.tournamentId).single(),
      ctx.supabase.from('tournament_entries').select('tournament_id').eq('tournament_id',ctx.tournamentId).eq('user_id',ctx.userId)
    ]);
    if (!current(target,ctx)) return;
    if (tour.error || entry.error || !tour.data) throw new Error((tour.error || entry.error)?.message || 'Toernooi niet beschikbaar.');
    const t=tour.data,joined=!!entry.data?.length;
    const size=50;
    const [matches,rounds,points,scoring,rules] = await Promise.all([
      ctx.supabase.from('matches').select('id,round_id,home_name,away_name,scheduled_start,actual_start,status,home_score,away_score,score_unit,first_to,start_time_confirmed,needs_review,predictions_enabled',{count:'exact'})
        .eq('tournament_id',t.id).order('scheduled_start').order('id').range(page*size,(page+1)*size-1),
      ctx.supabase.from('tournament_rounds').select('id,name,round_order').eq('tournament_id',t.id).order('round_order'),
      joined ? ctx.supabase.rpc('get_my_match_points',{p_tournament_id:t.id}) : Promise.resolve({data:[]}),
      ctx.supabase.from('tournament_scoring').select('scoring_mode').eq('tournament_id',t.id),
      ctx.supabase.from('round_scoring').select('round_id,winner_points,exact_score_points').eq('tournament_id',t.id)
    ]);
    if (!current(target,ctx)) return;
    const failure=[matches,rounds,points,scoring,rules].find(r=>r.error)?.error;
    if (failure) throw new Error(failure.message);
    const list=matches.data || [];
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
    target.innerHTML=`<div class="breadcrumb"><button type="button" id="online-back">← Toernooioverzicht</button></div>
      <h1>${esc(t.name)}</h1><p class="muted">${esc(labels[t.status] || t.status)} · Alle tijden: Nederland</p>
      <p role="status" id="online-notice">${esc(notice)}</p>
      ${joined ? `<div class="notice">Je doet mee · Punten uit afgeronde wedstrijden: ${esc(total)}.
        Eén voorspelling per wedstrijd telt voor dit toernooi en al je bijbehorende poules.</div>` :
      `<div class="panel stack"><p>Neem deel om je voorspellingen centraal op te slaan.</p>
        ${['published','active'].includes(t.status) ? '<button class="btn" id="online-join">Deelnemen aan dit toernooi</button>' : '<p>Dit toernooi staat niet meer open voor nieuwe deelnemers.</p>'}</div>`}
      <div class="row"><h2>Wedstrijden</h2><button class="btn secondary" id="online-refresh">Vernieuwen</button></div>
      <p class="hint">Alleen goedgekeurde en vrijgegeven wedstrijden zijn open. Predict controleert de individuele deadline opnieuw bij het opslaan.</p>
      <div class="grid online-matches">${list.map(m=>{
        const p=myPredictions.get(m.id),earned=myPoints.get(m.id),rule=roundRules.get(m.round_id);
        const allowed=joined && open(m,t);
        const hint=m.score_unit==='goals' ? 'Eindscore vóór strafschoppen; gelijkspel toegestaan.' :
          m.first_to ? `Precies één speler moet ${esc(m.first_to)} ${m.score_unit==='sets'?'sets':'legs'} winnen.` : 'Het wedstrijdformaat is nog niet vastgesteld.';
        return `<article class="panel stack" data-online-match="${esc(m.id)}">
          <div class="muted mini">${esc(roundNames.get(m.round_id) || 'Ronde nog niet vastgesteld')} · ${esc(labels[m.status] || m.status)}</div>
          <h3>${esc(m.home_name)} – ${esc(m.away_name)}</h3>
          <div class="mini">Deadline: ${esc(date(m.scheduled_start))}</div>
          <div class="pill" data-open-state>${allowed ? 'Voorspellen open' : 'Voorspellen gesloten'}</div>
          <p class="hint">${hint}${rule ? `<br>Winnaar: ${esc(rule.winner_points)} punten · exact: ${esc(rule.exact_score_points)} ${scoringMode==='additive'?'extra punten':'punten totaal'}.` : ''}</p>
          ${joined ? `<form class="stack" data-online-predict="${esc(m.id)}"><div class="two">
            <div class="field"><label for="online-home-${esc(m.id)}">Score ${esc(m.home_name)}</label><input id="online-home-${esc(m.id)}" name="home" type="number" min="0" max="99" step="1" required value="${esc(p?.home_score ?? '')}" ${allowed?'':'disabled'}></div>
            <div class="field"><label for="online-away-${esc(m.id)}">Score ${esc(m.away_name)}</label><input id="online-away-${esc(m.id)}" name="away" type="number" min="0" max="99" step="1" required value="${esc(p?.away_score ?? '')}" ${allowed?'':'disabled'}></div>
            </div><p class="hint">${p ? `Opgeslagen: ${esc(p.home_score)}–${esc(p.away_score)}` : 'Nog geen voorspelling opgeslagen.'}</p>
            <p role="status" data-prediction-message></p><button class="btn" ${allowed?'':'disabled'}>${p?'Voorspelling wijzigen':'Voorspelling opslaan'}</button></form>` : ''}
          ${m.status==='finished' && m.home_score!=null && m.away_score!=null ? `<div class="notice">Uitslag: ${esc(m.home_score)}–${esc(m.away_score)}${earned ? ` · ${esc(earned.earned_points)} punten` : ''}</div>` : ''}
        </article>`;
      }).join('') || '<p>Er zijn nog geen wedstrijden beschikbaar op deze pagina.</p>'}</div>
      <div class="row"><button class="btn secondary" id="online-previous" ${page===0?'disabled':''}>Vorige</button>
        <span>Pagina ${page+1}</span><button class="btn secondary" id="online-next" ${(page+1)*size >= (matches.count ?? list.length)?'disabled':''}>Volgende</button></div>`;
    const champion=document.createElement('section');champion.className='panel stack';champion.textContent='Winnaarsvraag laden...';target.querySelector('.online-matches').before(champion);
    import('./tournament-management.js').then(({loadChampionPrediction})=>{if(current(target,ctx))loadChampionPrediction(champion,ctx,t.id,joined);}).catch(()=>{if(current(target,ctx))champion.textContent='Winnaarsvraag laden mislukt.';});
    const schema=document.createElement('section');schema.className='panel stack';schema.textContent='Toernooischema laden...';
    target.querySelector('.online-matches').before(schema);
    import('./knockout.js').then(({loadKnockoutSchema})=>{if(current(target,ctx))loadKnockoutSchema(schema,ctx,t.id);}).catch(()=>{if(current(target,ctx))schema.textContent='Schema laden mislukt. Vernieuw het toernooi.';});
    const hasDraft=()=>!!target.querySelector('[data-ko-dirty="true"]')||[...target.querySelectorAll('input')].some(i=>i.value!==i.defaultValue);
    const discard=()=>!hasDraft() || confirm('Niet-opgeslagen wijzigingen laten vervallen?');
    window.addEventListener('beforeunload',event=>{
      if(current(target,ctx)&&hasDraft()){event.preventDefault();event.returnValue='';}
    },{signal:ctx.signal});
    target.querySelector('#online-back').onclick=()=>{if(discard())ctx.onBack();};
    const refresh=()=>loadTournamentDetail(host,ctx,page);
    target.querySelector('#online-refresh').onclick=()=>{
      if (discard()) refresh();
    };
    target.querySelector('#online-previous').onclick=()=>{if(discard())loadTournamentDetail(host,ctx,page-1);};
    target.querySelector('#online-next').onclick=()=>{if(discard())loadTournamentDetail(host,ctx,page+1);};
    const join=target.querySelector('#online-join');
    if (join) join.onclick=async()=>{
      join.disabled=true;
      try {
        const {error}=await ctx.supabase.rpc('join_tournament',{p_tournament_id:t.id});
        if (!current(target,ctx)) return;
        if (error) throw new Error(error.message);
        await loadTournamentDetail(host,ctx,page,'Je neemt nu deel aan dit toernooi.');
      } catch(error) {if(current(target,ctx)){target.querySelector('#online-notice').textContent=error.message;join.disabled=false;}}
    };
    target.querySelectorAll('[data-online-predict]').forEach(form=>{
      const m=list.find(m=>m.id===form.dataset.onlinePredict);
      const message=form.querySelector('[data-prediction-message]');
      const disable=()=>{
        form.querySelectorAll('input,button').forEach(e=>e.disabled=true);
        form.closest('article').querySelector('[data-open-state]').textContent='Voorspellen gesloten';
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
          message.textContent='Vul een geldige eindstand voor dit wedstrijdformaat in.';return;
        }
        const button=form.querySelector('button');button.disabled=true;message.textContent='Opslaan...';
        const fields=[...form.querySelectorAll('input')];fields.forEach(i=>i.disabled=true);
        try {
          const {error}=await ctx.supabase.rpc('submit_match_prediction',{p_match_id:m.id,p_home_score:home,p_away_score:away});
          if (!current(target,ctx)) return;
          if(error) throw new Error(error.message);
          // Preserve unsaved input on other cards; only update the submitted form.
          form.elements.home.defaultValue=String(home);form.elements.away.defaultValue=String(away);
          form.querySelector('.hint').textContent=`Opgeslagen: ${home}–${away}`;
          button.textContent='Voorspelling wijzigen';message.textContent='Opgeslagen in Predict.';
        } catch(error) {if(current(target,ctx))message.textContent='Opslaan mislukt: '+error.message;}
        finally {if(current(target,ctx)){const allowed=open(m,t);button.disabled=!allowed;fields.forEach(i=>i.disabled=!allowed);if(!allowed)disable();}}
      };
    });
  } catch(error) {showError(target,ctx,error,()=>loadTournamentDetail(host,ctx,page));}
}
