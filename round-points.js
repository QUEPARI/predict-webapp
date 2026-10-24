const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function mountRoundPoints(host,ctx,tournament,{getBusy=()=>false,setBusy=()=>{}}={}){
 let expected=structuredClone(tournament.rules||[]),busy=false;
 const alive=()=>host.isConnected&&ctx.isCurrent()&&!ctx.signal?.aborted;
 host.innerHTML=`<summary>Puntenberekening</summary><form class="stack round-points-form" novalidate><p class="hint">Pas de punten per ronde aan. Opslaan herberekent bestaande voorspellingen, het toernooiklassement en alle pouleklassementen.</p>${expected.length?`<div class="table-wrap"><table class="round-points-table"><thead><tr><th scope="col">Ronde</th><th scope="col">Juiste winnaar</th><th scope="col">Exacte score</th></tr></thead><tbody>${expected.map(r=>`<tr data-points-round="${esc(r.id)}"><th scope="row">${esc(r.name)}</th><td><input aria-label="${esc(r.name)}: punten juiste winnaar" data-winner type="number" inputmode="numeric" min="0" max="1000" step="1" required value="${esc(r.winner_points)}"></td><td><input aria-label="${esc(r.name)}: punten exacte score" data-exact type="number" inputmode="numeric" min="0" max="1000" step="1" required value="${esc(r.exact_points)}"></td></tr>`).join('')}</tbody></table></div>`:'<p class="hint">Dit toernooi heeft nog geen rondes.</p>'}<p data-points-message role="status" aria-live="polite"></p><button type="submit" class="btn" ${expected.length?'':'disabled'}>Opslaan + herberekenen</button></form>`;
 const form=host.querySelector('form'),message=host.querySelector('[data-points-message]'),detail=host.closest('[data-detail]');
 let otherDirty=detail?.dataset.koDirty==='true';
 detail?.addEventListener('input',e=>{if(alive()&&!host.contains(e.target))otherDirty=true;},{signal:ctx.signal});
 form.onsubmit=async e=>{
  e.preventDefault();if(busy||getBusy()||!expected.length||!alive())return;
  const fields=[...form.querySelectorAll('input')];
  const invalid=fields.filter(i=>i.value.trim()===''||!Number.isInteger(Number(i.value))||Number(i.value)<0||Number(i.value)>1000);
  fields.forEach(i=>i.setAttribute('aria-invalid',String(invalid.includes(i))));
  if(invalid.length){message.className='error';message.textContent='Vul per ronde hele punten tussen 0 en 1000 in.';invalid[0].focus();return;}
  const rules=[...form.querySelectorAll('[data-points-round]')].map(row=>({id:row.dataset.pointsRound,winner_points:Number(row.querySelector('[data-winner]').value),exact_points:Number(row.querySelector('[data-exact]').value)}));
  busy=true;setBusy(true);message.className='hint';message.textContent='Punten opslaan en herberekenen…';
  const controls=[...(detail?.parentElement||host).querySelectorAll('input,select,textarea,button')],states=controls.map(x=>x.disabled);controls.forEach(x=>x.disabled=true);
  try{
   const {data,error}=await ctx.supabase.rpc('admin_save_round_scoring',{p_tournament:tournament.id,p_rules:rules,p_expected:expected});if(error)throw error;
   if(!alive())return;
   expected=structuredClone(data.rules);tournament.rules=structuredClone(data.rules);
   fields.forEach(i=>i.defaultValue=i.value);
   if(detail)detail.dataset.koDirty=String(otherDirty);
   message.className='success';message.textContent=`Opgeslagen en herberekend: ${Number(data.scored_predictions)||0} voorspellingen met uitslag. Toernooi- en pouleklassementen zijn bijgewerkt.`;
   document.dispatchEvent(new CustomEvent('predict-results-changed'));
   ctx.onSaved?.();
  }catch(error){if(alive()){message.className='error';message.textContent='Niet opgeslagen: '+(error.message||'Verbinding mislukt. Probeer opnieuw.');}}
  finally{busy=false;setBusy(false);if(alive())controls.forEach((x,i)=>{if(x.isConnected)x.disabled=states[i];});}
 };
}
