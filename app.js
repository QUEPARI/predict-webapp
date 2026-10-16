import { createClient } from
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL =
  'https://sfcozzjcuppfypetbbzn.supabase.co';

const SUPABASE_PUBLISHABLE_KEY =
  'sb_publishable_1opRVzunD94Sd71rKSJAew_0ydMP2VU';

const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY,
  {
    auth: {
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: true
    }
  }
);

// NIEUWE REGEL:
window.predictSupabase = supabase;

// Offline demonstrator. No real users, server security, or live sports data.
// Offline demonstrator. No real users, server security, or live sports data.
const STORE='predict-demo-v1';
const defaults={theme:'light',user:'Demo-gebruiker',tab:'home',tournament:null,predictions:{},extra:{},pools:[{id:'friends',tournament:'darts27',name:'Vriendengroep',members:['Demo-gebruiker','Thomas','Mark']}],joined:['darts27','football'],showAdmin:false};
function read(){try{return {...structuredClone(defaults),...JSON.parse(localStorage.getItem(STORE)||'{}')}}catch{return structuredClone(defaults)}}
let state=read();const save=()=>localStorage.setItem(STORE,JSON.stringify(state));
const tournaments=[{id:'darts27',name:'WK Darts 2027',sport:'darts',state:'Binnenkort',description:'Exacte setstanden en progressieve punten per ronde.'},{id:'football',name:'Voetbal – demonstratietoernooi',sport:'football',state:'Demo',description:'Wedstrijdscores, kampioen en topscorer.'}];
// Fixtures here are *fictional* and deliberately not presented as official schedules.
const fixtures=[{id:'d1',tournament:'darts27',round:'Ronde 1',home:'Speler A',away:'Speler B',format:'sets',firstTo:3,start:'2027-12-18T20:00:00Z',status:'scheduled',official:null},{id:'d2',tournament:'darts27',round:'Ronde 1',home:'Speler C',away:'Speler D',format:'sets',firstTo:3,start:'2027-12-18T21:00:00Z',status:'scheduled',official:null},{id:'f1',tournament:'football',round:'Groepsfase',home:'Nederland',away:'Duitsland',format:'goals',start:'2027-12-18T19:00:00Z',status:'scheduled',official:null},{id:'f2',tournament:'football',round:'Groepsfase',home:'Spanje',away:'Frankrijk',format:'goals',start:'2027-12-19T19:00:00Z',status:'scheduled',official:null}];
const dartsPts={'Ronde 1':[1,3],'Ronde 2':[2,5],'Ronde 3':[3,7],'Ronde 4':[4,10],'Kwartfinale':[6,15],'Halve finale':[10,25],'Finale':[15,40]};
const $=id=>document.getElementById(id);
function esc(x){return String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function activeTournament(){return tournaments.find(t=>t.id===state.tournament)}
function fmt(date){return new Intl.DateTimeFormat('nl-NL',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit',timeZone:'Europe/Amsterdam'}).format(new Date(date))}
function locked(m){return m.status!=='scheduled'||new Date(m.start)<=new Date()}
function score(m,p){if(!m.official||!p)return 0;const a=m.official,b=p;const exact=Number(a.home)===Number(b.home)&&Number(a.away)===Number(b.away);const actualWin=Math.sign(a.home-a.away),predWin=Math.sign(b.home-b.away);if(m.format==='sets'){const [win,ex]=dartsPts[m.round]||[0,0];return exact?ex:actualWin===predWin?win:0}return exact?7:actualWin===predWin?3:0}
function points(tid){return fixtures.filter(m=>m.tournament===tid).reduce((s,m)=>s+score(m,state.predictions[m.id]),0)}
function missing(tid){return fixtures.filter(m=>m.tournament===tid&&!locked(m)&&!state.predictions[m.id]).length}
function nav(){return `<div class="nav">${[['home','Home'],['discover','Toernooien'],['pools','Mijn poules'],['profile','Profiel']].map(([id,label])=>`<button data-tab="${id}" class="${state.tab===id?'active':''}">${label}</button>`).join('')}</div>`}
function header(){return `<header class="top"><div class="logo"><div class="logo-mark">P</div><div><div class="brand">Predict</div><div class="tag">SPORTVOORSPELLINGEN</div></div></div><div class="top-actions"><span class="badge">DEMO</span><button class="ghost" data-action="theme" aria-label="Wissel licht/donker">${state.theme==='dark'?'☀ Licht':'◐ Donker'}</button></div></header>`}
function tournamentCard(t){return `<div class="panel stack"><div class="row"><span class="sport">${t.sport==='darts'?'DARTS':'VOETBAL'}</span><span class="pill mutedpill">${esc(t.state)}</span></div><h2 style="margin:0">${esc(t.name)}</h2><div class="muted mini">${esc(t.description)}</div><div class="row"><span class="mini muted">${missing(t.id)} nog te voorspellen</span><span class="mini"><b>${points(t.id)} pt</b></span></div><button class="btn" data-open="${t.id}">Open toernooi →</button></div>`}
function home(){return `<h1>Mijn toernooien</h1><p class="sub">Welkom, ${esc(state.user)}. Overzicht van jouw toernooien en voorspellingen.</p><div class="notice">Dit is een lokale demonstratie met fictieve wedstrijden. Er worden nog geen echte accounts, poules of uitslagen gesynchroniseerd.</div><div class="grid">${tournaments.filter(t=>state.joined.includes(t.id)).map(tournamentCard).join('')}</div>`}
function discover(){return `<h1>Toernooien</h1><p class="sub">Kies een beschikbaar toernooi. Alleen systeembeheerders zullen later toernooien kunnen toevoegen.</p><div class="grid">${tournaments.map(tournamentCard).join('')}</div>`}
function pools(){return `<h1>Mijn privépoules</h1><p class="sub">Iedere poule behoort tot één toernooi. Voorspellingen blijven per toernooi centraal opgeslagen.</p><div class="grid">${state.pools.map(p=>`<div class="panel stack"><h2>${esc(p.name)}</h2><div class="muted mini">${esc(tournaments.find(t=>t.id===p.tournament)?.name||'')}</div><div>${p.members.length} leden</div><button class="btn secondary" data-open="${p.tournament}">Open toernooi</button></div>`).join('')}</div><div class="section-head"><h2>Demonstratie: poule aanmaken</h2></div><form class="panel stack" id="pool-form"><div class="field"><label for="pool-name">Naam van de poule</label><input id="pool-name" required maxlength="60" placeholder="Bijvoorbeeld: Collega's"></div><div class="field"><label for="pool-tournament">Toernooi</label><select id="pool-tournament">${tournaments.map(t=>`<option value="${t.id}">${esc(t.name)}</option>`).join('')}</select></div><button class="btn">Maak lokale demo-poule</button><div class="hint">Er worden nog geen uitnodigingen verzonden. Een echte poule vereist gebruikersauthenticatie en databaseopslag.</div></form>`}
function profile(){return `<h1>Profiel en instellingen</h1><p class="sub">Lokale demo-instellingen.</p><form class="panel stack" id="profile-form"><div class="field"><label for="username">Weergavenaam</label><input id="username" required maxlength="40" value="${esc(state.user)}"></div><button class="btn">Opslaan</button></form><div class="section-head"><h2>Mijn voorspellingen</h2></div><div class="panel table-wrap"><table><thead><tr><th>Wedstrijd</th><th>Voorspelling</th><th>Fase</th></tr></thead><tbody>${fixtures.filter(m=>state.predictions[m.id]).map(m=>`<tr><td>${esc(m.home)} – ${esc(m.away)}</td><td>${state.predictions[m.id].home}–${state.predictions[m.id].away}</td><td>${esc(m.round)}</td></tr>`).join('')||'<tr><td colspan="3">Nog geen voorspellingen</td></tr>'}</tbody></table></div><div class="section-head"><h2>Demo resetten</h2></div><button class="ghost" data-action="reset">Verwijder lokale demogegevens</button>`}
function matchCard(m){const p=state.predictions[m.id],isLocked=locked(m);return `<div class="panel match"><div class="row"><span class="mini muted">${esc(m.round)} · ${fmt(m.start)}</span><span class="pill ${isLocked?'mutedpill':''}">${isLocked?'Gesloten':p?'Ingevuld':'Open'}</span></div><div class="teams"><span>${esc(m.home)}<br><span class="muted">${esc(m.away)}</span></span><span class="score">${p?`${p.home}–${p.away}`:'–'}</span></div><form class="prediction-form stack" data-match="${m.id}"><div class="two"><div class="field"><label>Score ${esc(m.home)}</label><input type="number" name="home" min="0" max="99" step="1" value="${p?p.home:''}" ${isLocked?'disabled':''} required></div><div class="field"><label>Score ${esc(m.away)}</label><input type="number" name="away" min="0" max="99" step="1" value="${p?p.away:''}" ${isLocked?'disabled':''} required></div></div><div class="row"><span class="hint">${m.format==='sets'?`Eén speler moet ${m.firstTo} sets winnen; de ander maximaal ${m.firstTo-1}.`:'Gelijkspel toegestaan; score vóór strafschoppen.'}</span><button class="btn" ${isLocked?'disabled':''}>${p?'Wijzigen':'Opslaan'}</button></div></form>${m.official?`<div class="notice">Officieel ${m.official.home}–${m.official.away} · ${score(m,p)} punten</div>`:''}</div>`}
function extra(t){if(t.sport!=='football')return `<div class="notice">Voor dit demo-dartstoernooi zijn geen extra vragen geconfigureerd.</div>`;return `<div class="panel stack"><h2>Extra toernooivoorspellingen</h2><p class="hint">De definitieve applicatie sluit alle extra vragen vóór de eerste wedstrijd van het toernooi. Dit demonstratieformulier heeft alleen lokale opslag.</p><form id="extra-form" class="stack"><div class="field"><label for="champ">Wie wordt kampioen?</label><select name="champ" id="champ"><option value="">Selecteer een land</option>${['Nederland','Duitsland','Spanje','Frankrijk'].map(x=>`<option ${state.extra.champ===x?'selected':''}>${x}</option>`).join('')}</select></div><div class="field"><label for="scorer">Wie wordt topscorer?</label><input id="scorer" name="scorer" maxlength="80" value="${esc(state.extra.scorer||'')}" placeholder="Naam van de speler"></div><button class="btn">Voorspellingen lokaal opslaan</button></form></div>`}
function leaderboard(t){return `<div class="panel stack"><h2>Klassement ${esc(t.name)}</h2><p class="hint">Een echt klassement komt uitsluitend uit de beveiligde database. Andere gebruikers en punten worden niet verzonnen in de demo.</p><div class="table-wrap"><table><thead><tr><th>#</th><th>Gebruiker</th><th class="num">Punten</th></tr></thead><tbody><tr><td>1</td><td>${esc(state.user)} (demo)</td><td class="num">${points(t.id)}</td></tr></tbody></table></div></div>`}
function tournamentView(t){let ms=fixtures.filter(m=>m.tournament===t.id);return `<div class="breadcrumb"><button data-action="back">← Mijn toernooien</button></div><div class="row"><div><span class="sport">${t.sport==='darts'?'DARTS':'VOETBAL'}</span><h1>${esc(t.name)}</h1></div><span class="pill">${esc(t.state)}</span></div><p class="sub">${esc(t.description)}</p><div class="grid three"><div class="panel"><div class="stat-label">Mijn punten</div><div class="stat">${points(t.id)}</div></div><div class="panel"><div class="stat-label">Nog voorspellen</div><div class="stat">${missing(t.id)}</div></div><div class="panel"><div class="stat-label">Wedstrijden (demo)</div><div class="stat">${ms.length}</div></div></div><div class="section-head"><h2>Wedstrijden</h2><span class="mini muted">Nederlandse tijd</span></div><div class="grid">${ms.map(matchCard).join('')}</div><div class="section-head"><h2>Extra voorspellingen</h2></div>${extra(t)}<div class="section-head"><h2>Klassement</h2></div>${leaderboard(t)}${t.sport==='darts'?`<div class="section-head"><h2>Puntentabel WK Darts 2027</h2></div><div class="panel table-wrap"><table><thead><tr><th>Ronde</th><th class="num">Winnaar</th><th class="num">Exact totaal</th></tr></thead><tbody>${Object.entries(dartsPts).map(([round,arr])=>`<tr><td>${esc(round)}</td><td class="num">${arr[0]}</td><td class="num">${arr[1]}</td></tr>`).join('')}</tbody></table></div>`:''}`}
function render(){document.body.className=state.theme==='dark'?'dark':'';const t=activeTournament();$('app').innerHTML=`<main class="layout">${header()}${t?tournamentView(t):nav()+(state.tab==='home'?home():state.tab==='discover'?discover():state.tab==='pools'?pools():profile())}<div class="footer">Predict · Lokale ontwerp- en functiedemo · Geen officiële sportdata · Geen online accounts</div></main>`;bind()}
function bind(){document.querySelectorAll('[data-tab]').forEach(el=>el.onclick=()=>{state.tab=el.dataset.tab;save();render()});document.querySelectorAll('[data-open]').forEach(el=>el.onclick=()=>{state.tournament=el.dataset.open;save();render()});document.querySelectorAll('[data-action]').forEach(el=>el.onclick=()=>{if(el.dataset.action==='theme')state.theme=state.theme==='dark'?'light':'dark';if(el.dataset.action==='back'){state.tournament=null;state.tab='home'}if(el.dataset.action==='reset'&&confirm('Alleen lokale demogegevens wissen?'))state=structuredClone(defaults);save();render()});document.querySelectorAll('.prediction-form').forEach(form=>form.onsubmit=e=>{e.preventDefault();const m=fixtures.find(x=>x.id===form.dataset.match);if(locked(m)){alert('De voorspeldeadline is verstreken.');render();return}const data=new FormData(form),a=Number(data.get('home')),b=Number(data.get('away'));if(!Number.isInteger(a)||!Number.isInteger(b)||a<0||b<0||a>99||b>99){alert('Vul twee geldige scores in.');return}if(m.format==='sets'&&!((a===m.firstTo&&b<m.firstTo)||(b===m.firstTo&&a<m.firstTo))){alert(`Eén darter moet precies ${m.firstTo} sets winnen.`);return}state.predictions[m.id]={home:a,away:b,updatedAt:new Date().toISOString()};save();render()});const pool=$('pool-form');if(pool)pool.onsubmit=e=>{e.preventDefault();const name=$('pool-name').value.trim();if(!name)return;state.pools.push({id:crypto.randomUUID(),name,tournament:$('pool-tournament').value,members:[state.user]});save();render()};const profileForm=$('profile-form');if(profileForm)profileForm.onsubmit=e=>{e.preventDefault();const n=$('username').value.trim();if(n)state.user=n;save();render()};const extraForm=$('extra-form');if(extraForm)extraForm.onsubmit=e=>{e.preventDefault();const d=new FormData(extraForm);state.extra={champ:d.get('champ'),scorer:String(d.get('scorer')).trim()};save();render()}}

let currentUser = null;
let currentRole = 'user';

const renderDemo = render;

render = function () {
  if (!currentUser) {
    document.body.className =
      state.theme === 'dark' ? 'dark' : '';

    $('app').innerHTML = `
      <main class="layout">
        <header class="top">
          <div class="logo">
            <div class="logo-mark">P</div>
            <div>
              <div class="brand">Predict</div>
              <div class="tag">SPORTVOORSPELLINGEN</div>
            </div>
          </div>
        </header>

        <div class="panel stack"
             style="max-width:440px;margin:60px auto">
          <h1>Inloggen</h1>
          <p class="sub">
            Log in met je Predict-account.
          </p>

          <form id="login-form" class="stack">
            <div class="field">
              <label for="login-email">E-mailadres</label>
              <input
                id="login-email"
                type="email"
                autocomplete="email"
                required
              >
            </div>

            <div class="field">
              <label for="login-password">Wachtwoord</label>
              <input
                id="login-password"
                type="password"
                autocomplete="current-password"
                required
              >
            </div>

            <button class="btn" type="submit">
              Inloggen
            </button>
          </form>

          <p id="login-error" role="alert"></p>
        </div>
      </main>
    `;

    $('login-form').onsubmit = async (event) => {
      event.preventDefault();

      const button =
        $('login-form').querySelector('button');

      const errorElement = $('login-error');

      button.disabled = true;
      errorElement.textContent = '';

      const email = $('login-email').value.trim();
      const password = $('login-password').value;

      const { error } =
        await supabase.auth.signInWithPassword({
          email,
          password
        });

      if (error) {
        errorElement.textContent =
          'Inloggen mislukt. Controleer je gegevens.';
        button.disabled = false;
        return;
      }

      await loadCurrentUser();
    };

    return;
  }

  renderDemo();

  // Toon accountgegevens en uitlogknop
  const actions = document.querySelector('.top-actions');

  if (actions) {
    const account = document.createElement('span');
    account.className = 'mini';
    account.textContent =
      currentRole === 'super_admin'
        ? 'Systeembeheerder'
        : currentRole === 'admin'
          ? 'Beheerder'
          : 'Gebruiker';

    const logoutButton = document.createElement('button');
    logoutButton.className = 'ghost';
    logoutButton.textContent = 'Uitloggen';

    logoutButton.onclick = async () => {
      const { error } = await supabase.auth.signOut();

      if (error) {
        alert('Uitloggen mislukt. Probeer opnieuw.');
        return;
      }

      currentUser = null;
      currentRole = 'user';
      render();
    };

    actions.append(account, logoutButton);
  }
};

async function loadCurrentUser() {
  const { data, error } = await supabase.auth.getUser();

  if (error || !data.user) {
    currentUser = null;
    currentRole = 'user';
    render();
    return;
  }

  currentUser = data.user;

  const { data: profile, error: profileError } =
    await supabase
      .from('profiles')
      .select('username, display_name')
      .eq('id', currentUser.id)
      .single();

  const { data: role, error: roleError } =
    await supabase
      .from('user_roles')
      .select('role')
      .eq('user_id', currentUser.id)
      .single();

  if (profileError || roleError) {
    console.error(
      'Profiel of rol ophalen mislukt',
      profileError,
      roleError
    );
    currentUser = null;
    currentRole = 'user';
    $('app').textContent =
      'Accountgegevens konden niet worden geladen. Vernieuw de pagina.';
    return;
  }

  state.user =
    profile.display_name ||
    profile.username ||
    'Gebruiker';

  currentRole = role.role;

  render();
}

$('app').textContent = 'Account laden...';

loadCurrentUser();

/*
 * PREDICT - Beheerdersoverzicht
 * Alleen lezen; geen databasewijzigingen.
 */

const renderWithLogin = render;

render = function () {
  // Behoud de bestaande login en webapp.
  renderWithLogin();

  const isAdmin =
    currentRole === 'admin' ||
    currentRole === 'super_admin';

  if (!currentUser || !isAdmin) return;

  const navigation = document.querySelector('.nav');

  // Op toernooidetailpagina's is geen navigatie zichtbaar.
  if (!navigation) return;

  // Voeg het beheertabblad toe.
  const adminButton = document.createElement('button');
  adminButton.textContent = 'Beheer';
  adminButton.classList.toggle(
    'active',
    state.tab === 'admin'
  );

  adminButton.onclick = () => {
    state.tab = 'admin';
    state.tournament = null;
    save();
    render();
  };

  navigation.appendChild(adminButton);

  if (state.tab !== 'admin') return;

  const layout = document.querySelector('.layout');

  // Verwijder alleen de standaardinhoud onder
  // de navigatie; behoud header en navigatie.
  while (navigation.nextSibling) {
    navigation.nextSibling.remove();
  }

  const section = document.createElement('section');

  section.innerHTML = `
    <h1>Wedstrijdbeheer</h1>
    <p class="sub">
      Controleer geïmporteerde wedstrijden
      van alle toernooien.
    </p>

    <div class="notice">
      Beheerdersoverzicht. Alleen toekomstige, nog niet gestarte wedstrijden zonder geopende voorspellingen kunnen worden gecorrigeerd.
    </div>

    <div class="section-head">
      <h2>Wedstrijden</h2>
      <button class="btn secondary"
              id="admin-refresh">
        Vernieuwen
      </button>
    </div>

    <div class="panel table-wrap">
      <div id="admin-matches">
        Wedstrijden laden...
      </div>
    </div>
  `;

  layout.appendChild(section);

  document.getElementById('admin-refresh').onclick =
    loadAdminMatches;

  loadAdminMatches();
};

let adminMatchesCache = [];

async function loadAdminMatches() {
  const target = document.getElementById('admin-matches');
  if (!target) return;
  target.textContent = 'Wedstrijden laden...';
  const { data, error } = await supabase.rpc('admin_get_matches');
  if (!target.isConnected) return;
  if (error) {
    console.error('Wedstrijdbeheer:', error);
    target.textContent = 'Wedstrijden laden mislukt.';
    return;
  }
  adminMatchesCache = data ?? [];
  if (adminMatchesCache.length === 0) {
    target.textContent = 'Geen wedstrijden gevonden.';
    return;
  }
  const reviewCount = adminMatchesCache.filter(m => m.needs_review).length;
  const rows = adminMatchesCache.map(m => {
    const start = m.scheduled_start ? fmt(m.scheduled_start) : 'Onbekend';
    const lockedForEdit = m.match_status !== 'scheduled' ||
      m.actual_start != null || m.predictions_enabled ||
      (m.scheduled_start != null && new Date(m.scheduled_start) <= new Date());
    return `<tr>
      <td>${esc(m.tournament_name)}</td>
      <td>${esc(m.home_name)}</td>
      <td>${esc(m.away_name)}</td>
      <td>${esc(m.round_name ?? 'Onbekend')}</td>
      <td>${esc(start)}</td>
      <td>${m.start_time_confirmed ? 'Bevestigd' : 'Niet bevestigd'}</td>
      <td>${m.needs_review ? 'Controle nodig' : 'Gecontroleerd'}</td>
      <td>${m.predictions_enabled ? 'Open' : 'Gesloten'}</td>
      <td><button class="btn secondary" data-edit-match="${esc(m.match_id)}"
        ${lockedForEdit ? 'disabled title="Wedstrijd niet wijzigbaar via deze procedure"' : 'title="Ronde en starttijd bewerken"'}>Bewerken</button></td>
    </tr>`;
  }).join('');
  target.innerHTML = `<p class="muted mini">${adminMatchesCache.length} wedstrijden gevonden. ${reviewCount} vereisen controle.</p>
  <table><thead><tr><th>Toernooi</th><th>Speler 1</th><th>Speler 2</th><th>Ronde</th><th>Starttijd</th><th>Starttijdstatus</th><th>Controle</th><th>Voorspellen</th><th>Actie</th></tr></thead>
  <tbody>${rows}</tbody></table>`;
  target.querySelectorAll('[data-edit-match]').forEach(button => {
    button.onclick = () => editAdminMatch(button.dataset.editMatch);
  });
}

function localDateTimeValue(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

async function editAdminMatch(matchId) {
  if (currentRole !== 'admin' && currentRole !== 'super_admin') return;
  const match = adminMatchesCache.find(m => m.match_id === matchId);
  const target = document.getElementById('admin-matches');
  if (!match || !target) return;
  let editor = document.getElementById('admin-editor');
  if (!editor) {
    editor = document.createElement('div');
    editor.id = 'admin-editor';
    editor.className = 'panel stack';
    target.parentElement.appendChild(editor);
  }
  editor.textContent = 'Beschikbare rondes laden...';
  const { data: rounds, error } = await supabase.rpc('admin_get_tournament_rounds', {
    p_tournament_id: match.tournament_id
  });
  if (!editor.isConnected) return;
  if (error) {
    console.error('Rondes:', error);
    editor.textContent = 'Rondes ophalen mislukt.';
    return;
  }
  const options = ['<option value="">Onbekend</option>', ...(rounds ?? []).map(r =>
    `<option value="${esc(r.round_id)}" ${r.round_id === match.round_id ? 'selected' : ''}>${esc(r.round_name)}</option>`
  )].join('');
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  editor.innerHTML = `<h2>Wedstrijd bewerken</h2>
    <p>${esc(match.home_name)} – ${esc(match.away_name)}</p>
    <form id="admin-edit-form" class="stack">
      <div class="field"><label for="edit-round">Ronde</label><select id="edit-round">${options}</select></div>
      <div class="field"><label for="edit-start">Starttijd</label>
        <input id="edit-start" type="datetime-local" value="${localDateTimeValue(match.scheduled_start)}">
        <div class="hint">Tijdzone van dit apparaat: ${esc(timezone)}. Controleer dat dit Nederlandse tijd is als je Nederlandse tijden invoert.</div>
      </div>
      <label><input id="edit-confirmed" type="checkbox" ${match.start_time_confirmed ? 'checked' : ''}> Officiële starttijd bevestigd</label>
      <p id="admin-edit-message" role="status"></p>
      <div class="row"><button class="btn" type="submit">Wijzigingen opslaan</button>
      <button class="btn secondary" type="button" id="admin-edit-cancel">Annuleren</button></div>
    </form>`;
  editor.querySelector('#admin-edit-cancel').onclick = () => editor.remove();
  editor.querySelector('#admin-edit-form').onsubmit = async event => {
    event.preventDefault();
    const button = editor.querySelector('button[type="submit"]');
    const message = editor.querySelector('#admin-edit-message');
    const roundId = editor.querySelector('#edit-round').value || null;
    const startInput = editor.querySelector('#edit-start').value;
    const confirmed = editor.querySelector('#edit-confirmed').checked;
    const parsed = startInput ? new Date(startInput) : null;
    if (parsed && Number.isNaN(parsed.getTime())) {
      message.textContent = 'Ongeldige starttijd.';
      return;
    }
    if (confirmed && !parsed) {
      message.textContent = 'Een bevestigde starttijd mag niet leeg zijn.';
      return;
    }
    if (parsed && parsed <= new Date()) {
      message.textContent = 'De nieuwe starttijd moet in de toekomst liggen.';
      return;
    }
    button.disabled = true;
    message.textContent = 'Wijzigingen opslaan...';
    const { error: saveError } = await supabase.rpc('admin_correct_match_schedule', {
      p_match_id: match.match_id,
      p_round_id: roundId,
      p_scheduled_start: parsed ? parsed.toISOString() : null,
      p_start_confirmed: confirmed
    });
    if (!editor.isConnected) return;
    if (saveError) {
      console.error('Opslaan:', saveError);
      message.textContent = `Opslaan mislukt: ${saveError.message}`;
      button.disabled = false;
      return;
    }
    editor.remove();
    await loadAdminMatches();
  };
}
