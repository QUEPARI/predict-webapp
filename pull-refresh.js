// One gesture refreshes the current app view; it never invokes the sports source.
export function installPullRefresh({onRefresh,canRefresh=()=>true,doc=document,win=window}) {
 const media=win.matchMedia('(max-width: 1100px) and (pointer: coarse)');
 const indicator=doc.createElement('div');indicator.className='pull-refresh';indicator.hidden=true;
 indicator.setAttribute('role','status');indicator.setAttribute('aria-live','polite');doc.body.append(indicator);
 const threshold=80;let start=null,distance=0,busy=false;
 const top=()=>Math.max(win.scrollY||0,doc.scrollingElement?.scrollTop||0)<=0;
 const excluded=element=>{
  if(element?.closest('input,textarea,select,[contenteditable="true"],dialog,[role="dialog"],canvas'))return true;
  for(let el=element;el&&el!==doc.body&&el!==doc.documentElement;el=el.parentElement){
   const style=win.getComputedStyle(el);
   if((/(auto|scroll)/.test(style.overflowY)&&el.scrollHeight>el.clientHeight)||(/(auto|scroll)/.test(style.overflowX)&&el.scrollWidth>el.clientWidth))return true;
  }
  return false;
 };
 function reset(){start=null;distance=0;if(!busy){indicator.hidden=true;indicator.classList.remove('is-loading');}}
 const update=()=>{doc.documentElement.classList.toggle('pull-refresh-enabled',media.matches);if(!media.matches)reset();};
 function begin(event){reset();if(busy||!media.matches||event.touches.length!==1||!top()||excluded(event.target)||doc.querySelector('dialog[open],[aria-modal="true"]'))return;
  start={x:event.touches[0].clientX,y:event.touches[0].clientY};
 }
 function move(event){
  if(!start)return;if(event.touches.length!==1||!top()){reset();return;}
  const dx=event.touches[0].clientX-start.x,dy=event.touches[0].clientY-start.y;
  if(dy<=0||Math.abs(dx)>Math.abs(dy)){reset();return;}
  if(dy<8)return;
  if(!event.cancelable){reset();return;}event.preventDefault();distance=dy;
  indicator.hidden=false;indicator.textContent=dy>=threshold?'↓ Laat los om te verversen':'↓ Trek omlaag om te verversen';
  indicator.style.setProperty('--pull-offset',Math.min(dy*.45,64)+'px');
 }
 async function end(){
  const refresh=start&&distance>=threshold;start=null;distance=0;
  if(!refresh||busy){reset();return;}
  busy=true;indicator.hidden=false;indicator.classList.add('is-loading');indicator.textContent='Verversen…';
  try{if(await canRefresh()){await onRefresh();await new Promise(resolve=>win.setTimeout(resolve,400));}}
  catch{indicator.textContent='Verversen mislukt. Probeer opnieuw.';await new Promise(resolve=>win.setTimeout(resolve,1800));}
  finally{busy=false;reset();}
 }
 doc.addEventListener('touchstart',begin,{passive:true});doc.addEventListener('touchmove',move,{passive:false});
 doc.addEventListener('touchend',end,{passive:true});doc.addEventListener('touchcancel',reset,{passive:true});
 media.addEventListener('change',update);update();
 return ()=>{doc.removeEventListener('touchstart',begin);doc.removeEventListener('touchmove',move);doc.removeEventListener('touchend',end);doc.removeEventListener('touchcancel',reset);media.removeEventListener('change',update);doc.documentElement.classList.remove('pull-refresh-enabled');indicator.remove();};
}
