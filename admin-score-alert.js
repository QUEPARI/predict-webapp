export function bindAdminScoreAlert(button,client,{isCurrent,onOpen}){
 let timer,busy=false,stopped=false;
 async function refresh(){
  if(stopped||!button.isConnected||!isCurrent())return;
  if(busy)return;busy=true;clearTimeout(timer);
  try{const r=await client.rpc('admin_result_alert');if(stopped||!button.isConnected||!isCurrent())return;if(r.error)throw r.error;
   const count=Number(r.data?.count)||0;button.hidden=count===0;button.querySelector('[data-score-count]').textContent=String(count);button.setAttribute('aria-label',`${count} gestarte wedstrijden zonder eindstand`);button.title=`${count} uitslagen invullen`;
   const blocked=r.data?.blocked_archives||[];document.querySelectorAll('[data-blocked-archives]').forEach(host=>{host.innerHTML='';if(blocked.length){const p=document.createElement('p');p.className='notice';p.textContent='Archivering wacht op ontbrekende uitslagen: '+blocked.map(t=>t.name).join(', ');host.append(p);}});
   const next=Date.parse(r.data?.next_start)-Date.parse(r.data?.server_now);timer=setTimeout(refresh,Number.isFinite(next)&&next>0?Math.max(1000,Math.min(next+100,60000)):60000);
  }catch{if(!stopped)timer=setTimeout(refresh,60000);}finally{busy=false;}
 }
 button.onclick=onOpen;const visible=()=>{if(!document.hidden)refresh();};const changed=()=>refresh();document.addEventListener('visibilitychange',visible);document.addEventListener('predict-results-changed',changed);refresh();
 return ()=>{stopped=true;clearTimeout(timer);document.removeEventListener('visibilitychange',visible);document.removeEventListener('predict-results-changed',changed);};
}
