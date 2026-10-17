import {validAccent,accentPalette,applyAccent} from './branding.js?v=crop-20261017';
import { createClient } from
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import {loadTournamentCatalog,loadTournamentDetail} from './online-tournaments.js?v=crop-20261017';
import {loadOnlineProfile} from './online-profile.js?v=account-20261016';

// Centrally configured branding; no user data is stored in the public response.
let brandAccent=null,appearanceRevision=0,appearanceController=null;
function applyBrandAccent(){applyAccent(brandAccent);}
async function readAppAppearance(){
 const revision=appearanceRevision,r=await supabase.rpc('get_app_appearance');if(r.error)throw Error(r.error.message);
 const color=r.data?.accent??null;if(color!==null&&!validAccent(color))throw Error('Ongeldige kleurinstelling ontvangen.');
 if(revision===appearanceRevision){brandAccent=color;applyBrandAccent();}return revision===appearanceRevision?color:brandAccent;
}
function loadAppearanceSettings(target){
 appearanceController?.abort();appearanceController=new AbortController();
 const userId=currentUser.id;
 target.innerHTML='<h2>Uiterlijk van Predict</h2><p>De accentkleur geldt voor alle gebruikers, ook op het inlogscherm. Licht en donker worden automatisch aangepast voor leesbare tekst.</p><form class="stack" data-appearance-form><label for="app-accent">Accentkleur</label><div class="accent-inputs"><input id="app-accent" type="color" value="#126f6b"><input id="app-accent-hex" aria-label="Kleurcode" pattern="#[0-9a-fA-F]{6}" maxlength="7" value="#126f6b" required spellcheck="false"></div><div class="accent-previews" aria-label="Kleurvoorbeeld"></div><p data-appearance-message role="status"></p><div class="toolbar"><button class="btn" type="submit">Kleur opslaan</button><button class="ghost" type="button" data-accent-reset>Standaardkleur herstellen</button><button class="ghost" type="button" data-accent-read>Opnieuw ophalen</button></div></form>';
 const form=target.querySelector('form'),picker=form.querySelector('#app-accent'),hex=form.querySelector('#app-accent-hex'),message=form.querySelector('[data-appearance-message]');
 const active=()=>target.isConnected&&currentUser?.id===userId&&['admin','super_admin'].includes(currentRole);
 const preview=()=>{if(!validAccent(hex.value))return;target.querySelector('.accent-previews').innerHTML=[false,true].map(dark=>{const p=form.dataset.useDefault==='true'?{accent:dark?'#58c6b0':'#126f6b',text:dark?'#10241e':'#ffffff'}:accentPalette(hex.value,dark);return `<div style="background:${dark?'#1e1e1e':'#ffffff'};color:${dark?'#f0f4f9':'#172335'}"><span>${dark?'Donker':'Licht'}</span><span class="accent-sample" style="background:${p.accent};color:${p.text}">Voorbeeld</span></div>`;}).join('');};
 form.oninput=event=>{form.dataset.useDefault='false';form.dataset.koDirty='true';message.textContent='';if(event.target===picker)hex.value=picker.value;else if(validAccent(hex.value))picker.value=hex.value;preview();};preview();
 const load=async()=>{message.textContent='Kleur laden…';try{const color=await readAppAppearance();if(!active())return;if(form.dataset.koDirty!=='true'){form.dataset.useDefault=String(color===null);picker.value=hex.value=color||'#126f6b';preview();}message.textContent='';}catch(error){if(active()){message.textContent='Ophalen mislukt: '+error.message;message.className='error';}}};
 const save=async color=>{if(!active())return;if(color!==null&&!validAccent(color)){message.textContent='Vul een geldige kleurcode in, bijvoorbeeld #2459B8.';message.className='error';hex.focus();return;}
   const controls=[...form.querySelectorAll('input,button')];controls.forEach(x=>x.disabled=true);message.className='';message.textContent='Opslaan…';
   try{const r=await supabase.rpc('set_app_appearance',{p_accent:color});if(!active())return;if(r.error)throw Error(r.error.message);const saved=r.data?.accent??null;if(saved!==null&&!validAccent(saved))throw Error('Ongeldige kleurinstelling ontvangen.');appearanceRevision++;brandAccent=saved;applyBrandAccent();picker.value=hex.value=saved||'#126f6b';form.dataset.koDirty='false';form.dataset.useDefault=String(saved===null);preview();message.textContent=saved?'Accentkleur opgeslagen.':'Standaardkleur hersteld.';message.className='success';}
   catch(error){if(active()){message.textContent='Opslaan mislukt: '+error.message;message.className='error';}}
   finally{if(active())controls.forEach(x=>x.disabled=false);}
 };
 form.onsubmit=event=>{event.preventDefault();save(hex.value);};form.querySelector('[data-accent-reset]').onclick=()=>save(null);
 form.querySelector('[data-accent-read]').onclick=()=>{if(form.dataset.koDirty!=='true'||confirm('Niet-opgeslagen kleurwijzigingen laten vervallen?')){form.dataset.koDirty='false';load();}};
 window.addEventListener('beforeunload',event=>{if(active()&&form.dataset.koDirty==='true'){event.preventDefault();event.returnValue='';}},{signal:appearanceController.signal});
 load();
}

// Route native Auth callbacks to the isolated, non-persistent account flow.
const authCallback = new URLSearchParams(location.hash.slice(1));
const legacyInvite = new URLSearchParams(location.search).get('invite');
if (['invite','recovery'].includes(authCallback.get('type')) || legacyInvite || new URLSearchParams(location.search).has('token_hash')) {
  location.replace(new URL('./account.html',location.href).href + (legacyInvite ? '#invite='+encodeURIComponent(legacyInvite) : location.search+location.hash));
  await new Promise(()=>{});
}

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
const STORE='predict-ui-v2';
const defaults={theme:'light',user:'Demo-gebruiker',tab:'home',tournament:null,predictions:{},extra:{},pools:[{id:'friends',tournament:'darts27',name:'Vriendengroep',members:['Demo-gebruiker','Thomas','Mark']}],joined:['darts27','football'],showAdmin:false};
function read(){
  try {
    localStorage.removeItem('predict-demo-v1');
    const value=JSON.parse(localStorage.getItem(STORE)||'{}');
    return {theme:['light','dark','system'].includes(value.theme)?value.theme:'system',
      tab:'home',user:'Gebruiker',tournament:null};
  } catch {return {theme:'system',tab:'home',user:'Gebruiker',tournament:null};}
}
let state=read();const save=()=>{try{localStorage.setItem(STORE,JSON.stringify({theme:state.theme,tab:state.tab}));}catch{/* Optional UI cache must not block account updates. */}};
const themeMedia=window.matchMedia('(prefers-color-scheme: dark)');
function isDarkTheme(){return state.theme==='dark'||(state.theme==='system'&&themeMedia.matches);}
function applyTheme(){
  document.body.classList.toggle('dark',isDarkTheme());applyBrandAccent();
  const button=document.querySelector('[data-action="theme"]');
  if(button)button.textContent=isDarkTheme()?'☀ Licht':'◐ Donker';
}
themeMedia.addEventListener('change',()=>{if(state.theme==='system')applyTheme();});
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
function nav(){return '<div class="nav" hidden></div>';}
function header(){const initial=Array.from(currentProfile?.username||'G')[0].toLocaleUpperCase('nl-NL');return `<header class="top"><button type="button" class="logo logo-button" data-tab="home" aria-label="Home" title="Naar Mijn spellen"><span class="logo-mark">P</span><span><span class="brand">PREDICT.</span><span class="tag">SPORTVOORSPELLINGEN</span></span></button><div class="header-actions">${['admin','super_admin'].includes(currentRole)?'<button type="button" class="header-icon" data-tab="admin" aria-label="Beheer" title="Beheer">⚙</button>':''}<button type="button" class="account-avatar" data-tab="profile" aria-label="Account" title="Accountinstellingen">${esc(initial)}</button></div></header>`;}

