const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const roleLabel={user:'Gebruiker',admin:'Beheerder',super_admin:'Hoofdbeheerder'};
export async function loadAdminAccounts(host,ctx){
 const alive=()=>host.isConnected&&ctx.isCurrent();let users=[],page=0,busy=false;
 host.innerHTML='<h2>Gebruikers</h2><div class="toolbar"><label>Gebruiker zoeken<input type="search" data-account-search placeholder="Naam of gebruikersnaam"></label></div><p role="status" data-account-message></p><div data-account-list></div>';
 const message=host.querySelector('[data-account-message]'),list=host.querySelector('[data-account-list]'),search=host.querySelector('input');
 function draw(){
  const query=search.value.trim().toLocaleLowerCase('nl-NL'),filtered=users.filter(u=>(u.username+' '+(u.display_name||'')).toLocaleLowerCase('nl-NL').includes(query));
  page=Math.min(page,Math.max(0,Math.ceil(filtered.length/20)-1));
  list.innerHTML=`<p class="hint">${filtered.length} van ${users.length} gebruikers</p><div class="table-wrap"><table class="admin-accounts-table"><thead><tr><th>Gebruikersnaam</th><th>Naam</th><th>Rol</th><th>Account</th><th>Beheerrechten</th></tr></thead><tbody>${filtered.slice(page*20,page*20+20).map(u=>`<tr><td data-label="Gebruikersnaam">${esc(u.username)}</td><td data-label="Naam">${esc(u.display_name||'—')}</td><td data-label="Rol">${esc(roleLabel[u.role]||u.role)}</td><td data-label="Account">${u.activated?'Geactiveerd':'Nog niet ingelogd'}</td><td data-label="Beheerrechten">${u.can_change_role?`<button type="button" class="ghost mini" data-account-role="${esc(u.id)}">${u.role==='admin'?'Beheerrechten intrekken':'Beheerder maken'}</button>`:u.role==='super_admin'?'Beschermd':'Alleen hoofdbeheerder'}</td></tr>`).join('')||'<tr><td colspan="5">Geen gebruikers gevonden.</td></tr>'}</tbody></table></div>${filtered.length>20?`<div class="toolbar"><button type="button" class="ghost" data-page-prev ${page===0?'disabled':''}>Vorige</button><span>${page+1} / ${Math.ceil(filtered.length/20)}</span><button type="button" class="ghost" data-page-next ${(page+1)*20>=filtered.length?'disabled':''}>Volgende</button></div>`:''}`;
  list.querySelector('[data-page-prev]')?.addEventListener('click',()=>{page--;draw();});list.querySelector('[data-page-next]')?.addEventListener('click',()=>{page++;draw();});
  list.querySelectorAll('[data-account-role]').forEach(button=>button.onclick=async()=>{
   if(busy)return;const user=users.find(u=>u.id===button.dataset.accountRole),role=user.role==='admin'?'user':'admin';
   if(!confirm(role==='admin'?`${user.username} beheerder maken? Deze persoon krijgt toegang tot spel- en accountbeheer.`:`Beheerrechten van ${user.username} intrekken?`))return;
   busy=true;host.querySelectorAll('button').forEach(b=>b.disabled=true);message.textContent='Rechten opslaan…';
   try{const r=await ctx.supabase.rpc('admin_set_account_role',{p_user:user.id,p_role:role});if(r.error)throw r.error;if(!alive())return;await read();if(alive())message.textContent='Rechten opgeslagen.';}
   catch(error){if(alive())message.textContent='Niet opgeslagen: '+error.message;}
   finally{busy=false;if(alive())draw();}
  });
 }
 async function read(){const r=await ctx.supabase.rpc('admin_list_accounts');if(r.error)throw r.error;if(!alive())return;users=Array.isArray(r.data)?r.data:[];draw();}
 search.oninput=()=>{page=0;draw();};
 try{await read();}catch(error){if(alive())message.textContent='Gebruikers laden mislukt: '+error.message;}
}
