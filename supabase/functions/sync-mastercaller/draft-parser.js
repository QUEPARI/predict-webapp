import {parseHTML} from 'linkedom';
import {sourceUrl,parseResults,parseBracket,fetchHtml,amsterdamStart,relativeDay} from './parser.js';
const clean=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/\s+/g,' ').trim();
const name=p=>p?.textContent.replace(/\s+/g,' ').trim()||'';
const iso=(year,month,day)=>{const m=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'].indexOf(month)+1;if(!m||+day<1||+day>31)throw Error('Onleesbare bronperiode.');return `${year}-${String(m).padStart(2,'0')}-${String(day).padStart(2,'0')}`;};
export function parseSourceMetadata(html,url){
 const canonical=sourceUrl(url),{document:d}=parseHTML(html),body=d.body.textContent.replace(/\s+/g,' '),title=name(d.querySelector('h1'));
 if(!title||!body.includes('Professional Darts Corporation'))throw Error('Geen herkenbare PDC-toernooipagina ontvangen.');
 const start=body.match(/Start Date:\s*(\d{1,2})\s+(\w{3})\s+(20\d{2})/),end=body.match(/End Date:\s*(\d{1,2})\s+(\w{3})\s+(20\d{2})/);
 if(!start||!end)throw Error('De toernooiperiode ontbreekt op Mastercaller.');
 return {url:canonical,title,start_date:iso(start[3],start[2],start[1]),end_date:iso(end[3],end[2],end[1])};
}
function koShape(html,results){
 const {document:d}=parseHTML(html),container=d.querySelector('.bracket-container');
 if(!container)return {rounds:[],matches:[],roster:[],ready:false};
 const rounds=[...container.querySelectorAll('.round-holder')].map(h=>{const fmt=name(h.querySelector('.round-format')).match(/^Best of (\d+) (Legs|Sets)$/i);if(!fmt||+fmt[1]%2!==1)throw Error('Het wedstrijdformat in het bracket is niet herkenbaar.');return {order:+h.dataset.col,name:name(h.querySelector('.round-title')),unit:fmt[2].toLowerCase(),first_to:(+fmt[1]+1)/2};}).sort((a,b)=>a.order-b.order);
 if(!rounds.length||rounds.length>7||rounds.some((r,i)=>r.order!==i+1))throw Error('Onbekende bracketindeling.');
 const matches=[...container.querySelectorAll('.match-holder')].map(h=>{const round=+h.dataset.col,position=+h.dataset.row,home=name(h.querySelector('.player1 .name')),away=name(h.querySelector('.player2 .name')),depth=rounds.length-round;
 const schedule=results.fixtures.filter(f=>f.depth===depth&&[clean(f.home_name),clean(f.away_name)].sort().join('|')===[clean(home),clean(away)].sort().join('|'));if(schedule.length>1)throw Error('Dubbele planning in de bron.');
 return {key:`k:${round}:${position}`,round,position,home_name:home,away_name:away,start:schedule[0]?.start||null,date:schedule[0]?.date||null};}).sort((a,b)=>a.round-b.round||a.position-b.position);
 for(const r of rounds){const ms=matches.filter(m=>m.round===r.order);if(ms.length!==2**(rounds.length-r.order)||ms.some((m,i)=>m.position!==i+1))throw Error('Het bracket is onvolledig.');}
 const roster=matches.filter(m=>m.round===1).flatMap(m=>[m.home_name,m.away_name]);
 const ready=roster.every(Boolean)&&new Set(roster.map(clean)).size===roster.length;
 if(ready)parseBracket(html,results); // Keep the existing full source validation.
 return {rounds,matches,roster:ready?roster:[],ready};
}
export function parseSourceDraft(resultsHtml,bracketHtml,url,groupsHtml=null,referenceTime=new Date()){
 const meta=parseSourceMetadata(resultsHtml,url);let results;try{results=parseResults(resultsHtml,url,referenceTime);}catch(e){if(!/Geen ondersteunde knock-outronden gevonden/.test(e.message))throw e;results={fixtures:[],records:[]};}const ko=koShape(bracketHtml,results);
 const {document:d}=parseHTML(resultsHtml),groups=meta.url.includes('/grand-slam-of-darts/')||[...d.querySelectorAll('a')].some(a=>/\/groupstage\/?$/.test(a.getAttribute('href')||''));
 if(!groups)return {...meta,...ko,format:'knockout',records:results.records,ready:ko.ready,reason:ko.ready?null:'De eerste ronde is nog niet volledig bekend op Mastercaller.'};
 const base={...meta,format:'groups',rounds:[{order:1,name:'Groepsfase',unit:'legs',first_to:null},...ko.rounds.map(r=>({...r,order:r.order+1}))],matches:ko.matches.map(m=>({...m,round:m.round+1})),records:results.records,roster:[],ready:false,reason:'De groepsindeling en wedstrijden zijn nog niet volledig bekend op Mastercaller.'};
 if(!groupsHtml)return base;
 const {document:g}=parseHTML(groupsHtml),headings=[...g.querySelectorAll('h3')].filter(h=>/^Group\s+[A-Z]+$/i.test(name(h)));
 if(!headings.length)return base;
 const roster=[],fixtures=[],records=[],groupNames=new Set();let complete=true;
 for(const h of headings){const label=name(h);if(groupNames.has(label))throw Error('Dubbele groep in de bron.');groupNames.add(label);const box=h.parentElement.parentElement;
  const players=[...box.querySelectorAll('table tbody a[href*="/players/"]')].map(name);if(players.length!==4||players.some(x=>!x)||new Set(players.map(clean)).size!==4){complete=false;continue;}roster.push(...players);
  const pairs=new Set();
  for(const card of box.querySelectorAll('div.grid.grid-cols-1')){
   const sides=[...card.querySelectorAll('a[href*="/players/"]')].map(name);if(sides.length!==2||sides.some(n=>!players.some(p=>clean(p)===clean(n)))){complete=false;continue;}
   const pair=sides.map(clean).sort().join('|');if(pairs.has(pair)||clean(sides[0])===clean(sides[1]))throw Error('Dubbele groepswedstrijd in de bron.');pairs.add(pair);
   const text=card.parentElement.querySelector('.relative')?.textContent.replace(/\s+/g,' ').trim()||'',date=text.match(/\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/),day=date?iso(meta.start_date.slice(0,4),date[2],date[1]):relativeDay(text,referenceTime),time=text.match(/-\s*(\d{1,2}):(\d{2})\b/);
   fixtures.push({key:'g:'+label+':'+pair,round:1,position:fixtures.length+1,group:label,home_name:sides[0],away_name:sides[1],date:day,start:day&&time?amsterdamStart(day,time[1],time[2]):null});
   const win=card.querySelectorAll('div.bg-green-500'),lose=card.querySelectorAll('div.bg-red-500');if(!win.length&&!lose.length)continue;
   const scores=[...card.children].map(x=>x.querySelector('div.bg-green-500,div.bg-red-500')?.textContent.trim());if(win.length!==1||lose.length!==1||scores.length!==2||!scores.every(x=>/^\d{1,2}$/.test(x||''))||!day||scores[0]===scores[1]||+win[0].textContent.trim()!==Math.max(...scores.map(Number)))throw Error('Onleesbare groepsuitslag.');
   records.push({depth:ko.rounds.length,round:label,home_name:sides[0],away_name:sides[1],home_score:+scores[0],away_score:+scores[1],date:day});
  }
  if(pairs.size!==6)complete=false;
 }
 if(!complete||!ko.rounds.length||headings.length*2!==2**ko.rounds.length||new Set(roster.map(clean)).size!==roster.length)return base;
 return {...base,ready:true,reason:null,roster,matches:[...fixtures,...base.matches],records:[...records,...base.records]};
}
export async function fetchSourceDraft(url,fetcher=fetch){
 const canonical=sourceUrl(url),reference=new Date(),results=await fetchHtml(canonical,fetcher),meta=parseSourceMetadata(results,canonical);
 let bracket='';try{bracket=await fetchHtml(canonical.replace(/\/results$/,'/bracket'),fetcher);}catch(e){if(!/HTTP 404/.test(e.message))throw e;}
 const groups=meta.url.includes('/grand-slam-of-darts/')||/href=["'][^"']*\/groupstage\/?["']/.test(results);
 let groupHtml=null;if(groups){const groupUrl=canonical.replace(/\/results$/,'/groupstage');try{groupHtml=await fetchHtml(groupUrl,fetcher);}catch(error){if(!/HTTP 404/.test(error.message))throw error;}}
 return parseSourceDraft(results,bracket,canonical,groupHtml,reference);
}