function tournamentCard(t){return `<div class="panel stack"><div class="row"><span class="sport">${t.sport==='darts'?'DARTS':'VOETBAL'}</span><span class="pill mutedpill">${esc(t.state)}</span></div><h2 style="margin:0">${esc(t.name)}</h2><div class="muted mini">${esc(t.description)}</div><div class="row"><span class="mini muted">${missing(t.id)} nog te voorspellen</span><span class="mini"><b>${points(t.id)} pt</b></span></div><button class="btn" data-open="${t.id}">Open toernooi →</button></div>`}
function home(){return `<h1>Mijn toernooien</h1><p class="sub">Welkom, ${esc(state.user)}. Overzicht van jouw toernooien en voorspellingen.</p><div class="notice">Dit is een lokale demonstratie met fictieve wedstrijden. Er worden nog geen echte accounts, poules of uitslagen gesynchroniseerd.</div><div class="grid">${tournaments.filter(t=>state.joined.includes(t.id)).map(tournamentCard).join('')}</div>`}
function discover(){return `<h1>Toernooien</h1><p class="sub">Kies een beschikbaar toernooi. Alleen systeembeheerders zullen later toernooien kunnen toevoegen.</p><div class="grid">${tournaments.map(tournamentCard).join('')}</div>`}
function pools(){return `<h1>Mijn privépoules</h1><p class="sub">Iedere poule behoort tot één toernooi. Voorspellingen blijven per toernooi centraal opgeslagen.</p><div class="grid">${state.pools.map(p=>`<div class="panel stack"><h2>${esc(p.name)}</h2><div class="muted mini">${esc(tournaments.find(t=>t.id===p.tournament)?.name||'')}</div><div>${p.members.length} leden</div><button class="btn secondary" data-open="${p.tournament}">Open toernooi</button></div>`).join('')}</div><div class="section-head"><h2>Demonstratie: poule aanmaken</h2></div><form class="panel stack" id="pool-form"><div class="field"><label for="pool-name">Naam van de poule</label><input id="pool-name" required maxlength="60" placeholder="Bijvoorbeeld: Collega's"></div><div class="field"><label for="pool-tournament">Toernooi</label><select id="pool-tournament">${tournaments.map(t=>`<option value="${t.id}">${esc(t.name)}</option>`).join('')}</select></div><button class="btn">Maak lokale demo-poule</button><div class="hint">Er worden nog geen uitnodigingen verzonden. Een echte poule vereist gebruikersauthenticatie en databaseopslag.</div></form>`}
function profile(){return `<h1>Profiel en instellingen</h1><p class="sub">Lokale demo-instellingen.</p><form class="panel stack" id="profile-form"><div class="field"><label for="username">Weergavenaam</label><input id="username" required maxlength="40" value="${esc(state.user)}"></div><button class="btn">Opslaan</button></form><div class="section-head"><h2>Mijn voorspellingen</h2></div><div class="panel table-wrap"><table><thead><tr><th>Wedstrijd</th><th>Voorspelling</th><th>Fase</th></tr></thead><tbody>${fixtures.filter(m=>state.predictions[m.id]).map(m=>`<tr><td>${esc(m.home)} – ${esc(m.away)}</td><td>${state.predictions[m.id].home}–${state.predictions[m.id].away}</td><td>${esc(m.round)}</td></tr>`).join('')||'<tr><td colspan="3">Nog geen voorspellingen</td></tr>'}</tbody></table></div><div class="section-head"><h2>Demo resetten</h2></div><button class="ghost" data-action="reset">Verwijder lokale demogegevens</button>`}
function matchCard(m){const p=state.predictions[m.id],isLocked=locked(m);return `<div class="panel match"><div class="row"><span class="mini muted">${esc(m.round)} · ${fmt(m.start)}</span><span class="pill ${isLocked?'mutedpill':''}">${isLocked?'Gesloten':p?'Ingevuld':'Open'}</span></div><div class="teams"><span>${esc(m.home)}<br><span class="muted">${esc(m.away)}</span></span><span class="score">${p?`${p.home}–${p.away}`:'–'}</span></div><form class="prediction-form stack" data-match="${m.id}"><div class="two"><div class="field"><label>Score ${esc(m.home)}</label><input type="number" name="home" min="0" max="99" step="1" value="${p?p.home:''}" ${isLocked?'disabled':''} required></div><div class="field"><label>Score ${esc(m.away)}</label><input type="number" name="away" min="0" max="99" step="1" value="${p?p.away:''}" ${isLocked?'disabled':''} required></div></div><div class="row"><span class="hint">${m.format==='sets'?`Eén speler moet ${m.firstTo} sets winnen; de ander maximaal ${m.firstTo-1}.`:'Gelijkspel toegestaan; score vóór strafschoppen.'}</span><button class="btn" ${isLocked?'disabled':''}>${p?'Wijzigen':'Opslaan'}</button></div></form>${m.official?`<div class="notice">Officieel ${m.official.home}–${m.official.away} · ${score(m,p)} punten</div>`:''}</div>`}
function extra(t){if(t.sport!=='football')return `<div class="notice">Voor dit demo-dartstoernooi zijn geen extra vragen geconfigureerd.</div>`;return `<div class="panel stack"><h2>Extra toernooivoorspellingen</h2><p class="hint">De definitieve applicatie sluit alle extra vragen vóór de eerste wedstrijd van het toernooi. Dit demonstratieformulier heeft alleen lokale opslag.</p><form id="extra-form" class="stack"><div class="field"><label for="champ">Wie wordt kampioen?</label><select name="champ" id="champ"><option value="">Selecteer een land</option>${['Nederland','Duitsland','Spanje','Frankrijk'].map(x=>`<option ${state.extra.champ===x?'selected':''}>${x}</option>`).join('')}</select></div><div class="field"><label for="scorer">Wie wordt topscorer?</label><input id="scorer" name="scorer" maxlength="80" value="${esc(state.extra.scorer||'')}" placeholder="Naam van de speler"></div><button class="btn">Voorspellingen lokaal opslaan</button></form></div>`}
function leaderboard(t){return `<div class="panel stack"><h2>Klassement ${esc(t.name)}</h2><p class="hint">Een echt klassement komt uitsluitend uit de beveiligde database. Andere gebruikers en punten worden niet verzonnen in de demo.</p><div class="table-wrap"><table><thead><tr><th>#</th><th>Gebruiker</th><th class="num">Punten</th></tr></thead><tbody><tr><td>1</td><td>${esc(state.user)} (demo)</td><td class="num">${points(t.id)}</td></tr></tbody></table></div></div>`}
function tournamentView(t){let ms=fixtures.filter(m=>m.tournament===t.id);return `<div class="breadcrumb"><button data-action="back">← Mijn toernooien</button></div><div class="row"><div><span class="sport">${t.sport==='darts'?'DARTS':'VOETBAL'}</span><h1>${esc(t.name)}</h1></div><span class="pill">${esc(t.state)}</span></div><p class="sub">${esc(t.description)}</p><div class="grid three"><div class="panel"><div class="stat-label">Mijn punten</div><div class="stat">${points(t.id)}</div></div><div class="panel"><div class="stat-label">Nog voorspellen</div><div class="stat">${missing(t.id)}</div></div><div class="panel"><div class="stat-label">Wedstrijden (demo)</div><div class="stat">${ms.length}</div></div></div><div class="section-head"><h2>Wedstrijden</h2><span class="mini muted">Nederlandse tijd</span></div><div class="grid">${ms.map(matchCard).join('')}</div><div class="section-head"><h2>Extra voorspellingen</h2></div>${extra(t)}<div class="section-head"><h2>Klassement</h2></div>${leaderboard(t)}${t.sport==='darts'?`<div class="section-head"><h2>Puntentabel WK Darts 2027</h2></div><div class="panel table-wrap"><table><thead><tr><th>Ronde</th><th class="num">Winnaar</th><th class="num">Exact totaal</th></tr></thead><tbody>${Object.entries(dartsPts).map(([round,arr])=>`<tr><td>${esc(round)}</td><td class="num">${arr[0]}</td><td class="num">${arr[1]}</td></tr>`).join('')}</tbody></table></div>`:''}`}
function render(){document.body.className=isDarkTheme()?'dark':'';const t=activeTournament();$('app').innerHTML=`<main class="layout">${header()}${t?tournamentView(t):nav()+(state.tab==='home'?home():state.tab==='discover'?discover():state.tab==='pools'?pools():profile())}<div class="footer">Predict · Lokale ontwerp- en functiedemo · Geen officiële sportdata · Geen online accounts</div></main>`;bind()}
function bind(){document.querySelectorAll('[data-tab]').forEach(el=>el.onclick=()=>{state.tab=el.dataset.tab;save();render()});document.querySelectorAll('[data-open]').forEach(el=>el.onclick=()=>{state.tournament=el.dataset.open;save();render()});document.querySelectorAll('[data-action]').forEach(el=>el.onclick=()=>{if(el.dataset.action==='theme')state.theme=isDarkTheme()?'light':'dark';if(el.dataset.action==='back'){state.tournament=null;state.tab='home'}if(el.dataset.action==='reset'&&confirm('Alleen lokale demogegevens wissen?'))state=structuredClone(defaults);save();render()});document.querySelectorAll('.prediction-form').forEach(form=>form.onsubmit=e=>{e.preventDefault();const m=fixtures.find(x=>x.id===form.dataset.match);if(locked(m)){alert('De voorspeldeadline is verstreken.');render();return}const data=new FormData(form),a=Number(data.get('home')),b=Number(data.get('away'));if(!Number.isInteger(a)||!Number.isInteger(b)||a<0||b<0||a>99||b>99){alert('Vul twee geldige scores in.');return}if(m.format==='sets'&&!((a===m.firstTo&&b<m.firstTo)||(b===m.firstTo&&a<m.firstTo))){alert(`Eén darter moet precies ${m.firstTo} sets winnen.`);return}state.predictions[m.id]={home:a,away:b,updatedAt:new Date().toISOString()};save();render()});const pool=$('pool-form');if(pool)pool.onsubmit=e=>{e.preventDefault();const name=$('pool-name').value.trim();if(!name)return;state.pools.push({id:crypto.randomUUID(),name,tournament:$('pool-tournament').value,members:[state.user]});save();render()};const profileForm=$('profile-form');if(profileForm)profileForm.onsubmit=e=>{e.preventDefault();const n=$('username').value.trim();if(n)state.user=n;save();render()};const extraForm=$('extra-form');if(extraForm)extraForm.onsubmit=e=>{e.preventDefault();const d=new FormData(extraForm);state.extra={champ:d.get('champ'),scorer:String(d.get('scorer')).trim()};save();render()}}

let currentUser = null;
let currentRole = 'user';
let currentProfile = null;
let profileRevision = 0;
let profileWriteQueue = Promise.resolve();
function applyAccountProfile(profile){
  currentProfile={...currentProfile,...profile};
  state.user=currentProfile.display_name||currentProfile.username||'Gebruiker';
  state.theme=['system','light','dark'].includes(currentProfile.theme)?currentProfile.theme:'system';
  save();applyTheme();
  window.dispatchEvent(new CustomEvent('predict-preferences-saved',{detail:currentProfile}));
}
function persistProfile(changes){
  const userId=currentUser?.id;
  const request=profileWriteQueue.catch(()=>{}).then(async()=>{
    if(!userId||currentUser?.id!==userId)throw new Error('Je bent niet meer ingelogd met dit account.');
    const {data,error}=await supabase.rpc('update_my_profile',changes);
    if(error)throw new Error(error.message);
    if(currentUser?.id!==userId)throw new Error('Het actieve account is gewijzigd.');
    profileRevision++;applyAccountProfile(data);return data;
  });
  profileWriteQueue=request;return request;
}

const renderDemo = render;

