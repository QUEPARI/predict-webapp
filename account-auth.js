// Capture and erase credentials before loading third-party code. Keep only in memory.
const query = new URLSearchParams(location.search);
let credentials = new URLSearchParams(location.hash.slice(1));
if (query.has('token_hash')) credentials = query;
history.replaceState(null, '', location.pathname);
const {createClient} = await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/+esm');
const client = createClient('https://sfcozzjcuppfypetbbzn.supabase.co','sb_publishable_1opRVzunD94Sd71rKSJAew_0ydMP2VU',{
  auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}
});
const target=document.getElementById('account-flow'), message=document.getElementById('message');
const title=document.getElementById('title');
const type=credentials.get('type');
const invite=credentials.get('invite');
const callback=new URL('./account.html',location.href).href;
let verified=false, saving=false;
function form(html){target.innerHTML='<form class="stack">'+html+'</form>';return target.querySelector('form');}
function passwordForm(){
  title.textContent=type==='invite'?'Kies je wachtwoord':'Nieuw wachtwoord';
  const f=form('<label for="password">Wachtwoord (minimaal 12 tekens)</label><input id="password" type="password" autocomplete="new-password" minlength="12" maxlength="128" required><label for="repeat">Herhaal wachtwoord</label><input id="repeat" type="password" autocomplete="new-password" minlength="12" maxlength="128" required><button class="btn">Wachtwoord opslaan</button>');
  f.onsubmit=async e=>{
    e.preventDefault();if(!verified||saving)return;
    const password=f.querySelector('#password'), repeat=f.querySelector('#repeat'),button=f.querySelector('button');
    if(password.value!==repeat.value){message.textContent='De wachtwoorden zijn niet gelijk.';return;}
    saving=true;button.disabled=true;message.textContent='';
    try{
      const {data,error}=await client.auth.getUser();if(error||!data.user)throw Error();
      // The database independently verifies the confirmed address and live invitation.
      if(type==='invite') {const r=await client.rpc('complete_account_invitation');if(r.error)throw Error();}
      const update=await client.auth.updateUser({password:password.value});if(update.error)throw Error();
      password.value='';repeat.value='';verified=false;
      // Revoke refresh sessions, including older sessions, before returning to login.
      const signedOut=await client.auth.signOut({scope:'global'});
      target.textContent='';title.textContent='Wachtwoord opgeslagen';
      message.textContent=signedOut.error?'Je wachtwoord is opgeslagen. Uitloggen van andere sessies is niet bevestigd. Log opnieuw in.':'Je wachtwoord is opgeslagen. Log opnieuw in met je nieuwe wachtwoord.';
    }catch{message.textContent='Opslaan mislukt. Controleer of je uitnodiging nog geldig is of vraag een nieuwe herstelmail aan.';}
    finally{saving=false;if(button.isConnected)button.disabled=false;}
  };
}
if(invite && /^[0-9a-f]{64}$/.test(invite)){
  title.textContent='Predict-uitnodiging';
  const f=form('<p>Bevestig het uitgenodigde e-mailadres. Je ontvangt een e-mail om je account te activeren. De uitnodiging is zeven dagen geldig.</p><label for="email">E-mailadres</label><input id="email" type="email" autocomplete="email" maxlength="254" required><button class="btn">Activatiemail aanvragen</button>');
  f.onsubmit=async e=>{
    e.preventDefault();const b=f.querySelector('button');b.disabled=true;
    try{
      const result=await client.functions.invoke('activate-account-invitation',{body:{token:invite,email:f.querySelector('input').value.trim()}});
      if(result.error)throw Error();
      message.textContent='Als de uitnodiging geldig is, ontvang je een activatiemail. Controleer ook je spammap. Probeer na een minuut opnieuw als de mail uitblijft.';
    }catch{message.textContent='Aanvragen mislukt. Probeer later opnieuw.';}
    finally{b.disabled=false;}
  };
}else if(['invite','recovery'].includes(type)&&(credentials.has('token_hash')||(credentials.has('access_token')&&credentials.has('refresh_token')))){
  target.innerHTML='<p>Bevestig dat je wilt doorgaan met deze accountlink.</p><button class="btn" id="verify">Doorgaan</button>';
  document.getElementById('verify').onclick=async e=>{
    e.target.disabled=true;message.textContent='';
    try{
      const r=credentials.has('token_hash')?await client.auth.verifyOtp({token_hash:credentials.get('token_hash'),type}):
        await client.auth.setSession({access_token:credentials.get('access_token'),refresh_token:credentials.get('refresh_token')});
      credentials=new URLSearchParams();
      if(r.error)throw Error();
      const check=await client.auth.getUser();if(check.error||!check.data.user?.email_confirmed_at)throw Error();
      verified=true;passwordForm();
    }catch{credentials=new URLSearchParams();target.textContent='';message.textContent='Deze link is ongeldig, verlopen of al gebruikt. Vraag een nieuwe uitnodiging of herstelmail aan.';}
  };
}else if(credentials.size){
  credentials=new URLSearchParams();title.textContent='Accountlink ongeldig';
  target.textContent='Deze link is ongeldig, verlopen of al gebruikt. Vraag een nieuwe uitnodiging of open wachtwoordherstel via de inlogpagina.';
}else{
  credentials=new URLSearchParams();title.textContent='Wachtwoord vergeten';
  const f=form('<p>Vul je accountadres in voor een herstelmail.</p><label for="email">E-mailadres</label><input id="email" type="email" autocomplete="email" maxlength="254" required><button class="btn">Herstelmail aanvragen</button>');
  f.onsubmit=async e=>{
    e.preventDefault();const b=f.querySelector('button');b.disabled=true;
    try{
      // Keep account existence and server errors private. Supabase enforces server rate limits.
      await client.auth.resetPasswordForEmail(f.querySelector('input').value.trim(),{redirectTo:callback});
      message.textContent='Als dit adres een account heeft, ontvang je een herstelmail. Controleer ook je spammap.';
    }catch{message.textContent='Verbinding mislukt. Probeer later opnieuw.';b.disabled=false;}
  };
}
