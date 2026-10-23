// Invite only an explicitly selected account; never submit free text as a username.
export function bindPoolInvite(form,{supabase,poolId,isCurrent=()=>true}) {
 const input=form.querySelector('input'),list=form.querySelector('[data-user-suggestions]'),send=form.querySelector('[type=submit]'),status=form.querySelector('[role=status]');
 let selected=null,revision=0,timer,busy=false,users=[],active=-1;
 const valid=()=>form.isConnected&&isCurrent();
 list.id=(input.id||'pool-user-'+poolId)+'-options';list.setAttribute('role','listbox');list.setAttribute('aria-label','Gevonden gebruikers');
 input.setAttribute('role','combobox');input.setAttribute('aria-autocomplete','list');input.setAttribute('aria-controls',list.id);input.setAttribute('aria-expanded','false');
 const close=()=>{list.hidden=true;input.setAttribute('aria-expanded','false');input.removeAttribute('aria-activedescendant');active=-1;};
 const highlight=index=>{active=index;[...list.children].forEach((el,i)=>el.setAttribute('aria-selected',String(i===active)));if(active>=0)input.setAttribute('aria-activedescendant',list.children[active].id);else input.removeAttribute('aria-activedescendant');};
 const choose=user=>{if(busy)return;selected=user;revision++;clearTimeout(timer);input.value=user.username;close();list.replaceChildren();users=[];status.textContent=`Geselecteerd: ${user.username}`;send.disabled=false;};
 const show=()=>{if(!users.length||selected)return;list.hidden=false;input.setAttribute('aria-expanded','true');highlight(-1);};
 const search=()=>{
  if(busy)return;
  clearTimeout(timer);const version=++revision;selected=null;send.disabled=true;users=[];list.replaceChildren();close();
  const query=input.value.trim();status.textContent=query.length<3?'Typ minimaal 3 letters en selecteer een gebruiker.':'Gebruikers zoeken…';
  if(query.length<3)return;
  timer=setTimeout(async()=>{
   if(!valid()||version!==revision)return;
   try{
    const r=await supabase.rpc('search_pool_users',{p_pool_id:poolId,p_query:query});
    if(!valid()||version!==revision)return;if(r.error)throw r.error;
    users=(r.data||[]).slice(0,3);status.textContent=users.length?'Selecteer de gebruiker die je wilt uitnodigen.':'Geen beschikbare gebruikers gevonden.';
    users.forEach((user,index)=>{const option=document.createElement('button');option.type='button';option.tabIndex=-1;option.id=list.id+'-'+index;option.setAttribute('role','option');option.setAttribute('aria-selected','false');option.textContent=user.username;option.dataset.suggestedUser=user.user_id;option.onpointerdown=event=>event.preventDefault();option.onpointermove=()=>highlight(index);option.onclick=()=>choose(user);list.append(option);});
    if(document.activeElement===input)show();
   }catch(error){if(valid()&&version===revision){close();status.textContent=error.message||'Zoeken mislukt. Probeer opnieuw.';}}
  },250);
 };
 input.oninput=search;
 input.onfocus=()=>{if(users.length&&!selected)show();else if(!selected&&input.value.trim().length>=3)search();};
 input.onkeydown=event=>{
  if(['ArrowDown','ArrowUp'].includes(event.key)&&users.length&&!selected){event.preventDefault();if(list.hidden)show();const next=event.key==='ArrowDown'?(active+1)%users.length:active<0?users.length-1:(active+users.length-1)%users.length;highlight(next);}
  else if(event.key==='Enter'&&!list.hidden&&users.length){event.preventDefault();choose(users[active<0?0:active]);}
  else if(event.key==='Enter'&&!selected){event.preventDefault();status.textContent='Selecteer eerst een gebruiker uit de lijst.';}
  else if(event.key==='Escape'){event.preventDefault();revision++;clearTimeout(timer);close();}
  else if(event.key==='Tab')close();
 };
 input.onblur=()=>{revision++;clearTimeout(timer);close();};
 form.onsubmit=async event=>{
  event.preventDefault();if(!selected||selected.username!==input.value||busy)return;
  const user=selected;busy=true;revision++;clearTimeout(timer);close();input.disabled=true;send.disabled=true;status.textContent='Uitnodiging versturen…';
  try{
   const r=await supabase.rpc('send_pool_invitation',{p_pool_id:poolId,p_user_id:user.user_id});
   if(!valid())return;if(r.error)throw r.error;
   selected=null;input.value='';users=[];list.replaceChildren();status.textContent=`${user.username} is uitgenodigd. De uitnodiging staat bij Spel > Poules.`;
  }catch(error){if(valid())status.textContent=error.message||'Versturen mislukt. Probeer opnieuw.';}
  finally{busy=false;if(valid()){input.disabled=false;send.disabled=!selected;}}
 };
}
