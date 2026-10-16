// Provider shapes verified against DartsAPI /v1/fixtures and /v1/results/yesterday.
// No odds, guessed score units, fuzzy participant matching or partial pagination.
export function validDate(value){
  return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T00:00:00Z'))&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;
}
function text(value,required=true){
  if(value==null&&!required)return null;
  if(typeof value!=='string'||!value.trim()||value.length>120||/[\u0000-\u001f\u007f]/.test(value))throw Error('invalid_data');
  return value.trim();
}
function id(value,prefix){const v=text(value);if(!new RegExp('^'+prefix+'_[a-z0-9_-]+$','i').test(v))throw Error('invalid_data');return v;}
function player(p){if(!p||typeof p!=='object')throw Error('invalid_data');return {name:text(p.name),id:id(p.player_id,'pl')};}
export function normalizeDarts(rows,scope){
  const out=[],seen=new Set();
  for(const row of rows){
    if(!row||typeof row!=='object'||Array.isArray(row))throw Error('invalid_data');
    const competition=scope.kind==='fixtures'?row.competition:row.event?.name;
    if(typeof competition!=='string'||competition.trim().toLowerCase()!==scope.competition.trim().toLowerCase())continue;
    const date=scope.kind==='fixtures'?row.date:row.played_on;
    if(!validDate(date))throw Error('invalid_data');
    if(date<scope.from||date>scope.to)continue;
    const external=id(scope.kind==='fixtures'?row.fixture_id:row.match_id,scope.kind==='fixtures'?'fx':'mt');
    if(seen.has(external))throw Error('invalid_data');seen.add(external);
    let a,b,start=null;
    if(scope.kind==='fixtures'){
      if(!Array.isArray(row.players)||row.players.length!==2)throw Error('invalid_data');
      a=player(row.players[0]);b=player(row.players[1]);
      if(row.starts_at!=null){
        if(typeof row.starts_at!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/.test(row.starts_at)||!Number.isFinite(Date.parse(row.starts_at)))throw Error('invalid_data');
        if(!validDate(row.starts_at.slice(0,10))||row.starts_at.slice(0,10)!==date)throw Error('invalid_data');
        start=new Date(row.starts_at).toISOString();if(start.slice(0,10)!==date)throw Error('invalid_data');
      }
    }else{a=player(row.winner);b=player(row.loser);}
    if(a.id===b.id||a.name.toLowerCase()===b.name.toLowerCase())throw Error('invalid_data');
    const p={external_id:external,competition:text(competition),played_on:date,round:text(row.round,false),home_name:a.name,away_name:b.name,home_player_id:a.id,away_player_id:b.id};
    if(scope.kind==='fixtures')Object.assign(p,{scheduled_start:start,date_confirmed:row.date_confirmed===true});
    else{
      if(!Number.isInteger(row.winner.score)||!Number.isInteger(row.loser.score)||row.winner.score<=row.loser.score||row.winner.score>99||row.loser.score<0)throw Error('invalid_data');
      const blocked=row.walkover===true||row.played===false||row.retired===true||(row.status!=null&&!['finished','completed','settled'].includes(String(row.status).toLowerCase()));
      Object.assign(p,{home_score:row.winner.score,away_score:row.loser.score,event_id:text(row.event?.event_id,false),source_status:blocked?'blocked':'settled'});
    }
    out.push(p);
  }
  return out;
}
export async function readDarts(fetcher,key,scope){
  if(!['fixtures','results'].includes(scope.kind)||!validDate(scope.from)||!validDate(scope.to)||scope.from>scope.to||
    (Date.parse(scope.to)-Date.parse(scope.from))/86400000>31||!text(scope.competition))throw Error('invalid_data');
  const all=[],seen=new Set();let cursor=null,pages=0;
  do{
    const url=new URL('https://api.dartsapi.com/v1/'+(scope.kind==='fixtures'?'fixtures':'results/yesterday'));
    url.searchParams.set('limit','100');
    if(scope.kind==='fixtures'){url.searchParams.set('from',scope.from);url.searchParams.set('to',scope.to);}
    if(cursor)url.searchParams.set('cursor',cursor);
    const r=await fetcher(url,{headers:{Authorization:'Bearer '+key,Accept:'application/json'},signal:AbortSignal.timeout(10000),redirect:'error'});
    if(!r.ok)throw Error(r.status===429?'rate_limited':'upstream_error');
    const body=await r.text();if(body.length>1000000)throw Error('invalid_data');
    let data;try{data=JSON.parse(body);}catch{throw Error('invalid_data');}
    if(!Array.isArray(data?.data)||data.data.length>100||!data.meta||!Object.hasOwn(data.meta,'next_cursor'))throw Error('invalid_data');
    all.push(...data.data);pages++;
    const next=data.meta.next_cursor;
    if(next!==null&&(typeof next!=='string'||!next||next.length>2048))throw Error('invalid_data');
    cursor=next;
    if(cursor){if(seen.has(cursor)||pages>=5)throw Error('invalid_data');seen.add(cursor);}
  }while(cursor);
  return {items:normalizeDarts(all,scope),pages,fetched:all.length};
}
