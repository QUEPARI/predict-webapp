// Only IDs selected from the server's search results can be invited.
export function bindPoolInvite(form,{supabase,poolId,isCurrent=()=>true}) {
 const input=form.querySelector('input'),list=form.querySelector('[data-user-suggestions]'),send=form.querySelector('[type=submit]'),status=form.querySelector('[role=status]');
 let selected=null,revision=0,timer,busy=false;
 const valid=()=>form.isConnected&&isCurrent();
 input.oninput=()=>{
  clearTimeout(timer);const version=++revision;selected=null;send.disabled=true;list.replaceChildren();
  const query=input.value.trim();status.textContent=query.length<3?'Typ minimaal 3 letters en selecteer een gebruiker.':'Gebruikers zoeken…';
  if(query.length<3)return;
  timer=setTimeout(async()=>{
   try {
    const r=await supabase.rpc('search_pool_users',{p_pool_id:poolId,p_query:query});
    if(!valid()||version!==revision)return;if(r.error)throw r.error;
    const users=(r.data||[]).slice(0,3);status.textContent=users.length?'Selecteer de gebruiker die je wilt uitnodigen.':'Geen beschikbare gebruikers gevonden.';
    users.forEach(user=>{const b=document.createElement('button');b.type='button';b.className='btn secondary';b.textContent=user.username;b.dataset.suggestedUser=user.user_id;
     b.onclick=()=>{if(busy)return;selected=user;revision++;input.value=user.username;list.replaceChildren();status.textContent=`Geselecteerd: ${user.username}`;send.disabled=false;};list.append(b);});
   }catch(error){if(valid()&&version===revision)status.textContent=error.message||'Zoeken mislukt. Probeer opnieuw.';}
  },250);
 };
 form.onsubmit=async event=>{
  event.preventDefault();if(!selected||selected.username!==input.value||busy)return;
  const user=selected;busy=true;input.disabled=true;send.disabled=true;status.textContent='Uitnodiging versturen…';
  try {
   const r=await supabase.rpc('send_pool_invitation',{p_pool_id:poolId,p_user_id:user.user_id});
   if(!valid())return;if(r.error)throw r.error;
   selected=null;revision++;input.value='';list.replaceChildren();status.textContent=`${user.username} is uitgenodigd. De uitnodiging staat bij Spel > Poules.`;
  }catch(error){if(valid())status.textContent=error.message||'Versturen mislukt. Probeer opnieuw.';}
  finally{busy=false;if(valid()){input.disabled=false;send.disabled=!selected;}}
 };
}