render = function () {
  if (!currentUser) {
    document.body.className =
      isDarkTheme() ? 'dark' : '';

    $('app').innerHTML = `
      <main class="layout">
        <header class="top">
          <div class="logo">
            <div class="logo-mark">P</div>
            <div>
              <div class="brand">PREDICT.</div>
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
              <label for="login-email">Gebruikersnaam</label>
              <input
                id="login-email"
                type="text"
                autocomplete="username"
                maxlength="128"
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
          <a href="./account.html">Wachtwoord vergeten?</a>
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

      try {
        // Existing email/password accounts keep working while usernames become the default.
        if(email.includes('@')){
          const r=await supabase.auth.signInWithPassword({email,password});if(r.error)throw Error();
        }else{
          const r=await supabase.functions.invoke('username-login',{body:{username:email,password}});
          if(r.error||!r.data?.access_token||!r.data?.refresh_token)throw Error();
          const session=await supabase.auth.setSession(r.data);if(session.error)throw Error();
        }
        state.tab='home';await loadCurrentUser();
      }catch{
        if(errorElement.isConnected)errorElement.textContent='Inloggen mislukt. Controleer je gegevens of probeer over vijftien minuten opnieuw.';
      }finally{if(button.isConnected)button.disabled=false;}
    };

    return;
  }

  renderDemo();
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
      .select('username, display_name, theme')
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

  applyAccountProfile(profile);

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
    <h1>Beheer</h1>
    <p class="sub">
      Beheer je toernooien, wedstrijden en accounts.
    </p>

    <div class="notice">
      Beheerdersoverzicht. Alleen toekomstige, nog niet gestarte wedstrijden zonder geopende voorspellingen kunnen worden gecorrigeerd.
    </div>

    <div class="section-head">
      <h2>Toernooipublicatie</h2>
    </div>
    <div class="panel" id="admin-tournament-publications">
      Toernooistatus laden...
    </div>

    <div class="section-head">
      <h2>QA-test: echte voorspelling</h2>
    </div>
    <div class="panel stack" id="qa-prediction-panel">
      QA-testwedstrijd laden...
    </div>

    <div class="section-head">
      <h2>Echte klassementen</h2>
    </div>
    <div class="panel stack" id="admin-leaderboards">
      Klassementen laden...
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
  loadAdminTournamentPublications();
  loadQaPredictionForm();
  loadAdminLeaderboards();
};

// Gebruik dezelfde beschikbaarheidscontrole in de tabel en de uitslagpop-up.
// De databasefunctie admin_record_match_result herhaalt alle controles.
function canRecordAdminResult(match) {
  const startedByActualTime =
    match.match_status === 'live' &&
    match.actual_start != null &&
    Number.isFinite(new Date(match.actual_start).getTime()) &&
    new Date(match.actual_start) <= new Date();

  const startedBySchedule =
    match.match_status === 'scheduled' &&
    match.scheduled_start != null &&
    Number.isFinite(new Date(match.scheduled_start).getTime()) &&
    new Date(match.scheduled_start) <= new Date();

  const validFormat = match.score_unit === 'goals' ||
    (['sets', 'legs'].includes(match.score_unit) &&
     Number.isInteger(match.first_to) &&
     match.first_to >= 1 && match.first_to <= 99);

  return Boolean((startedByActualTime || startedBySchedule) &&
    match.round_id && validFormat);
}

let adminMatchesCache = [];
let adminShowAllMatches=false;

async function loadAdminMatches() {
  const target = document.getElementById('admin-matches');
  if (!target) return;
  target.textContent = 'Wedstrijden laden...';
  const [response,resultResponse]=await Promise.all([supabase.rpc('admin_get_matches'),supabase.rpc('admin_match_results')]);
  const {data,error}=response;
  if (!target.isConnected) return;
  if (error) {
    console.error('Wedstrijdbeheer:', error);
    target.textContent = 'Wedstrijden laden mislukt.';
    return;
  }
  const results=new Map((resultResponse.data||[]).map(x=>[x.id,x]));
  adminMatchesCache = (data??[]).map(m=>({...m,...results.get(m.match_id)}));
  if (adminMatchesCache.length === 0) {
    target.textContent = 'Geen wedstrijden gevonden.';
    return;
  }
  const reviewCount = adminMatchesCache.filter(m => m.needs_review).length;
  const isOpen=m=>m.predictions_enabled&&m.match_status==='scheduled'&&!m.actual_start&&!m.needs_review&&m.start_time_confirmed&&Date.parse(m.scheduled_start)>Date.now();
  const visible=adminMatchesCache.filter(m=>adminShowAllMatches||isOpen(m)||(m.home_score==null&&m.away_score==null&&['scheduled','live'].includes(m.match_status)&&(Date.parse(m.actual_start)<=Date.now()||Date.parse(m.scheduled_start)<=Date.now())));
  const rows = visible.map(m => {
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
      <td>${isOpen(m)?'Voorspellen open':m.home_score!=null?'Afgerond':canRecordAdminResult(m)?'Uitslag nodig':'Voorspellen gesloten'}</td><td class="result-column">${m.home_score!=null?esc(m.home_score)+'–'+esc(m.away_score):'—'}</td>
      <td>
        <div style="display:flex;gap:6px;flex-wrap:wrap">
          <button class="btn secondary" data-edit-match="${esc(m.match_id)}"
            ${lockedForEdit ? 'disabled title="Wedstrijd niet wijzigbaar via deze procedure"' : 'title="Ronde en starttijd bewerken"'}>Bewerken</button>
          <button class="btn secondary" data-approve-match="${esc(m.match_id)}"
            ${m.match_status !== 'scheduled' || m.actual_start != null ||
              m.predictions_enabled || !m.start_time_confirmed ||
              !m.scheduled_start || new Date(m.scheduled_start) <= new Date() ||
              !m.needs_review
              ? 'disabled title="Goedkeuren vereist een bevestigde toekomstige starttijd, gesloten voorspellingen en een wedstrijd die nog niet begonnen is"'
              : 'title="Wedstrijdgegevens controleren en goedkeuren"'}>Goedkeuren</button>
          <button class="btn secondary" data-start-match="${esc(m.match_id)}"
            ${m.match_status !== 'scheduled' || m.actual_start != null
              ? 'disabled title="Alleen een nog niet als gestart geregistreerde wedstrijd kan worden gestart"'
              : 'title="Registreer de waargenomen daadwerkelijke start en sluit voorspellingen"'}>Wedstrijd gestart</button>
          <button class="btn secondary" data-result-match="${esc(m.match_id)}"
            ${!canRecordAdminResult(m)
              ? 'disabled title="Uitslag vereist een geregistreerde werkelijke start of verstreken geplande starttijd, plus geldige ronde en formaat"'
              : 'title="Handmatige eindstand met auditregistratie invoeren"'}>Uitslag invoeren</button>
        </div>
      </td>
    </tr>`;
  }).join('');
  target.innerHTML = `<p class="muted mini">${resultResponse.error?'Uitslagen laden mislukt: '+esc(resultResponse.error.message)+'. ':''}Nog af te handelen · ${visible.length} van ${adminMatchesCache.length} wedstrijden. ${reviewCount} vereisen controle.</p><label class="choice"><input type="checkbox" id="admin-show-all" ${adminShowAllMatches?'checked':''}>Toon alle wedstrijden</label>${!visible.length?'<p>Geen wedstrijden om af te handelen.</p>':''}
  <table><thead><tr><th>Toernooi</th><th>Speler 1</th><th>Speler 2</th><th>Ronde</th><th>Starttijd</th><th>Starttijdstatus</th><th>Controle</th><th>Voorspellen</th><th class="result-column">Uitslag</th><th>Actie</th></tr></thead>
  <tbody>${rows}</tbody></table>`;
  target.querySelector('table').classList.add('admin-match-table');
  const columnLabels=['Toernooi','Speler 1','Speler 2','Ronde','Starttijd','Starttijdstatus','Controle','Voorspellen','Uitslag','Actie'];
  target.querySelectorAll('tbody tr').forEach(row=>[...row.cells].forEach((cell,i)=>cell.dataset.label=columnLabels[i]));
  target.querySelector('#admin-show-all').onchange=e=>{adminShowAllMatches=e.target.checked;loadAdminMatches();};
  target.querySelectorAll('[data-edit-match]').forEach(button => {
    button.onclick = () => editAdminMatch(button.dataset.editMatch);
  });
  target.querySelectorAll('[data-approve-match]').forEach(button => {
    button.onclick = () => approveAdminMatch(button.dataset.approveMatch);
  });
  target.querySelectorAll('[data-start-match]').forEach(button => {
    button.onclick = () => recordAdminMatchStart(button.dataset.startMatch);
  });
  target.querySelectorAll('[data-result-match]').forEach(button => {
    button.onclick = () => recordAdminMatchResult(button.dataset.resultMatch);
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
  // Eén modal tegelijk, zodat formulieren elkaar niet kunnen overlappen.
  document.getElementById('admin-editor')?.close();
  const editor = document.createElement('dialog');
  editor.id = 'admin-editor';
  editor.className = 'panel stack';
  editor.setAttribute('aria-labelledby', 'admin-edit-title');
  Object.assign(editor.style, {
    width: 'min(520px, calc(100% - 32px))',
    maxHeight: '85vh',
    overflowY: 'auto',
    margin: 'auto',
    padding: '28px',
    borderRadius: '16px',
    border: '1px solid #374151',
    background: isDarkTheme() ? '#1e293b' : '#ffffff',
    color: isDarkTheme() ? '#ffffff' : '#111827',
    boxShadow: '0 20px 80px rgba(0,0,0,.55)'
  });
  // De backdrop hoort bij het modale dialoogelement.
  if (!document.getElementById('predict-modal-style')) {
    const style = document.createElement('style');
    style.id = 'predict-modal-style';
    style.textContent = '#admin-editor::backdrop { background: rgba(4, 10, 25, .75); }';
    document.head.appendChild(style);
  }
  document.body.appendChild(editor);
  editor.addEventListener('close', () => editor.remove(), { once: true });
  editor.textContent = 'Beschikbare rondes laden...';
  editor.showModal();
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
  const {dutchInput,dutchToUTC}=await import('./knockout.js?v=hub-20261017');
  editor.innerHTML = `<div class="row" style="justify-content:space-between;align-items:center;gap:12px">
      <h2 id="admin-edit-title" style="margin:0">Wedstrijd bewerken</h2>
      <button type="button" class="ghost" id="admin-edit-close" aria-label="Sluiten">✕</button>
    </div>
    <p>${esc(match.home_name)} – ${esc(match.away_name)}</p>
    <form id="admin-edit-form" class="stack">
      <div class="field"><label for="edit-round">Ronde</label><select id="edit-round">${options}</select></div>
      <div class="field"><label for="edit-start">Starttijd</label>
        <input id="edit-start" type="datetime-local" value="${dutchInput(match.scheduled_start)}">
        <div class="hint">Invoer in Nederlandse tijd (Europe/Amsterdam).</div>
      </div>
      <label><input id="edit-confirmed" type="checkbox" ${match.start_time_confirmed ? 'checked' : ''}> Officiële starttijd bevestigd</label>
      <p id="admin-edit-message" role="status"></p>
      <div class="row"><button class="btn" type="submit">Wijzigingen opslaan</button>
      <button class="btn secondary" type="button" id="admin-edit-cancel">Annuleren</button></div>
    </form>`;
  editor.querySelector('#admin-edit-cancel').onclick = () => editor.close();
  editor.querySelector('#admin-edit-close').onclick = () => editor.close();
  editor.querySelector('#admin-edit-form').onsubmit = async event => {
    event.preventDefault();
    const button = editor.querySelector('button[type="submit"]');
    const message = editor.querySelector('#admin-edit-message');
    const roundId = editor.querySelector('#edit-round').value || null;
    const startInput = editor.querySelector('#edit-start').value;
    const confirmed = editor.querySelector('#edit-confirmed').checked;
    let parsed;try{parsed=startInput?new Date(dutchToUTC(startInput)):null;}catch(error){message.textContent=error.message;return;}
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
    editor.close();
    await loadAdminMatches();
  };
}


// Goedkeuring is een afzonderlijke handeling; openen van voorspellingen
// gebeurt NIET via dit formulier.
async function approveAdminMatch(matchId) {
  if (!['admin', 'super_admin'].includes(currentRole)) return;
  const match = adminMatchesCache.find(m => m.match_id === matchId);
  if (!match) return;

  const oldDialog = document.getElementById('admin-approval-dialog');
  if (oldDialog) oldDialog.close();

  const dialog = document.createElement('dialog');
  dialog.id = 'admin-approval-dialog';
  dialog.className = 'panel stack';
  dialog.setAttribute('aria-labelledby', 'approval-title');
  Object.assign(dialog.style, {
    width: 'min(520px, calc(100% - 32px))',
    maxHeight: '85vh',
    overflowY: 'auto',
    margin: 'auto',
    padding: '28px',
    borderRadius: '16px',
    border: '1px solid #374151',
    background: isDarkTheme() ? '#1e293b' : '#ffffff',
    color: isDarkTheme() ? '#ffffff' : '#111827',
    boxShadow: '0 20px 80px rgba(0,0,0,.55)'
  });
  document.body.appendChild(dialog);
  dialog.addEventListener('close', () => dialog.remove(), { once: true });
  dialog.textContent = 'Wedstrijdgegevens laden...';
  dialog.showModal();

  const { data: rounds, error } = await supabase.rpc(
    'admin_get_tournament_rounds',
    { p_tournament_id: match.tournament_id }
  );
  if (!dialog.isConnected) return;

  if (error) {
    console.error('Rondes ophalen:', error);
    dialog.textContent = 'Kon de beschikbare rondes niet ophalen.';
    return;
  }

  const isEligible = match.match_status === 'scheduled' &&
    match.actual_start == null &&
    !match.predictions_enabled &&
    match.start_time_confirmed === true &&
    Boolean(match.scheduled_start) &&
    new Date(match.scheduled_start) > new Date() &&
    match.needs_review === true;

  const roundOptions = [
    '<option value="">Selecteer een ronde</option>',
    ...(rounds ?? []).map(r =>
      `<option value="${esc(r.round_id)}" ${r.round_id === match.round_id ? 'selected' : ''}>${esc(r.round_name)}</option>`
    )
  ].join('');

  const darts = match.score_unit === 'sets' || match.score_unit === 'legs';
  const formatField = darts
    ? `<div class="field">
         <label for="approval-first-to">Aantal ${match.score_unit === 'legs' ? 'legs' : 'sets'} om te winnen (first_to)</label>
         <input id="approval-first-to" type="number" min="1" max="99"
                step="1" required value="${Number.isInteger(match.first_to) ? match.first_to : ''}">
         <div class="hint">Controleer dit aan de hand van het officiële wedstrijdformaat.</div>
       </div>`
    : `<p class="hint">Voor voetbal is first_to niet van toepassing.</p>`;

  dialog.innerHTML = `
    <div class="row" style="justify-content:space-between;align-items:center;gap:12px">
      <h2 id="approval-title" style="margin:0">Wedstrijd goedkeuren</h2>
      <button type="button" class="ghost" id="approval-close" aria-label="Sluiten">✕</button>
    </div>
    <p><strong>${esc(match.home_name)} – ${esc(match.away_name)}</strong></p>
    <p class="hint">
      Geplande starttijd: ${match.scheduled_start ? esc(fmt(match.scheduled_start)) : 'Onbekend'}.
      Starttijd bevestigd: ${match.start_time_confirmed ? 'ja' : 'nee'}.
    </p>
    <div class="notice">
      Goedkeuren bevestigt de gegevens en schrijft een auditregistratie.
      <strong>Voorspellingen blijven gesloten.</strong>
    </div>
    <form id="approval-form" class="stack">
      <div class="field">
        <label for="approval-round">Gecontroleerde ronde</label>
        <select id="approval-round" required>${roundOptions}</select>
      </div>
      ${formatField}
      <label>
        <input id="approval-attest" type="checkbox" required>
        Ik heb de ronde, het wedstrijdformaat en de starttijd
        gecontroleerd aan de hand van een betrouwbare bron.
      </label>
      <p id="approval-message" role="status"></p>
      <div class="row">
        <button class="btn" type="submit" ${isEligible ? '' : 'disabled'}>
          Goedkeuring opslaan
        </button>
        <button class="btn secondary" type="button" id="approval-cancel">
          Annuleren
        </button>
      </div>
    </form>
  `;

  dialog.querySelector('#approval-close').onclick = () => dialog.close();
  dialog.querySelector('#approval-cancel').onclick = () => dialog.close();
  dialog.querySelector('#approval-form').onsubmit = async (event) => {
    event.preventDefault();
    const message = dialog.querySelector('#approval-message');
    const submit = dialog.querySelector('button[type="submit"]');
    const roundId = dialog.querySelector('#approval-round').value;
    const firstTo = darts
      ? Number(dialog.querySelector('#approval-first-to').value)
      : null;

    if (!isEligible || !roundId ||
        (darts && (!Number.isInteger(firstTo) || firstTo < 1 || firstTo > 99))) {
      message.textContent = 'De wedstrijdgegevens zijn nog niet geschikt voor goedkeuring.';
      return;
    }
    if (!dialog.querySelector('#approval-attest').checked) {
      message.textContent = 'Bevestig eerst dat de gegevens gecontroleerd zijn.';
      return;
    }

    submit.disabled = true;
    message.textContent = 'Goedkeuring opslaan...';
    const { error: saveError } = await supabase.rpc('admin_approve_match', {
      p_match_id: match.match_id,
      p_round_id: roundId,
      p_first_to: firstTo
    });
    if (!dialog.isConnected) return;
    if (saveError) {
      console.error('Goedkeuring:', saveError);
      message.textContent = `Goedkeuren mislukt: ${saveError.message}`;
      submit.disabled = false;
      return;
    }
    dialog.close();
    await loadAdminMatches();
  };
}


// Handmatige uitslagen: de serverfunctie valideert status, scoreformaat,
// wedstrijdstart, gebruikersrol en eerste registratie opnieuw.
// Het formulier kent geen mogelijkheid om een bestaande uitslag te overschrijven.
async function recordAdminMatchResult(matchId) {
  if (!['admin', 'super_admin'].includes(currentRole)) return;
  const match = adminMatchesCache.find(m => m.match_id === matchId);
  if (!match) return;

  document.getElementById('admin-result-dialog')?.close();
  const dialog = document.createElement('dialog');
  dialog.id = 'admin-result-dialog';
  dialog.className = 'panel stack';
  dialog.setAttribute('aria-labelledby', 'result-title');
  Object.assign(dialog.style, {
    width: 'min(520px, calc(100% - 32px))',
    maxHeight: '85vh', overflowY: 'auto', margin: 'auto',
    padding: '28px', borderRadius: '16px', border: '1px solid #374151',
    background: isDarkTheme() ? '#1e293b' : '#ffffff',
    color: isDarkTheme() ? '#ffffff' : '#111827',
    boxShadow: '0 20px 80px rgba(0,0,0,.55)'
  });
  if (!document.getElementById('predict-result-modal-style')) {
    const style = document.createElement('style');
    style.id = 'predict-result-modal-style';
    style.textContent = '#admin-result-dialog::backdrop{background:rgba(4,10,25,.75)}';
    document.head.appendChild(style);
  }
  document.body.appendChild(dialog);
  dialog.addEventListener('close', () => dialog.remove(), { once: true });
  const eligible = canRecordAdminResult(match);
  const formatHint = match.score_unit === 'goals'
    ? 'Voetbal: eindstand na eventuele verlenging, zonder strafschoppen.'
    : `Darts: de winnaar moet exact ${esc(String(match.first_to ?? '?'))} ` +
      `${match.score_unit === 'sets' ? 'sets' : 'legs'} hebben.`;
  dialog.innerHTML = `
    <div class="row" style="justify-content:space-between;align-items:center;gap:12px">
      <h2 id="result-title" style="margin:0">Uitslag invoeren</h2>
      <button type="button" class="ghost" id="result-close" aria-label="Sluiten">✕</button>
    </div>
    <p><strong>${esc(match.home_name)} – ${esc(match.away_name)}</strong></p>
    <p class="hint">${esc(match.tournament_name)} · ${esc(match.round_name ?? 'Ronde onbekend')} ·
    Geplande start: ${match.scheduled_start ? esc(fmt(match.scheduled_start)) : 'Onbekend'}</p>
    <p class="notice">${formatHint} Alleen de eerste registratie is toegestaan.
      De actie wordt vastgelegd in het auditlog. Een latere API-verificatie blijft noodzakelijk.</p>
    <form id="result-form" class="stack">
      <div class="row" style="gap:12px;flex-wrap:wrap">
        <div class="field"><label for="result-home">${esc(match.home_name)}</label>
          <input id="result-home" type="number" required min="0" max="999" step="1" style="max-width:120px"></div>
        <div class="field"><label for="result-away">${esc(match.away_name)}</label>
          <input id="result-away" type="number" required min="0" max="999" step="1" style="max-width:120px"></div>
      </div>
      <label><input id="result-verified" type="checkbox" required>
        Ik heb de eindstand gecontroleerd aan de hand van een betrouwbare uitslagenbron.</label>
      <p id="result-message" role="status"></p>
      <div class="row"><button type="submit" class="btn" ${eligible ? '' : 'disabled'}>Uitslag opslaan</button>
        <button type="button" class="btn secondary" id="result-cancel">Annuleren</button></div>
    </form>`;
  dialog.querySelector('#result-close').onclick = () => dialog.close();
  dialog.querySelector('#result-cancel').onclick = () => dialog.close();
  dialog.querySelector('#result-form').onsubmit = async event => {
    event.preventDefault();
    const message = dialog.querySelector('#result-message');
    const submit = dialog.querySelector('button[type="submit"]');
    const homeRaw = dialog.querySelector('#result-home').value;
    const awayRaw = dialog.querySelector('#result-away').value;
    const home = Number(homeRaw);
    const away = Number(awayRaw);
    if (!eligible || homeRaw === '' || awayRaw === '' ||
        !Number.isInteger(home) || !Number.isInteger(away) ||
        home < 0 || away < 0 || home > 999 || away > 999) {
      message.textContent = 'Voer twee geldige, gehele, niet-negatieve scores in.';
      return;
    }
    if (match.score_unit !== 'goals' && !(
        (home === match.first_to && away < match.first_to) ||
        (away === match.first_to && home < match.first_to))) {
      message.textContent = `Ongeldige dartuitslag: de winnaar moet exact ${match.first_to} halen.`;
      return;
    }
    if (!dialog.querySelector('#result-verified').checked) {
      message.textContent = 'Bevestig eerst dat de eindstand gecontroleerd is.';
      return;
    }
    if (!window.confirm(`Definitieve uitslag invoeren: ${match.home_name} ${home} – ${away} ${match.away_name}?`)) return;
    submit.disabled = true;
    message.textContent = 'Uitslag opslaan...';
    const { error } = await supabase.rpc('admin_record_match_result', {
      p_match_id: match.match_id,
      p_home_score: home,
      p_away_score: away
    });
    if (!dialog.isConnected) return;
    if (error) {
      console.error('Uitslagregistratie:', error);
      message.textContent = `Opslaan mislukt: ${error.message}`;
      submit.disabled = false;
      return;
    }
    dialog.close();
    await loadAdminMatches();
  };
}


// Registreer een daadwerkelijk waargenomen wedstrijdstart.
// De database bepaalt het registratie- en starttijdstip wanneer er geen
// afzonderlijk betrouwbaar tijdstip wordt doorgegeven. Dit kan afwijken
// van het daadwerkelijke aanvangsmoment bij vertraagde melding.
async function recordAdminMatchStart(matchId) {
  if (!['admin', 'super_admin'].includes(currentRole)) return;
  const match = adminMatchesCache.find(m => m.match_id === matchId);
  if (!match || match.match_status !== 'scheduled' || match.actual_start != null) return;

  document.getElementById('admin-start-dialog')?.close();
  const dialog = document.createElement('dialog');
  dialog.id = 'admin-start-dialog';
  dialog.className = 'panel stack';
  dialog.setAttribute('aria-labelledby', 'start-title');
  Object.assign(dialog.style, {
    width: 'min(540px, calc(100% - 32px))',
    maxHeight: '85vh', overflowY: 'auto', margin: 'auto',
    padding: '28px', borderRadius: '16px', border: '1px solid #374151',
    background: isDarkTheme() ? '#1e293b' : '#ffffff',
    color: isDarkTheme() ? '#ffffff' : '#111827',
    boxShadow: '0 20px 80px rgba(0,0,0,.55)'
  });
  if (!document.getElementById('predict-start-modal-style')) {
    const style = document.createElement('style');
    style.id = 'predict-start-modal-style';
    style.textContent = '#admin-start-dialog::backdrop{background:rgba(4,10,25,.75)}';
    document.head.appendChild(style);
  }
  document.body.appendChild(dialog);
  dialog.addEventListener('close', () => dialog.remove(), { once: true });

  dialog.innerHTML = `
    <div class="row" style="justify-content:space-between;align-items:center;gap:12px">
      <h2 id="start-title" style="margin:0">Werkelijke wedstrijdstart registreren</h2>
      <button type="button" class="ghost" id="start-close" aria-label="Sluiten">✕</button>
    </div>
    <p><strong>${esc(match.home_name)} – ${esc(match.away_name)}</strong></p>
    <p class="hint">${esc(match.tournament_name)} · ${esc(match.round_name ?? 'Ronde onbekend')} ·
      geplande start: ${match.scheduled_start ? esc(fmt(match.scheduled_start)) : 'Onbekend'}</p>
    <div class="notice">Gebruik deze functie alleen wanneer je via een betrouwbare livebron hebt
      vastgesteld dat de wedstrijd daadwerkelijk begonnen is.
      De wedstrijd krijgt status <strong>live</strong> en voorspellingen worden onmiddellijk
      gesloten. Zonder opgegeven exacte aanvang registreert Supabase het meldmoment als starttijd;
      dit is niet noodzakelijk het werkelijke aanvangsmoment.</div>
    <form id="start-form" class="stack">
      <div class="field">
        <label for="start-actual-time">Geverifieerde werkelijke starttijd (optioneel)</label>
        <input id="start-actual-time" type="datetime-local" step="60">
        <p class="hint">Laat dit veld leeg als je de exacte starttijd niet kent. Supabase registreert dan
          het moment van melden. Invoer in Nederlandse tijd
          (<span id="start-timezone"></span>). Gebruik alleen een door een betrouwbare bron bevestigde tijd.</p>
      </div>
      <label><input id="start-attested" type="checkbox" required>
        Ik heb via een betrouwbare bron vastgesteld dat deze wedstrijd begonnen is.</label>
      <p id="start-message" role="status"></p>
      <div class="row">
        <button type="submit" class="btn" id="start-submit">Start registreren</button>
        <button type="button" class="btn secondary" id="start-cancel">Annuleren</button>
      </div>
    </form>`;
  dialog.showModal();
  dialog.querySelector('#start-timezone').textContent =
    'Europe/Amsterdam';
  dialog.querySelector('#start-close').onclick = () => dialog.close();
  dialog.querySelector('#start-cancel').onclick = () => dialog.close();
  dialog.querySelector('#start-form').onsubmit = async event => {
    event.preventDefault();
    const message = dialog.querySelector('#start-message');
    const submit = dialog.querySelector('#start-submit');
    if (!dialog.querySelector('#start-attested').checked) {
      message.textContent = 'Bevestig eerst dat je de werkelijke start hebt vastgesteld.';
      return;
    }
    const enteredTime = dialog.querySelector('#start-actual-time').value;
    let verifiedStart = null;
    if (enteredTime) {
      const {dutchToUTC}=await import('./knockout.js?v=hub-20261017');let parsed;try{parsed=new Date(dutchToUTC(enteredTime));}catch(error){message.textContent=error.message;return;}
      if (!Number.isFinite(parsed.getTime()) || parsed.getTime() > Date.now()) {
        message.textContent = 'Vul een geldige werkelijke starttijd in die niet in de toekomst ligt.';
        return;
      }
      verifiedStart = parsed.toISOString();
    }
    const startDescription = verifiedStart
      ? `Geverifieerde werkelijke start: ${new Date(verifiedStart).toLocaleString('nl-NL',{timeZone:'Europe/Amsterdam'})} ` +
        `(Europe/Amsterdam).`
      : 'Exacte start onbekend; Supabase gebruikt het meldmoment.';
    if (!window.confirm(
      `Is ${match.home_name} – ${match.away_name} daadwerkelijk begonnen?\n` +
      `${startDescription}\nDeze actie sluit voorspellingen en kan niet via dit scherm ongedaan worden gemaakt.`
    )) return;
    submit.disabled = true;
    message.textContent = 'Wedstrijdstart registreren...';
    const { error } = await supabase.rpc('admin_record_match_start', {
      p_match_id: match.match_id,
      p_actual_start: verifiedStart
    });
    if (!dialog.isConnected) return;
    if (error) {
      console.error('Startregistratie:', error);
      message.textContent = `Registratie mislukt: ${error.message}`;
      submit.disabled = false;
      return;
    }
    dialog.close();
    await loadAdminMatches();
  };
}


// Toernooipublicatie: de backend controleert beheerdersrechten,
// compleetheid van de puntentelling, de status en auditregistratie.
// Deze handeling opent GEEN wedstrijden voor voorspellingen.
async function loadAdminTournamentPublications(force=false) {
  const target=document.getElementById('admin-tournament-publications');
  if(!target||!['admin','super_admin'].includes(currentRole))return;
  if(!force&&target.querySelector('[data-ko-dirty="true"]'))return;
  tournamentManagementController?.abort();tournamentManagementController=new AbortController();const managementSignal=tournamentManagementController.signal;
  const userId=currentUser.id;
  try{const {loadTournamentManagement}=await import('./tournament-management.js?v=crop-20261017');
    if(!target.isConnected||managementSignal.aborted)return;
    await loadTournamentManagement(target,{supabase,signal:managementSignal,isCurrent:()=>currentUser?.id===userId&&['admin','super_admin'].includes(currentRole),
      onSaved:()=>loadAdminMatches(),onEdit:(id,knockout)=>{showAdminSection(knockout?'schema':'matches');if(knockout)document.dispatchEvent(new CustomEvent('predict-knockout-select',{detail:id}));},
      onPublish:async t=>{if(!t.knockout){showPublishTournamentDialog(t);return;}
        if(!confirm('Publiceren vergrendelt de puntentelling en opent complete toekomstige wedstrijden. Doorgaan?'))return;
        const r=await supabase.rpc('edit_knockout',{p_tournament:t.id,p_action:'publish',p_match:null,p_values:{}});
        if(!target.isConnected)return;if(r.error){alert(r.error.message);return;}loadAdminTournamentPublications();loadAdminMatches();
      }});
  }catch(error){if(target.isConnected)target.textContent='Toernooibeheer laden mislukt: '+error.message;}
}

function showPublishTournamentDialog(tournament) {
  if (!tournament || tournament.status !== 'draft' ||
      !['admin','super_admin'].includes(currentRole)) return;
  const prior = document.getElementById('admin-publish-dialog');
  if (prior) prior.close();
  const dialog = document.createElement('dialog');
  dialog.id = 'admin-publish-dialog';
  dialog.setAttribute('aria-labelledby','publish-dialog-title');
  Object.assign(dialog.style, {
    width: 'min(540px, calc(100% - 32px))', maxHeight: '85vh',
    overflowY: 'auto', margin: 'auto', padding: '28px', borderRadius: '16px',
    border: '1px solid #cbd5e1',
    background: isDarkTheme() ? '#1e293b' : '#ffffff',
    color: isDarkTheme() ? '#ffffff' : '#111827'
  });
  document.body.appendChild(dialog);
  dialog.addEventListener('close', () => dialog.remove(), {once:true});
  dialog.innerHTML = `<div class="row" style="justify-content:space-between;align-items:center">
      <h2 id="publish-dialog-title">Toernooi publiceren</h2>
      <button type="button" class="btn secondary" id="publish-close" aria-label="Sluiten">✕</button>
    </div>
    <p><strong>${esc(tournament.name)}</strong></p>
    <p>Publicatie vergrendelt de puntentelling en wordt vastgelegd in het auditlog.
    Deze actie opent <strong>geen</strong> wedstrijden voor voorspellingen.</p>
    <p>Een nog onbevestigde wedstrijdstart blijft onbevestigd.</p>
    <form id="publish-form" class="stack">
      <label><input id="publish-confirm" type="checkbox" required>
        Ik bevestig dat de puntentelling voor dit toernooi definitief is.</label>
      <p id="publish-message" role="status"></p>
      <div class="row" style="gap:8px;flex-wrap:wrap">
        <button class="btn" type="submit">Publiceren en puntentelling vergrendelen</button>
        <button class="btn secondary" type="button" id="publish-cancel">Annuleren</button>
      </div>
    </form>`;
  dialog.showModal();
  dialog.querySelector('#publish-close').onclick = () => dialog.close();
  dialog.querySelector('#publish-cancel').onclick = () => dialog.close();
  dialog.querySelector('#publish-form').onsubmit = async event => {
    event.preventDefault();
    if (!dialog.querySelector('#publish-confirm').checked) return;
    if (!window.confirm(`Publiceer ${tournament.name} en vergrendel de puntentelling? Dit opent geen voorspellingen.`)) return;
    const submit = dialog.querySelector('button[type="submit"]');
    const message = dialog.querySelector('#publish-message');
    submit.disabled = true;
    message.textContent = 'Publicatie verwerken...';
    const { error } = await supabase.rpc('admin_publish_tournament', {
      p_tournament_id: tournament.id
    });
    if (!dialog.isConnected) return;
    if (error) {
      console.error('Publiceren:',error);
      message.textContent = `Publicatie mislukt: ${error.message}`;
      submit.disabled = false;
      return;
    }
    dialog.close();
    await loadAdminTournamentPublications();
  };
}


/*
 * PREDICT - Gecontroleerde QA-voorspelling
 * Gebruikt uitsluitend Supabase RPC en de RLS-regels.
 * De gewone lokale demonstratiegegevens blijven onaangetast.
 */
async function loadQaPredictionForm() {
  const target = document.getElementById('qa-prediction-panel');
  if (!target || !currentUser) return;
  target.textContent = 'QA-gegevens ophalen...';

  const { data: tours, error: tourError } =
    await supabase.rpc('admin_list_tournaments');
  if (!target.isConnected) return;
  if (tourError) {
    target.textContent = `Testtoernooi ophalen mislukt: ${tourError.message}`;
    return;
  }
  const qaTours = (tours ?? []).filter(t => t.name === 'Predict QA - dartstest');
  if (qaTours.length !== 1) {
    target.textContent = 'QA-testtoernooi ontbreekt of is niet uniek.';
    return;
  }
  const tournament = qaTours[0];
  if (tournament.status !== 'published' && tournament.status !== 'active') {
    target.textContent = 'QA-testtoernooi is nog niet gepubliceerd.';
    return;
  }

  const {data: allMatches, error: matchError} = await supabase.rpc(
    'admin_get_matches', {p_tournament_id: tournament.id}
  );
  if (!target.isConnected) return;
  if (matchError) {
    target.textContent = `Testwedstrijd ophalen mislukt: ${matchError.message}`;
    return;
  }
  const qaMatches = (allMatches ?? []).filter(m =>
    m.home_name === 'Testspeler A' &&
    m.away_name === 'Testspeler B'
  );
  if (qaMatches.length !== 1) {
    target.textContent = 'Er is niet precies één QA-testwedstrijd.';
    return;
  }
  const match = qaMatches[0];

  const {data: predictions, error: predictionError} = await supabase
    .from('match_predictions')
    .select('id,home_score,away_score,updated_at')
    .eq('match_id', match.match_id)
    .eq('user_id', currentUser.id)
    .limit(1);
  if (!target.isConnected) return;
  if (predictionError) {
    target.textContent =
      `Eigen voorspelling ophalen mislukt: ${predictionError.message}`;
    return;
  }
  const prediction = predictions?.[0] ?? null;
  const deadline = match.scheduled_start
    ? new Date(match.scheduled_start) : null;
  const allowed = match.predictions_enabled === true &&
    match.start_time_confirmed === true &&
    match.needs_review === false &&
    match.match_status === 'scheduled' &&
    match.actual_start == null &&
    deadline && Number.isFinite(deadline.getTime()) &&
    deadline > new Date();

  target.innerHTML = `
    <p class="muted mini">
      Alleen voor de fictieve QA-wedstrijd. Opslaan gebeurt echt in
      Supabase; geen lokale demovoorspelling.
    </p>
    <h3 style="margin:0">${esc(match.home_name)} – ${esc(match.away_name)}</h3>
    <p class="muted mini">
      ${esc(match.round_name ?? 'Testronde')} · Deadline:
      ${deadline ? esc(fmt(match.scheduled_start)) : 'Onbekend'} (Nederlandse tijd)
      · ${allowed ? 'Voorspellingen open' : 'Voorspellingen gesloten'}
    </p>
    <p>
      ${prediction
        ? `Huidige eigen voorspelling: <strong>${prediction.home_score}–${prediction.away_score}</strong>`
        : 'Nog geen voorspelling opgeslagen.'}
    </p>
    <form id="qa-prediction-form" class="stack">
      <div class="two">
        <div class="field">
          <label for="qa-home-score">${esc(match.home_name)} (legs)</label>
          <input id="qa-home-score" type="number" min="0" max="99" step="1"
            value="${prediction ? prediction.home_score : 6}"
            required ${allowed ? '' : 'disabled'}>
        </div>
        <div class="field">
          <label for="qa-away-score">${esc(match.away_name)} (legs)</label>
          <input id="qa-away-score" type="number" min="0" max="99" step="1"
            value="${prediction ? prediction.away_score : 3}"
            required ${allowed ? '' : 'disabled'}>
        </div>
      </div>
      <p class="hint">
        Best of 11 legs: precies één speler moet 6 legs hebben;
        de andere speler maximaal 5.
      </p>
      <p id="qa-prediction-feedback" role="status"></p>
      <div class="row" style="gap:8px;flex-wrap:wrap">
        <button class="btn" type="submit" ${allowed ? '' : 'disabled'}>
          ${prediction ? 'Voorspelling wijzigen' : 'Voorspelling indienen'}
        </button>
        <button class="btn secondary" type="button" id="qa-reload">
          Vernieuwen
        </button>
      </div>
    </form>
    <div id="qa-points-panel" class="notice" role="status">
      ${match.match_status === 'finished'
        ? 'Officiële testuitslag en punten ophalen...'
        : 'Punten verschijnen zodra de testwedstrijd is afgerond.'}
    </div>
  `;

  if (match.match_status === 'finished') {
    const pointsTarget = target.querySelector('#qa-points-panel');
    const { data: pointRows, error: pointsError } = await supabase.rpc(
      'get_my_match_points',
      { p_tournament_id: tournament.id }
    );
    if (!target.isConnected || !pointsTarget.isConnected) return;
    if (pointsError) {
      pointsTarget.textContent = `Punten ophalen mislukt: ${pointsError.message}`;
      console.error('QA-punten:', pointsError);
    } else {
      const forMatch = (pointRows ?? []).filter(row => row.match_id === match.match_id);
      if (forMatch.length !== 1) {
        pointsTarget.textContent = 'Geen unieke afgeronde voorspelling gevonden voor deze wedstrijd.';
      } else {
        const p = forMatch[0];
        pointsTarget.innerHTML = `
          <h3 style="margin:0 0 8px">Testresultaat uit Supabase</h3>
          <p>Voorspelling: <strong>${esc(p.predicted_home)}–${esc(p.predicted_away)}</strong></p>
          <p>Uitslag: <strong>${esc(p.actual_home)}–${esc(p.actual_away)}</strong></p>
          <p>Juiste winnaar: <strong>${p.correct_winner ? 'Ja' : 'Nee'}</strong> ·
             Exacte uitslag: <strong>${p.exact_score ? 'Ja' : 'Nee'}</strong></p>
          <p><strong>Behaalde punten: ${esc(p.earned_points)}</strong></p>
        `;
      }
    }
  }

  target.querySelector('#qa-reload').onclick = loadQaPredictionForm;
  target.querySelector('#qa-prediction-form').onsubmit = async event => {
    event.preventDefault();
    const a = Number(target.querySelector('#qa-home-score').value);
    const b = Number(target.querySelector('#qa-away-score').value);
    const feedback = target.querySelector('#qa-prediction-feedback');
    const button = target.querySelector('button[type="submit"]');

    if (!Number.isInteger(a) || !Number.isInteger(b) ||
        !((a === 6 && b >= 0 && b < 6) ||
          (b === 6 && a >= 0 && a < 6))) {
      feedback.textContent = 'Ongeldige legstand: één speler moet precies 6 legs winnen.';
      return;
    }
    button.disabled = true;
    feedback.textContent = 'Voorspelling naar Supabase versturen...';

    const {data: savedId, error} = await supabase.rpc(
      'submit_match_prediction',
      {p_match_id: match.match_id, p_home_score: a, p_away_score: b}
    );
    if (!target.isConnected) return;
    if (error) {
      feedback.textContent = `Opslaan geweigerd: ${error.message}`;
      button.disabled = false;
      console.error('QA voorspelling:', error);
      return;
    }
    feedback.textContent = `Opgeslagen in Supabase (ID: ${savedId}).`;
    await loadQaPredictionForm();
  };
}


/*
 * Klassementen zijn volledig serverberekend en omvatten alle officiële
 * afgeronde wedstrijden van een toernooi, ook bij later poulelidmaatschap.
 * Het filter op ronde of poule wordt eveneens op de server afgedwongen.
 */
async function loadAdminLeaderboards() {
  const panel = document.getElementById('admin-leaderboards');
  if (!panel || !currentUser) return;
  const {data: tournaments, error} = await supabase.rpc('admin_list_tournaments');
  if (!panel.isConnected) return;
  if (error) {
    panel.textContent = 'Toernooien ophalen mislukt: ' + error.message;
    return;
  }
  const list = (tournaments || []).filter(t => t.status !== 'draft');
  if (!list.length) {
    panel.textContent = 'Er zijn nog geen gepubliceerde toernooien.';
    return;
  }
  panel.innerHTML = `
    <p class="hint">Live uit Supabase. Punten worden per toernooi berekend; bij een
       gelijke stand telt het aantal juist voorspelde winnaars.</p>
    <div class="two">
      <div class="field"><label for="leaderboard-tournament">Toernooi</label>
        <select id="leaderboard-tournament">${list.map(t =>
          `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('')}</select>
      </div>
      <div class="field"><label for="leaderboard-pool">Poule</label>
        <select id="leaderboard-pool"><option value="">Alle deelnemers</option></select>
      </div>
      <div class="field"><label for="leaderboard-round">Ronde</label>
        <select id="leaderboard-round"><option value="">Alle rondes</option></select>
      </div>
    </div>
    <div id="leaderboard-results" class="table-wrap" role="status">Laden...</div>
    <button class="btn secondary" id="leaderboard-refresh" type="button">Vernieuwen</button>
  `;
  const tour = panel.querySelector('#leaderboard-tournament');
  const pool = panel.querySelector('#leaderboard-pool');
  const round = panel.querySelector('#leaderboard-round');
  const results = panel.querySelector('#leaderboard-results');
  let version = 0;

  async function refreshOptions() {
    const request = ++version;
    const tournamentId = tour.value;
    pool.innerHTML = '<option value="">Alle deelnemers</option>';
    round.innerHTML = '<option value="">Alle rondes</option>';
    results.textContent = 'Filters laden...';
    const [poolsResponse, roundsResponse] = await Promise.all([
      supabase.from('pools').select('id,name').eq('tournament_id', tournamentId).order('name'),
      supabase.rpc('admin_get_tournament_rounds', {p_tournament_id: tournamentId})
    ]);
    if (!panel.isConnected || request !== version) return;
    if (!poolsResponse.error) {
      for (const p of poolsResponse.data || []) {
        const option = document.createElement('option');
        option.value = p.id;
        option.textContent = p.name;
        pool.appendChild(option);
      }
    }
    if (!roundsResponse.error) {
      for (const r of roundsResponse.data || []) {
        const option = document.createElement('option');
        option.value = r.round_id;
        option.textContent = r.round_name;
        round.appendChild(option);
      }
    }
    await refreshRows();
  }

  async function refreshRows() {
    const request = ++version;
    results.textContent = 'Klassement laden...';
    const {data, error} = await supabase.rpc('get_tournament_leaderboard', {
      p_tournament_id: tour.value,
      p_pool_id: pool.value || null,
      p_round_id: round.value || null
    });
    if (!panel.isConnected || request !== version) return;
    if (error) {
      results.textContent = 'Klassement ophalen mislukt: ' + error.message;
      return;
    }
    const rows = data || [];
    results.innerHTML = rows.length
      ? `<table><thead><tr><th>#</th><th>Deelnemer</th><th class="num">Punten</th>
          <th class="num">Winnaars</th><th class="num">Exact</th></tr></thead>
          <tbody>${rows.map(r => `<tr><td>${r.rank_position}</td>
            <td>${esc(r.display_name)}</td>
            <td class="num"><strong>${r.earned_points}</strong></td>
            <td class="num">${r.correct_winners}</td>
            <td class="num">${r.exact_scores}</td></tr>`).join('')}</tbody></table>`
      : '<p class="hint">Nog geen deelnemers in dit klassement.</p>';
  }

  tour.onchange = refreshOptions;
  pool.onchange = refreshRows;
  round.onchange = refreshRows;
  panel.querySelector('#leaderboard-refresh').onclick = refreshRows;
  await refreshOptions();
}


async function loadPublicLeaderboard() {
  const target=document.getElementById('public-leaderboard');
  if (!target || !currentUser) return;
  const [entries,tours] = await Promise.all([
    supabase.from('tournament_entries').select('tournament_id').eq('user_id',currentUser.id),
    supabase.from('tournaments').select('id,name,status').neq('status','draft').order('name')
  ]);
  if (!target.isConnected) return;
  if (entries.error || tours.error) {
    target.textContent='Toernooien ophalen mislukt: '+(entries.error?.message||tours.error?.message);
    return;
  }
  const joined=new Set((entries.data||[]).map(e=>e.tournament_id));
  const isAdmin=['admin','super_admin'].includes(currentRole);
  const available=(tours.data||[]).filter(t=>isAdmin||joined.has(t.id));
  if (!available.length) {target.textContent='Nog geen toegankelijke toernooien.';return;}
  target.innerHTML='<label for="lb-tour">Toernooi</label><select id="lb-tour">'+available.map(t=>'<option value="'+esc(t.id)+'">'+esc(t.name)+'</option>').join('')+'</select><label for="lb-pool">Poule</label><select id="lb-pool"><option value="">Alle deelnemers</option></select><label for="lb-round">Ronde</label><select id="lb-round"><option value="">Alle rondes</option></select><div class="table-wrap" id="lb-data">Laden...</div><button class="btn secondary" id="lb-refresh" type="button">Vernieuwen</button>';
  const tour=target.querySelector('#lb-tour'),pool=target.querySelector('#lb-pool'),round=target.querySelector('#lb-round'),results=target.querySelector('#lb-data');
  let generation=0;
  async function loadRounds() {
    const g=++generation;
    round.innerHTML='<option value="">Alle rondes</option>';
    pool.innerHTML='<option value="">Alle deelnemers</option>';
    const [{data,error},poolResponse]=await Promise.all([
      supabase.from('tournament_rounds').select('id,name').eq('tournament_id',tour.value).order('round_order'),
      supabase.from('pools').select('id,name').eq('tournament_id',tour.value).order('name')
    ]);
    if (!target.isConnected||g!==generation)return;
    if (error||poolResponse.error) {results.textContent='Filters laden mislukt. Kies het toernooi opnieuw.';return;}
    (poolResponse.data||[]).forEach(p=>{const o=document.createElement('option');o.value=p.id;o.textContent=p.name;pool.add(o);});
    if (!error) (data||[]).forEach(r=>{const o=document.createElement('option');o.value=r.id;o.textContent=r.name;round.add(o);});
    await loadRows();
  }
  async function loadRows() {
    const g=++generation;
    results.textContent='Klassement laden...';
    const {data,error}=await supabase.rpc('get_tournament_leaderboard',{p_tournament_id:tour.value,p_pool_id:pool.value||null,p_round_id:round.value||null});
    if (!target.isConnected||g!==generation)return;
    if (error) {results.textContent='Klassement ophalen mislukt: '+error.message;return;}
    results.innerHTML=(data||[]).length?'<table><thead><tr><th>#</th><th>Gebruiker</th><th>Punten</th><th>Winnaars</th></tr></thead><tbody>'+(data||[]).map(r=>'<tr><td>'+r.rank_position+'</td><td>'+esc(r.display_name)+(r.user_id===currentUser.id?' (jij)':'')+'</td><td>'+r.earned_points+'</td><td>'+r.correct_winners+'</td></tr>').join('')+'</tbody></table>':'Nog geen deelnemers.';
  }
  tour.onchange=loadRounds;
  round.onchange=loadRows;
  pool.onchange=loadRows;
  target.querySelector('#lb-refresh').onclick=loadRows;
  await loadRounds();
}

// Online privépoules replace the old local-only demonstration on this tab.
pools = function () {
  return `<h1>Mijn privépoules</h1><p class="sub">Iedere poule hoort bij één toernooi.
    Je centrale voorspellingen tellen in iedere poule mee, ook als je later lid wordt.</p>
    <div id="private-pools" class="stack" role="region" aria-label="Privépoules">Poules laden...</div>`;
};
const renderBeforePrivatePools = render;
render = function () {
  renderBeforePrivatePools();
  if (currentUser && !state.tournament && state.tab === 'pools') {
    const badge = document.querySelector('.top .badge');
    if (badge) badge.textContent = 'ONLINE';
    const footer = document.querySelector('.footer');
    if (footer) footer.textContent = 'Predict · Privépoules en klassementen uit Supabase';
    loadPrivatePools();
  }
};

async function loadPrivatePools(host,tournamentId) {
  const target = host?.nodeType===1?host:document.getElementById('private-pools');
  if(target&&tournamentId)target.dataset.tournament=tournamentId;
  const scope=target?.dataset.tournament;
  if (!target || !currentUser) return;
  const userId = currentUser.id;
  const [memberships, poolResponse, tournamentsResponse] = await Promise.all([
    supabase.from('pool_members').select('pool_id').eq('user_id', userId),
    supabase.from('pools').select('id,name,tournament_id,owner_id').order('name'),
    supabase.from('tournaments').select('id,name,status').order('name')
  ]);
  if (!target.isConnected || currentUser?.id !== userId) return;
  const failure = memberships.error || poolResponse.error || tournamentsResponse.error;
  if (failure) {
    target.textContent = 'Poules laden mislukt: ' + failure.message;
    const retry = document.createElement('button'); retry.className = 'btn secondary';
    retry.textContent = 'Opnieuw proberen'; retry.onclick = ()=>loadPrivatePools(target); target.append(retry);
    return;
  }
  const ids = new Set((memberships.data || []).map(m => m.pool_id));
  const mine = (poolResponse.data || []).filter(p => ids.has(p.id)&&(!scope||p.tournament_id===scope));
  const tournamentsById = new Map((tournamentsResponse.data || []).map(t => [t.id, t]));
  const openTours = (tournamentsResponse.data || []).filter(t => ['published','active'].includes(t.status)&&(!scope||t.id===scope));
  target.innerHTML = `<p id="pool-message" role="status"></p>
    <div class="grid">${mine.length ? mine.map(p => `<article class="panel stack">
      <h2>${esc(p.name)}</h2><div class="muted">${esc(tournamentsById.get(p.tournament_id)?.name || 'Toernooi')}</div>
      <div>${p.owner_id === userId ? 'Jij beheert deze poule' : 'Pouledeelnemer'}</div>
      <button class="btn secondary" data-pool-detail="${esc(p.id)}">Leden en klassement</button>
    </article>`).join('') : '<p>Je bent nog geen lid van een privépoule.</p>'}</div>
    <form id="private-create-form" class="panel stack"><h2>Poule aanmaken</h2>
      <label for="private-pool-name">Poulenaam</label><input id="private-pool-name" required minlength="2" maxlength="80">
      <label for="private-pool-tournament" ${scope?'hidden':''}>Toernooi</label><select id="private-pool-tournament" required ${scope?'hidden':''}>
      ${openTours.map(t => `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('')}</select>
      <p class="hint">Je wordt automatisch deelnemer van het toernooi en beheerder van de poule.</p>
      <button class="btn" ${openTours.length ? '' : 'disabled'}>Poule aanmaken</button>
    </form>
    <form id="private-accept-form" class="panel stack"><h2>Uitnodiging accepteren</h2>
      <label for="private-invite-code">Uitnodigingscode</label><input id="private-invite-code" required pattern="[0-9a-f]{64}" maxlength="64" autocomplete="off" spellcheck="false">
      <p class="hint">Log in met het account waarvoor je bent uitgenodigd. Een code is zeven dagen geldig en eenmalig bruikbaar.</p>
      <button class="btn">Lid worden</button>
    </form><div id="private-pool-detail" class="stack"></div>`;
  const message = target.querySelector('#pool-message');
  async function submit(form, rpc, args) {
    const button = form.querySelector('button'); button.disabled = true; message.textContent = 'Bezig...';
    try {
      const {data,error} = await supabase.rpc(rpc, args);
      if (!target.isConnected || currentUser?.id !== userId) return;
      if (error) {message.textContent = error.message; return;}
      if(rpc==='accept_pool_invitation'&&scope&&data){
        const accepted=await supabase.from('pools').select('id,tournament_id').eq('id',data).single();
        if(!target.isConnected||currentUser?.id!==userId)return;
        if(!accepted.error&&accepted.data?.tournament_id&&accepted.data.tournament_id!==scope){
          const dirty=[...document.querySelectorAll('[data-online-predict] input')].some(i=>i.value!==i.defaultValue)||document.querySelector('[data-ko-dirty="true"]');
          if(dirty&&!confirm('Uitnodiging geaccepteerd. Niet-opgeslagen wijzigingen laten vervallen en het andere toernooi openen?')){await loadPrivatePools(target);target.querySelector('#pool-message').textContent='Uitnodiging geaccepteerd. Je poule staat bij het andere toernooi op de startpagina.';return;}
          onlineTournamentId=accepted.data.tournament_id;initialTournamentTab='pools';tournamentNotice='Uitnodiging geaccepteerd.';state.tab='home';render();return;
        }
      }
      if(scope&&target.dataset.joined==='false'){onlineTournamentId=scope;initialTournamentTab='pools';tournamentNotice=rpc==='create_pool'?'Poule aangemaakt. Je neemt nu ook deel aan dit toernooi.':'Uitnodiging geaccepteerd.';state.tab='home';render();return;}
      await loadPrivatePools(target);if(target.isConnected){const feedback=target.querySelector('#pool-message');if(feedback){feedback.textContent=rpc==='create_pool'?'Poule aangemaakt.':'Uitnodiging geaccepteerd.';feedback.className='success';}}
    } catch {if (target.isConnected) message.textContent = 'Verbinding mislukt. Probeer opnieuw.';}
    finally {if (button.isConnected) button.disabled = false;}
  }
  const create = target.querySelector('#private-create-form');
  create.onsubmit = event => {event.preventDefault(); submit(create,'create_pool', {
    p_tournament_id: target.querySelector('#private-pool-tournament').value,
    p_name: target.querySelector('#private-pool-name').value.trim()
  });};
  const accept = target.querySelector('#private-accept-form');
  accept.onsubmit = event => {event.preventDefault(); submit(accept,'accept_pool_invitation', {
    p_token: target.querySelector('#private-invite-code').value.trim()
  });};
  target.querySelectorAll('[data-pool-detail]').forEach(button => {
    button.onclick = () => loadPrivatePoolDetail(mine.find(p => p.id === button.dataset.poolDetail));
  });
}

async function loadPrivatePoolDetail(pool) {
  const host = document.getElementById('private-pool-detail');
  if (!pool || !host || !currentUser) return;
  // A new element invalidates outstanding requests from a previously selected pool.
  const target = document.createElement('div'); target.className = 'panel stack';
  const overview=host.parentElement;[...overview.children].forEach(x=>{if(x!==host){x.dataset.poolOverviewHidden='true';x.hidden=true;}});host.replaceChildren(target);host.scrollIntoView({block:'start'}); target.textContent = 'Leden en klassement laden...';
  try{
  const userId = currentUser.id;
  const owner = pool.owner_id === userId;
  const [members, rows, rounds] = await Promise.all([
    supabase.from('pool_members').select('user_id').eq('pool_id',pool.id),
    supabase.rpc('get_tournament_leaderboard',{p_tournament_id:pool.tournament_id,p_pool_id:pool.id,p_round_id:null}),
    supabase.from('tournament_rounds').select('id,name').eq('tournament_id',pool.tournament_id).order('round_order')
  ]);
  if (!target.isConnected || currentUser?.id !== userId) return;
  if (members.error || rows.error || rounds.error) {
    target.innerHTML='<button class="ghost" data-retry-back>← Mijn poules</button><p role="alert">Poule laden mislukt: '+esc((members.error || rows.error || rounds.error).message)+'</p>';target.querySelector('button').onclick=()=>loadPrivatePools(overview);return;
  }
  const names = new Map((rows.data || []).map(r => [r.user_id,r.display_name]));
  target.innerHTML = `<button class="ghost" id="private-detail-back">← Mijn poules</button><h2>${esc(pool.name)}</h2><p id="private-detail-message" role="status"></p>
    <h3>Leden (${members.data.length})</h3><ul>${members.data.map(m => `<li>
      <button class="name-link" data-compare-member="${esc(m.user_id)}">${esc(names.get(m.user_id) || 'Gebruiker')}</button>${m.user_id === pool.owner_id ? ' (beheerder)' : ''}
      ${owner && m.user_id !== userId ? `<button class="ghost" data-remove-member="${esc(m.user_id)}">Verwijderen</button>
        <button class="ghost" data-transfer-member="${esc(m.user_id)}">Beheer overdragen</button>` : ''}</li>`).join('')}</ul>
    <label for="private-pool-round">Klassement per ronde</label><select id="private-pool-round"><option value="">Alle rondes</option>
      ${rounds.data.map(r => `<option value="${esc(r.id)}">${esc(r.name)}</option>`).join('')}</select>
    <div id="private-pool-ranking" class="table-wrap" role="status"></div>
    ${owner ? `<form id="private-invite-form" class="stack"><h3>Lid uitnodigen</h3>
      <label for="private-invite-email">Gebruikersnaam van het lid</label><input id="private-invite-email" required maxlength="254" autocomplete="off">
      <button class="btn">Uitnodigingscode maken</button>
      <p class="hint">Deel de code zelf met de bedoelde ontvanger. Die heeft een bestaand Predict-account nodig.
      Een nieuwe code voor hetzelfde adres maakt de vorige ongeldig.</p>
      <div id="private-invite-result" role="status"></div></form>
      <button class="btn secondary" id="private-revoke">Alle openstaande uitnodigingen intrekken</button>` :
      '<button class="btn secondary" id="private-leave">Poule verlaten</button>'}`;
  target.querySelector('#private-detail-back').onclick=()=>loadPrivatePools(overview);
  const comparison=document.createElement('section');comparison.className='stack';target.append(comparison);
  const compare=member=>{import('./pool-comparison.js').then(({loadPoolComparison})=>{if(target.isConnected)loadPoolComparison(comparison,{supabase,isCurrent:()=>currentUser?.id===userId},pool,member,names.get(member)||'Poulegenoot');}).catch(()=>comparison.textContent='Vergelijken laden mislukt. Probeer opnieuw.');};
  const message = target.querySelector('#private-detail-message');
  const ranking = target.querySelector('#private-pool-ranking');
  function showRanking(data) {
    ranking.innerHTML = data.length ? `<table><thead><tr><th>#</th><th>Gebruiker</th><th>Punten</th><th>Winnaars</th></tr></thead>
      <tbody>${data.map(r => `<tr><td>${esc(r.rank_position)}</td><td><button class="name-link" data-compare-member="${esc(r.user_id)}">${esc(r.display_name)}${r.user_id === userId ? ' (jij)' : ''}</button></td>
        <td>${esc(r.earned_points)}</td><td>${esc(r.correct_winners)}</td></tr>`).join('')}</tbody></table>` : 'Nog geen deelnemers.';
  }
  const bindComparisons=()=>target.querySelectorAll('[data-compare-member]').forEach(b=>b.onclick=()=>compare(b.dataset.compareMember));
  showRanking(rows.data || []);bindComparisons();
  let generation = 0;
  target.querySelector('#private-pool-round').onchange = async event => {
    const g = ++generation; ranking.textContent = 'Klassement laden...';
    const {data,error} = await supabase.rpc('get_tournament_leaderboard',{
      p_tournament_id:pool.tournament_id,p_pool_id:pool.id,p_round_id:event.target.value || null
    });
    if (!target.isConnected || g !== generation) return;
    if (error) ranking.textContent = error.message; else {showRanking(data || []);bindComparisons();}
  };
  async function manage(action, member, button) {
    if (!confirm(action === 'transfer' ? 'Poulebeheer overdragen aan dit lid?' :
      action === 'remove' ? 'Dit lid uit de poule verwijderen?' :
      action === 'revoke' ? 'Alle openstaande uitnodigingen intrekken?' : 'Deze poule verlaten?')) return;
    button.disabled = true;
    try {
      const {error} = await supabase.rpc('manage_pool_member',{p_pool_id:pool.id,p_user_id:member,p_action:action});
      if (!target.isConnected) return;
      if (error) message.textContent = error.message; else await loadPrivatePools(overview);
    } catch {if (target.isConnected) message.textContent = 'Verbinding mislukt. Probeer opnieuw.';}
    finally {if (button.isConnected) button.disabled = false;}
  }
  target.querySelectorAll('[data-remove-member]').forEach(b => b.onclick = () => manage('remove',b.dataset.removeMember,b));
  target.querySelectorAll('[data-transfer-member]').forEach(b => b.onclick = () => manage('transfer',b.dataset.transferMember,b));
  const leave = target.querySelector('#private-leave'); if (leave) leave.onclick = () => manage('leave',null,leave);
  const revoke = target.querySelector('#private-revoke'); if (revoke) revoke.onclick = () => manage('revoke',null,revoke);
  const invite = target.querySelector('#private-invite-form');
  if (invite) invite.onsubmit = async event => {
    event.preventDefault(); const button = invite.querySelector('button'); button.disabled = true;
    const result = target.querySelector('#private-invite-result'); result.textContent = 'Code maken...';
    try {
      const {data,error} = await supabase.rpc('invite_pool_member',{
        p_pool_id:pool.id,p_email:target.querySelector('#private-invite-email').value.trim()
      });
      if (!target.isConnected) return;
      if (error) {result.textContent = error.message; return;}
      result.innerHTML = '<label for="private-created-code">Kopieer deze eenmalige code voor de ontvanger</label><input id="private-created-code" readonly autocomplete="off"><p class="hint">Deze code wordt alleen nu getoond en niet op dit apparaat opgeslagen.</p>';
      result.querySelector('input').value = data;
      result.querySelector('input').onclick = event => event.target.select();
    } catch {if (target.isConnected) result.textContent = 'Verbinding mislukt. Probeer opnieuw.';}
    finally {if (button.isConnected) button.disabled = false;}
  };
  }catch(error){if(target.isConnected){target.innerHTML='<button class="ghost">← Mijn poules</button><p role="alert"></p>';target.querySelector('p').textContent='Poule laden mislukt: '+error.message;target.querySelector('button').onclick=()=>loadPrivatePools(overview);}}
}

// Replace the remaining tournament demo routes with authenticated online screens.
// Obsolete local demo IDs must never select an online tournament or prediction.
state.tournament = null;
let onlineTournamentId = null;let initialTournamentTab='predictions',tournamentNotice='';
let onlineScreenController = null;
home = discover = function () {return '<section id="online-tournaments" class="stack" aria-label="Toernooien">Toernooien laden...</section>';};
const renderBeforeOnlineTournaments = render;
render = function () {
  onlineScreenController?.abort();
  renderBeforeOnlineTournaments();
  if (!currentUser) {onlineTournamentId=null;return;}
  document.querySelectorAll('.top [data-tab]').forEach(button=>{
    const navigate=button.onclick;
    button.onclick=event=>{
      const dirty=[...document.querySelectorAll('[data-online-predict] input')].some(i=>i.value!==i.defaultValue)||
        document.querySelector('[data-profile-form][data-dirty="true"]')||document.querySelector('[data-ko-dirty="true"]')||[...document.querySelectorAll('#private-pools form input:not([readonly]):not([type=hidden])')].some(i=>i.value!==i.defaultValue);
      if(dirty&&!confirm('Niet-opgeslagen wijzigingen laten vervallen?'))return;
      onlineTournamentId=null;navigate(event);
    };
  });
  if (state.tab !== 'profile') {
    const badge=document.querySelector('.top .badge');if(badge)badge.textContent='ONLINE';
    const footer=document.querySelector('.footer');if(footer)footer.textContent='Predict · Toernooien, voorspellingen en poules uit Supabase';
  }
  const target=document.getElementById('online-tournaments');
  if (!target) return;
  onlineScreenController=new AbortController();
  const userId=currentUser.id;
  const ctx={supabase,userId,signal:onlineScreenController.signal,isCurrent:()=>currentUser?.id===userId,
    mode:state.tab,tournamentId:onlineTournamentId,
    onOpen:id=>{onlineTournamentId=id;initialTournamentTab='predictions';render();},
    onBack:()=>{onlineTournamentId=null;render();},onPools:(panel,joined)=>{panel.dataset.joined=String(joined);return loadPrivatePools(panel,onlineTournamentId);}};
  if (onlineTournamentId) {loadTournamentDetail(target,ctx,0,tournamentNotice,{tab:initialTournamentTab,round:''});tournamentNotice='';}
  else loadTournamentCatalog(target,ctx);
};

profile=function(){return '<section id="online-profile" class="stack" aria-label="Account">Account laden...</section><section class="panel stack account-session"><h2>Sessie</h2><button type="button" class="ghost" id="account-logout">Uitloggen</button><p id="account-logout-message" role="status"></p></section>';};
let profileScreenController=null;
const renderBeforeOnlineProfile=render;
render=function(){
  profileScreenController?.abort();renderBeforeOnlineProfile();
  if(!currentUser){currentProfile=null;return;}
  const badge=document.querySelector('.top .badge');if(badge)badge.textContent='ONLINE';
  const footer=document.querySelector('.footer');if(footer)footer.textContent='Predict · Je account, voorspellingen en poules uit Supabase';
  const userId=currentUser.id;
  applyTheme();
  const target=document.getElementById('online-profile');if(!target)return;
  const logout=document.getElementById('account-logout');
  logout.onclick=async()=>{
    const message=document.getElementById('account-logout-message');logout.disabled=true;message.textContent='Uitloggen…';
    try{
      const {error}=await supabase.auth.signOut();if(error)throw error;
      if(currentUser?.id!==userId)return;
      currentUser=null;currentProfile=null;currentRole='user';render();
    }catch(error){if(logout.isConnected&&currentUser?.id===userId){message.textContent='Uitloggen mislukt. Probeer opnieuw.';message.setAttribute('role','alert');}}
    finally{if(logout.isConnected)logout.disabled=false;}
  };
  profileScreenController=new AbortController();
  const revision=profileRevision;
  loadOnlineProfile(target,{supabase,userId,signal:profileScreenController.signal,isCurrent:()=>currentUser?.id===userId,
    save:persistProfile,onLoaded:data=>{if(profileRevision===revision)applyAccountProfile(data);return currentProfile;}});
};

const renderBeforeAccountInvitations=render;
render=function(){
  renderBeforeAccountInvitations();
  if(!currentUser||!['admin','super_admin'].includes(currentRole)||state.tab!=='admin')return;
  const panel=document.createElement('section');panel.className='panel stack';panel.id='account-invitations';
  panel.innerHTML='<h2>Accounts en herstelcodes</h2><p>Deel een eenmalige link rechtstreeks met de juiste persoon. Activatie is zeven dagen geldig, wachtwoordherstel één uur. De gebruiker kiest zelf een wachtwoord; er wordt geen e-mail verstuurd.</p><form class="stack"><label for="account-invite-username">Gebruikersnaam voor accountbeheer</label><input id="account-invite-username" autocomplete="off" maxlength="128" required spellcheck="false"><button class="btn" value="activate">Account uitnodigen</button><button class="ghost" value="reset">Herstelcode maken</button><button class="ghost" type="button" id="revoke-account-invite">Openstaande codes intrekken</button></form><p id="account-invite-message" role="status"></p><div id="account-invite-result"></div>';
  document.querySelector('.nav')?.after(panel);
  const form=panel.querySelector('form'),username=panel.querySelector('input'),message=panel.querySelector('#account-invite-message'),result=panel.querySelector('#account-invite-result');
  async function submit(kind){
    if(!form.reportValidity())return;
    const userId=currentUser.id;form.querySelectorAll('button').forEach(b=>b.disabled=true);message.textContent='';result.textContent='';
    try{
      const revoke=kind==='revoke';
      const args={p_username:username.value.trim(),...(!revoke?{p_kind:kind}:{})};
      const response=await supabase.rpc(revoke?'revoke_manual_account_codes':'issue_manual_account_code',args);
      if(!panel.isConnected||currentUser?.id!==userId)return;
      if(response.error)throw response.error;
      if(revoke){message.textContent='Openstaande codes ingetrokken. Een code die al wordt verwerkt kan niet meer worden ingetrokken.';return;}
      const link=new URL('./account.html',location.href);link.hash=new URLSearchParams({kind,username:username.value.trim().toLowerCase(),code:response.data}).toString();
      const label=document.createElement('label');label.textContent='Kopieer deze eenmalige link voor de ontvanger';
      const output=document.createElement('input');output.readOnly=true;output.autocomplete='off';output.value=link.href;output.setAttribute('aria-label','Accountlink');output.onclick=()=>output.select();
      result.append(label,output);message.textContent='Code aangemaakt. De link wordt alleen nu getoond.';
    }catch(error){if(panel.isConnected&&currentUser?.id===userId)message.textContent=error.message||'Verbinding mislukt. Probeer opnieuw.';}
    finally{if(panel.isConnected)form.querySelectorAll('button').forEach(b=>b.disabled=false);}
  }
  form.onsubmit=e=>{e.preventDefault();submit(e.submitter?.value||'activate');};
  panel.querySelector('#revoke-account-invite').onclick=()=>submit('revoke');
};

let knockoutScreenController=null;
const renderBeforeKnockout=render;
render=function(){
  knockoutScreenController?.abort();renderBeforeKnockout();
  if(!currentUser||!['admin','super_admin'].includes(currentRole)||state.tab!=='admin')return;
  const target=document.createElement('section');target.id='admin-knockout';target.className='panel stack';
  document.querySelector('#account-invitations')?.after(target);
  knockoutScreenController=new AbortController();const signal=knockoutScreenController.signal,userId=currentUser.id;
  import('./knockout.js?v=hub-20261017').then(({loadKnockoutAdmin})=>{
    if(!signal.aborted&&target.isConnected)loadKnockoutAdmin(target,{supabase,signal,isCurrent:()=>currentUser?.id===userId,onSaved:()=>{loadAdminMatches();loadAdminTournamentPublications();}});
  }).catch(()=>{if(!signal.aborted&&target.isConnected)target.textContent='Knock-outbeheer laden mislukt. Open Beheer opnieuw.';});
};

let tournamentManagementController=null;
let selectedAdminSection='tournaments';
function showAdminSection(id){
 selectedAdminSection=id;
 document.querySelectorAll('[data-admin-panel]').forEach(panel=>panel.hidden=panel.dataset.adminPanel!==id);
 document.querySelectorAll('[data-admin-section]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.adminSection===id)));
}
const renderBeforeAdminNavigation=render;
render=function(){
 tournamentManagementController?.abort();renderBeforeAdminNavigation();if(!currentUser||!['admin','super_admin'].includes(currentRole)||state.tab!=='admin')return;
 const publication=document.getElementById('admin-tournament-publications'),old=publication?.closest('section');if(!old)return;
 const shell=document.createElement('section');shell.className='admin-shell stack';shell.innerHTML='<h1>Beheer</h1><nav class="admin-subnav" aria-label="Beheeronderdelen"></nav>';
 document.querySelector('.nav')?.after(shell);
 const nav=shell.querySelector('nav');
 const appearance=document.createElement('section');appearance.id='app-appearance';appearance.className='panel stack';loadAppearanceSettings(appearance);
 const groups=[['settings','Instellingen',appearance],['tournaments','Toernooien',publication],['schema','Schema’s',document.getElementById('admin-knockout')],['matches','Wedstrijden',document.getElementById('admin-matches')?.closest('.panel')],['accounts','Accounts',document.getElementById('account-invitations')],['rankings','Klassementen',document.getElementById('admin-leaderboards')],['qa','Testomgeving',document.getElementById('qa-prediction-panel')]];
 groups.forEach(([id,label,content])=>{if(!content)return;const panel=document.createElement('section');panel.dataset.adminPanel=id;panel.className='stack';panel.setAttribute('aria-label',label);const button=document.createElement('button');button.type='button';button.textContent=label;button.dataset.adminSection=id;button.onclick=()=>showAdminSection(id);nav.append(button);if(id==='matches'){const refresh=document.getElementById('admin-refresh');if(refresh)panel.append(refresh);}panel.append(content);shell.append(panel);});
 old.remove();showAdminSection(selectedAdminSection);
};

const renderBeforeHeaderNavigation=render;
render=function(){renderBeforeHeaderNavigation();if(currentUser)document.querySelectorAll('.nav').forEach(el=>el.remove());};

readAppAppearance().catch(()=>{});
