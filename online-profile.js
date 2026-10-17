const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const active=(target,ctx)=>target.isConnected&&!ctx.signal.aborted&&ctx.isCurrent();
const status={scheduled:'Gepland',postponed:'Uitgesteld',live:'Bezig',finished:'Afgerond',cancelled:'Geannuleerd'};

export async function loadOnlineProfile(target,ctx){
  target.textContent='Account laden...';
  try {
    const [profile,entries,tours]=await Promise.all([
      ctx.supabase.from('profiles').select('username,display_name,theme').eq('id',ctx.userId).single(),
      ctx.supabase.from('tournament_entries').select('tournament_id').eq('user_id',ctx.userId),
      ctx.supabase.from('tournaments').select('id,name').order('name')
    ]);
    if(!active(target,ctx))return;
    const error=[profile,entries,tours].find(r=>r.error)?.error;
    if(error||!profile.data)throw new Error(error?.message||'Eigen profiel niet gevonden.');
    const p=ctx.onLoaded(profile.data)||profile.data,joined=new Set((entries.data||[]).map(e=>e.tournament_id));
    const available=(tours.data||[]).filter(t=>joined.has(t.id));
    target.innerHTML=`<h1>Account</h1><p class="sub">Je accountvoorkeuren en eigen voorspellingen.</p>
      <form class="panel stack" data-profile-form data-dirty="false">
        <div class="muted mini">Gebruikersnaam: ${esc(p.username)}</div>
        <div class="field"><label for="account-display-name">Weergavenaam</label>
          <input id="account-display-name" required maxlength="40" value="${esc(p.display_name||p.username)}" autocomplete="nickname"></div>
        <div class="field"><label for="account-theme">Thema</label><select id="account-theme">
          ${[['system','Systeeminstelling'],['light','Licht'],['dark','Donker']].map(([v,label])=>`<option value="${v}" ${p.theme===v?'selected':''}>${label}</option>`).join('')}</select></div>
        <p class="hint">Naam en thema worden bij je account opgeslagen. Systeeminstelling volgt de voorkeur van je apparaat.</p>
        <p role="status" id="account-profile-message"></p><button class="btn">Account opslaan</button>
      </form><section class="panel stack" data-push-settings aria-label="Telefoonmeldingen"></section><div class="panel stack"><h2>Mijn voorspellingen</h2>
        ${available.length?`<label for="account-prediction-tour">Toernooi</label><select id="account-prediction-tour">
          ${available.map(t=>`<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('')}</select>
          <div id="account-predictions" class="stack" role="region" aria-label="Eigen voorspellingen"></div>`:
          '<p>Je doet nog niet mee aan een toernooi. Kies een toernooi via Toernooien of accepteer een poule-uitnodiging.</p>'}</div>`;
    import('./push-notifications.js?v=push-times-20261017').then(({loadPushSettings})=>{const host=target.querySelector('[data-push-settings]');if(host&&active(target,ctx))loadPushSettings(host,ctx.supabase);}).catch(()=>{const host=target.querySelector('[data-push-settings]');if(host)host.textContent='Telefoonmeldingen laden mislukt.';});
    const form=target.querySelector('[data-profile-form]'),name=form.querySelector('input'),theme=form.querySelector('select');
    let savedTheme=p.theme||'system',savedName=name.value;
    const dirty=()=>{form.dataset.dirty=String(name.value!==savedName||theme.value!==savedTheme);};
    form.oninput=dirty;form.onchange=dirty;
    window.addEventListener('beforeunload',event=>{
      if(active(target,ctx)&&form.dataset.dirty==='true'){event.preventDefault();event.returnValue='';}
    },{signal:ctx.signal});
    // Account preference updates preserve unsaved display-name drafts.
    window.addEventListener('predict-preferences-saved',event=>{
      if(!active(target,ctx))return;
      const displayName=event.detail.display_name||event.detail.username;
      if(name.value===savedName){name.value=displayName;name.defaultValue=displayName;}
      savedName=displayName;
      if(theme.value===savedTheme)theme.value=event.detail.theme;
      savedTheme=event.detail.theme;dirty();
    },{signal:ctx.signal});
    form.onsubmit=async event=>{
      event.preventDefault();
      const message=target.querySelector('#account-profile-message');
      if(!name.value.trim()){message.textContent='Vul een weergavenaam in.';return;}
      const controls=[...form.querySelectorAll('input,select,button')];controls.forEach(c=>c.disabled=true);message.textContent='Opslaan...';
      try {
        const data=await ctx.save({p_display_name:name.value.trim(),p_theme:theme.value});
        if(!active(target,ctx))return;
        name.value=data.display_name;name.defaultValue=data.display_name;savedName=data.display_name;
        theme.value=data.theme;savedTheme=data.theme;dirty();message.textContent='Account opgeslagen in Predict.';
      } catch(error){if(active(target,ctx))message.textContent='Opslaan mislukt: '+error.message;}
      finally{if(active(target,ctx))controls.forEach(c=>c.disabled=false);}
    };
    const predictionHost=target.querySelector('#account-predictions');
    if(predictionHost){
      const select=target.querySelector('#account-prediction-tour');
      select.onchange=()=>loadPredictions(predictionHost,ctx,select.value);
      await loadPredictions(predictionHost,ctx,select.value);
    }
  } catch(error){
    if(!active(target,ctx))return;
    target.innerHTML='<h1>Account</h1><p role="alert"></p><button class="btn secondary">Opnieuw proberen</button>';
    target.querySelector('p').textContent='Account laden mislukt: '+error.message;
    target.querySelector('button').onclick=()=>loadOnlineProfile(target,ctx);
  }
}

async function loadPredictions(host,ctx,tournamentId,page=0){
  const target=document.createElement('div');target.className='stack';target.textContent='Eigen voorspellingen laden...';host.replaceChildren(target);
  try {
    const size=25;
    const [response,points]=await Promise.all([
      ctx.supabase.from('match_predictions').select('id,match_id,home_score,away_score,matches!inner(tournament_id,home_name,away_name,status,home_score,away_score)',{count:'exact'})
        .eq('user_id',ctx.userId).eq('matches.tournament_id',tournamentId).order('updated_at',{ascending:false}).order('id').range(page*size,(page+1)*size-1),
      ctx.supabase.rpc('get_my_match_points',{p_tournament_id:tournamentId})
    ]);
    if(!active(target,ctx))return;
    if(response.error||points.error)throw new Error((response.error||points.error).message);
    const data=response.data||[],earned=new Map((points.data||[]).map(r=>[r.match_id,r.earned_points]));
    target.innerHTML=`<p class="hint">Alleen je eigen voorspellingen. Punten worden door Predict berekend zodra een wedstrijd is afgerond.</p>
      <div class="table-wrap">${data.length?`<table><thead><tr><th>Wedstrijd</th><th>Voorspelling</th><th>Uitslag</th><th>Punten</th></tr></thead>
      <tbody>${data.map(p=>{const m=p.matches;return `<tr><td>${esc(m.home_name)} – ${esc(m.away_name)}<br><span class="mini muted">${esc(status[m.status]||m.status)}</span></td>
        <td>${esc(p.home_score)}–${esc(p.away_score)}</td><td>${m.status==='finished'&&m.home_score!=null&&m.away_score!=null?`${esc(m.home_score)}–${esc(m.away_score)}`:'–'}</td>
        <td>${earned.has(p.match_id)?esc(earned.get(p.match_id)):'–'}</td></tr>`;}).join('')}</tbody></table>`:'<p>Nog geen voorspellingen voor dit toernooi.</p>'}</div>
      <div class="row"><button class="btn secondary" data-page-previous ${page===0?'disabled':''}>Vorige</button><span>Pagina ${page+1}</span>
        <button class="btn secondary" data-page-next ${(page+1)*size>=(response.count??data.length)?'disabled':''}>Volgende</button></div>`;
    target.querySelector('[data-page-previous]').onclick=()=>loadPredictions(host,ctx,tournamentId,page-1);
    target.querySelector('[data-page-next]').onclick=()=>loadPredictions(host,ctx,tournamentId,page+1);
  } catch(error){
    if(!active(target,ctx))return;
    target.innerHTML='<p role="alert"></p><button class="btn secondary">Voorspellingen opnieuw proberen</button>';
    target.querySelector('p').textContent='Eigen voorspellingen laden mislukt: '+error.message;
    target.querySelector('button').onclick=()=>loadPredictions(host,ctx,tournamentId,page);
  }
}
