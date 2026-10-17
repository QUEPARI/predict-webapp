// Fixed geometry keeps every round in one horizontally scrollable bracket.
export function layoutBracket(view,data){
 const columns=[...view.querySelectorAll(':scope > section')];if(!columns.length)return;
 const all=new Map(),byId=new Map();const rounds=[...data.rounds].sort((a,b)=>a.order-b.order);
 rounds.forEach(r=>data.matches.filter(m=>m.round===r.order).forEach((m,i)=>{const node={...m,position:m.position||i+1};all.set(`${m.round}:${node.position}`,node);byId.set(m.id,node);}));
 const measured=new Map();let half=56;
 if(view.classList.contains('compact-public')){
   const probe=document.createElement('div');probe.className='ko-bracket compact-public';Object.assign(probe.style,{position:'fixed',left:'-10000px',visibility:'hidden',width:'200px'});probe.innerHTML='<div class="ko-track"><section class="ko-round"></section></div>';
   const col=probe.querySelector('section');view.querySelectorAll('article').forEach(card=>{const copy=card.cloneNode(true);Object.assign(copy.style,{position:'relative',height:'auto',top:'auto'});col.append(copy);});document.body.append(probe);
   col.querySelectorAll('article').forEach(card=>measured.set(card.dataset.node,card.offsetHeight));half=Math.max(60,...measured.values())/2;probe.remove();
 }
 const step=half*2+16;
 const centers=new Map(),links=[];let row=0;
 function visit(m){if(!m||m.bye)return null;if(centers.has(m.id))return centers.get(m.id);
  const parents=[all.get(`${m.round-1}:${m.position*2-1}`),all.get(`${m.round-1}:${m.position*2}`)];
  const ys=parents.map(p=>visit(p)).filter(y=>y!=null);const y=ys.length?ys.reduce((a,b)=>a+b,0)/ys.length:half+row++*step;centers.set(m.id,y);parents.filter(p=>p&&!p.bye).forEach(p=>links.push([p,m]));return y;
 }
 [...byId.values()].sort((a,b)=>b.round-a.round||a.position-b.position).forEach(visit);
 const height=Math.max(step,row*step)+32,track=document.createElement('div');track.className='ko-track';track.style.height=height+'px';
 columns.forEach((column,i)=>{column.style.height=height+'px';column.dataset.bracketRound=rounds[i]?.order;column.querySelectorAll('article').forEach((card,j)=>{const match=byId.get(card.dataset.node)||data.matches.filter(m=>m.round===rounds[i].order&&!m.bye)[j];if(match){card.dataset.node=match.id;card.style.top=((centers.get(match.id)||half)-(measured.get(match.id)||half*2)/2+32)+'px';}});track.append(column);});
 const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.classList.add('bracket-links');svg.setAttribute('aria-hidden','true');svg.setAttribute('width',String(columns.length*200+Math.max(0,columns.length-1)*32));svg.setAttribute('height',String(height));
 links.forEach(([from,to])=>{const a=rounds.findIndex(r=>r.order===from.round),b=rounds.findIndex(r=>r.order===to.round),x=a*232+200,end=b*232,y=centers.get(from.id)+32,dest=centers.get(to.id)+32;const path=document.createElementNS(svg.namespaceURI,'path');path.setAttribute('d',`M${x},${y} H${x+16} V${dest} H${end}`);svg.append(path);});track.prepend(svg);
 view.replaceChildren(track);view.tabIndex=0;view.setAttribute('role','region');view.setAttribute('aria-label','Toernooischema, horizontaal verschuifbaar');
 const toolbar=document.createElement('div');toolbar.className='bracket-controls';toolbar.innerHTML='<span class="hint">Veeg of scroll horizontaal door de rondes</span><button type="button" class="ghost" aria-label="Vorige ronde in schema">←</button><button type="button" class="ghost" aria-label="Volgende ronde in schema">→</button>';
 toolbar.querySelectorAll('button').forEach((button,i)=>button.onclick=()=>view.scrollBy({left:i?232:-232,behavior:'smooth'}));view.before(toolbar);
}
