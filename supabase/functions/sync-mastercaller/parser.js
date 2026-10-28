import {parseHTML} from 'linkedom';

export function sourceUrl(value) {
  const u=new URL(value);
  if(u.protocol!=='https:'||u.port||u.username||u.password||u.search||u.hash||!['mastercaller.com','www.mastercaller.com','mastercaller.nl','www.mastercaller.nl'].includes(u.hostname))throw Error('Gebruik een Mastercaller-uitslagenlink.');
  const path=u.pathname.replace(/^\/toernooien\//,'/tournaments/').replace(/\/uitslagen\/?$/,'/results');
  if(!/^\/tournaments\/(?:[a-z0-9-]+\/20\d{2}|players-championships\/20\d{2}-pc-[1-9]\d?-[a-z0-9]+(?:-[a-z0-9]+)*)\/results\/?$/.test(path))throw Error('Gebruik de uitslagenpagina van één toernooi en jaargang.');
  return 'https://mastercaller.com'+path.replace(/\/$/,'');
}
export function parseResults(html,url,referenceTime=new Date()) {
  const canonical=sourceUrl(url),year=canonical.split('/')[5].slice(0,4);
  const {document}=parseHTML(html);
  const title=document.querySelector('h1')?.textContent.trim();
  if(!title||!document.body.textContent.includes('Professional Darts Corporation'))throw Error('Geen herkenbare PDC-uitslagenpagina ontvangen.');
  const depths={'Final':0,'Semi-finals':1,'Quarter-finals':2,'Last 16':3,'Last 32':4,'Last 48':5,'Last 64':5,'Last 96':6,'Last 128':6};
  const records=[],fixtures=[],rounds=[],seen=new Map();
  for(const heading of document.querySelectorAll('h3')) {
    const label=heading.textContent.trim(),depth=depths[label];
    if(depth===undefined)continue;
    if(rounds.some(r=>r.depth===depth))throw Error('Dubbelzinnige ronde-indeling in de bron.');
    rounds.push({label,depth});
    const cards=heading.parentElement.parentElement.querySelectorAll('div.grid.grid-cols-1');
    for(const card of cards) {
      const players=[...card.querySelectorAll('a[href*="/players/"]')];
      const winners=card.querySelectorAll('div.bg-green-500'),losers=card.querySelectorAll('div.bg-red-500');
      const dateText=card.parentElement.querySelector('.relative')?.textContent.replace(/\s+/g,' ').trim()||'';
      const date=dateText.match(/\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/);
      const day=date?isoDay(year,date[2],date[1]):relativeDay(dateText,referenceTime);
      const names=players.map(p=>p.textContent.trim().replace(/\s+/g,' '));
      if(players.length===2&&day){
        const time=dateText.match(/-\s*(\d{1,2}):(\d{2})\b/);
        fixtures.push({depth,home_name:names[0],away_name:names[1],date:day,start:time?amsterdamStart(day,time[1],time[2]):null});
      }
      // Only explicit winner/loser styling is accepted as a completed match.
      if(!winners.length&&!losers.length)continue;
      if(players.length!==2||winners.length!==1||losers.length!==1)throw Error('Gewijzigde of onvolledige wedstrijdstructuur.');
      const sides=[...card.children];
      if(sides.length!==2)throw Error('Onbekende score-indeling.');
      const scores=sides.map(side=>side.querySelector('div.bg-green-500,div.bg-red-500')?.textContent.trim());
      if(!scores.every(s=>/^\d{1,2}$/.test(s||'')))throw Error('Onleesbare eindstand.');
      const [home_score,away_score]=scores.map(Number);
      const winnerScore=Number(winners[0].textContent.trim());
      if(home_score===away_score||winnerScore!==Math.max(home_score,away_score))throw Error('Afwijkende uitslag; handmatige controle vereist.');
      if(!day)throw Error('Wedstrijddatum ontbreekt in de bron.');
      const row={depth,round:label,home_name:names[0],away_name:names[1],home_score,away_score,date:day};
      const key=depth+'|'+names.map(n=>n.toLowerCase()).sort().join('|');
      if(seen.has(key))throw Error('Dubbele wedstrijd in de bron; controleer het toernooi.');
      seen.set(key,row);records.push(row);
    }
  }
  if(!rounds.length)throw Error('Geen ondersteunde knock-outronden gevonden.');
  if(records.length>256)throw Error('Te veel uitslagen in één toernooi.');
  const body=document.body.textContent.replace(/\s+/g,' ');
  const startDate=body.match(/Start Date:\s*(\d{1,2})\s+(\w{3})\s+(20\d{2})/),endDate=body.match(/End Date:\s*(\d{1,2})\s+(\w{3})\s+(20\d{2})/);
  return {title,rounds,fixtures,records:records.sort((a,b)=>b.depth-a.depth),url:canonical,start_date:startDate?isoDay(startDate[3],startDate[2],startDate[1]):null,end_date:endDate?isoDay(endDate[3],endDate[2],endDate[1]):null};
}

// Resolve relative source labels once per fetched page, in the source timezone.
export function relativeDay(text,referenceTime){
 const label=text.match(/^(Today|Tomorrow|Yesterday|Vandaag|Morgen|Gisteren)\b/i)?.[1]?.toLowerCase();
 if(!label)return null;
 const instant=new Date(referenceTime);
 if(!Number.isFinite(instant.getTime()))throw Error('Ongeldig ophaaltijdstip.');
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Amsterdam',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(instant);
 const part=type=>parts.find(p=>p.type===type).value;
 const day=new Date(Date.UTC(Number(part('year')),Number(part('month'))-1,Number(part('day'))));
 day.setUTCDate(day.getUTCDate()+({today:0,vandaag:0,tomorrow:1,morgen:1,yesterday:-1,gisteren:-1}[label]));
 return day.toISOString().slice(0,10);
}
function isoDay(year,month,day){
 const m=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'].indexOf(month)+1;
 if(!m||Number(day)<1||Number(day)>31)throw Error('Onleesbare datum.');
 return `${year}-${String(m).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
}
// Mastercaller publishes Dutch local times; reject ambiguous/nonexistent DST times.
export function amsterdamStart(day,hour,minute){
 const wanted=`${day}T${String(hour).padStart(2,'0')}:${minute}`,base=Date.parse(wanted+'Z'),matches=[];
 const format=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Amsterdam',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
 for(const offset of [60,120]){const t=base-offset*60000;if(Number.isFinite(t)&&format.format(t).replace(' ','T')===wanted)matches.push(new Date(t).toISOString());}
 return matches.length===1?matches[0]:null;
}
const clean=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/ł/g,'l').toLowerCase().replace(/\s+/g,' ').trim();
export function parseBracket(html,results){
 const {document}=parseHTML(html),container=document.querySelector('.bracket-container');
 if(!container)throw Error('Het Mastercaller-bracket is nog niet beschikbaar.');
 const rounds=[...container.querySelectorAll('.round-holder')].map(holder=>{
  const label=holder.querySelector('.round-title')?.textContent.trim(),format=holder.querySelector('.round-format')?.textContent.trim().match(/^Best of (\d+) (Legs|Sets)$/i);
  if(!label||!format||Number(format[1])%2!==1)throw Error('Onbekend wedstrijdformat in het bracket.');
  return {order:Number(holder.dataset.col),name:label,unit:format[2].toLowerCase(),first_to:(Number(format[1])+1)/2};
 }).sort((a,b)=>a.order-b.order);
 if(!rounds.length||rounds.some((r,i)=>r.order!==i+1)||rounds.length>7)throw Error('Onbekende bracketindeling.');
 const fixtures=[...container.querySelectorAll('.match-holder')].map(holder=>{
  const order=Number(holder.dataset.col),position=Number(holder.dataset.row),depth=rounds.length-order;
  const sides=[holder.querySelector('.player1'),holder.querySelector('.player2')];
  const names=sides.map(p=>p?.querySelector('.name')?.textContent.replace(/\s+/g,' ').trim()||'');
  const matching=results.fixtures.filter(f=>f.depth===depth&&[clean(f.home_name),clean(f.away_name)].sort().join('|')===names.map(clean).sort().join('|'));
  if(matching.length>1)throw Error('Dubbele planning in de bron.');
  return {order,position,depth,home_name:names[0],away_name:names[1],home_id:sides[0]?.dataset.playerid||null,away_id:sides[1]?.dataset.playerid||null,start:matching[0]?.start||null,date:matching[0]?.date||null};
 }).sort((a,b)=>a.order-b.order||a.position-b.position);
 const first=fixtures.filter(f=>f.order===1),roster=first.flatMap(f=>[f.home_name,f.away_name]);
 if(roster.length&&roster.every(n=>!n))throw Error('De loting van dit toernooi is nog niet ingevuld op Mastercaller. Probeer opnieuw zodra de deelnemers in het bracket staan.');
 // Initial fully automatic setup supports complete, power-of-two knockouts.
 // Byes/seeded entry require an explicit source graph; never guess their slots.
 if(roster.length!==2**rounds.length||roster.some(n=>!n)||new Set(roster.map(clean)).size!==roster.length)throw Error('Dit bracket kan nog niet volledig automatisch worden ingericht.');
 for(const r of rounds){const matches=fixtures.filter(f=>f.order===r.order);if(matches.length!==2**(rounds.length-r.order)||matches.some((f,i)=>f.position!==i+1))throw Error('Het bracket is onvolledig.');}
 for(const record of results.records){
  if(!fixtures.some(f=>f.depth===record.depth&&[clean(f.home_name),clean(f.away_name)].sort().join('|')===[clean(record.home_name),clean(record.away_name)].sort().join('|')))throw Error('Bracket en uitslagen spreken elkaar tegen.');
 }
 if(!results.start_date||!results.end_date)throw Error('De toernooidatums ontbreken.');
 return {...results,rounds,roster,bracket:fixtures};
}

async function fetchHtml(canonical,fetcher){
  const r=await fetcher(canonical,{redirect:'error',signal:AbortSignal.timeout(15000),headers:{Accept:'text/html','User-Agent':'Predict-Mastercaller-Test/1.0'}});
  if(!r.ok)throw Error(`Mastercaller niet bereikbaar (HTTP ${r.status}). Automatische verwerking wacht op de bron.`);
  if(!r.headers.get('content-type')?.includes('text/html'))throw Error('Mastercaller gaf geen HTML-uitslagenpagina terug.');
  const reader=r.body.getReader(),parts=[];let size=0;
  try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>2000000)throw Error('Mastercaller-pagina is te groot.');parts.push(value);}}finally{await reader.cancel();}
  const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
  return new TextDecoder().decode(bytes);
}
export async function fetchResults(url,fetcher=fetch){
 const canonical=sourceUrl(url),referenceTime=new Date();return parseResults(await fetchHtml(canonical,fetcher),canonical,referenceTime);
}
export async function fetchTournament(url,fetcher=fetch){
 const canonical=sourceUrl(url),results=await fetchResults(canonical,fetcher);
 return parseBracket(await fetchHtml(canonical.replace(/\/results$/,'/bracket'),fetcher),results);
}
