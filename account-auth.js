// Codes stay in the fragment/in memory and are erased before importing the SDK.
const parameters=new URLSearchParams(location.hash.slice(1));
history.replaceState(null,'',location.pathname);
const initialKind=parameters.get('kind')==='activate'?'activate':'reset';
const initialCode=parameters.get('code')||'';
const initialUsername=parameters.get('username')||'';
const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/+esm');
const client=createClient('https://sfcozzjcuppfypetbbzn.supabase.co','sb_publishable_1opRVzunD94Sd71rKSJAew_0ydMP2VU',{
  auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}
});
// Public branding is independent of the isolated, non-persistent account session.
import('./branding.js?v=cards-20261017').then(async({applyAccent})=>{if(!client.rpc)return;const r=await client.rpc('get_app_appearance');if(!r.error)applyAccent(r.data?.accent??null);}).catch(()=>{});
const target=document.getElementById('account-flow'),message=document.getElementById('message'),title=document.getElementById('title');
title.textContent=initialKind==='activate'?'Account activeren':'Wachtwoord herstellen';
target.innerHTML='<p>Gebruik de eenmalige code van je beheerder. Je kiest zelf je wachtwoord. Er wordt geen e-mail verstuurd.</p><form class="stack"><label for="kind">Wat wil je doen?</label><select id="kind"><option value="activate">Nieuw account activeren</option><option value="reset">Wachtwoord herstellen</option></select><label for="username">Gebruikersnaam</label><input id="username" autocomplete="username" maxlength="128" required spellcheck="false"><label for="code">Eenmalige code</label><input id="code" autocomplete="off" pattern="[0-9a-f]{64}" maxlength="64" required spellcheck="false"><label for="password">Wachtwoord (minimaal 12 tekens)</label><input id="password" type="password" autocomplete="new-password" minlength="12" maxlength="128" required><label for="repeat">Herhaal wachtwoord</label><input id="repeat" type="password" autocomplete="new-password" minlength="12" maxlength="128" required><button class="btn">Wachtwoord opslaan</button></form>';
const form=target.querySelector('form');
form.querySelector('#kind').value=initialKind;
form.querySelector('#username').value=initialUsername;
form.querySelector('#code').value=initialCode;
form.querySelector('#kind').onchange=e=>{title.textContent=e.target.value==='activate'?'Account activeren':'Wachtwoord herstellen';};
let saving=false;
form.onsubmit=async e=>{
  e.preventDefault();if(saving)return;
  const password=form.querySelector('#password'),repeat=form.querySelector('#repeat');
  if(password.value!==repeat.value){message.textContent='De wachtwoorden zijn niet gelijk.';return;}
  const body={kind:form.querySelector('#kind').value,username:form.querySelector('#username').value.trim(),code:form.querySelector('#code').value.trim(),password:password.value};
  saving=true;form.querySelectorAll('input,select,button').forEach(x=>x.disabled=true);message.textContent='';
  try{
    const r=await client.functions.invoke('manual-account',{body});if(r.error||!r.data?.success)throw Error();
    form.reset();target.textContent='';title.textContent='Wachtwoord opgeslagen';
    message.textContent='Je kunt nu inloggen met je gebruikersnaam en nieuwe wachtwoord.';
  }catch{message.textContent='Opslaan mislukt. Controleer je gebruikersnaam en code. Is de code verlopen of al gebruikt? Vraag dan een nieuwe code aan je beheerder.';}
  finally{body.password='';saving=false;form.querySelectorAll('input,select,button').forEach(x=>x.disabled=false);}
};
