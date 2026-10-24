import {loadingScreen} from './loading-screen.js?v=loading-ui-20261024';
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const active=(target,ctx)=>target.isConnected&&!ctx.signal.aborted&&ctx.isCurrent();


export async function loadOnlineProfile(target,ctx){
  target.innerHTML=loadingScreen();
  try {
    target.classList.add('account-settings');
    const profile=await ctx.supabase.from('profiles').select('username,display_name,theme').eq('id',ctx.userId).single();
    if(!active(target,ctx))return;
    if(profile.error||!profile.data)throw new Error(profile.error?.message||'Eigen profiel niet gevonden.');
    const p=ctx.onLoaded(profile.data)||profile.data;
    target.innerHTML=`<h1>Account</h1>
      <form class="panel stack" data-profile-form data-dirty="false">
        <div class="muted mini">Gebruikersnaam: ${esc(p.username)}</div>
        <div class="field"><label for="account-display-name">Weergavenaam</label>
          <input id="account-display-name" required maxlength="40" value="${esc(p.display_name||p.username)}" autocomplete="nickname"></div>
        <div class="field"><label for="account-theme">Thema</label><select id="account-theme">
          ${[['system','Systeeminstelling'],['light','Licht'],['dark','Donker']].map(([v,label])=>`<option value="${v}" ${p.theme===v?'selected':''}>${label}</option>`).join('')}</select></div>

        <p role="status" id="account-profile-message"></p><button class="btn">Account opslaan</button>
      </form><section class="panel stack" data-push-settings aria-label="Telefoonmeldingen"></section>`;
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
  } catch(error){
    if(!active(target,ctx))return;
    target.innerHTML='<h1>Account</h1><p role="alert"></p><button class="btn secondary">Opnieuw proberen</button>';
    target.querySelector('p').textContent='Account laden mislukt: '+error.message;
    target.querySelector('button').onclick=()=>loadOnlineProfile(target,ctx);
  }
}
