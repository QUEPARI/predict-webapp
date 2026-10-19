import {fetchTournament,fetchResults} from '../../supabase/functions/sync-mastercaller/parser.js';
const endpoint='https://sfcozzjcuppfypetbbzn.supabase.co/functions/v1/mastercaller-github';
const oidcURL=new URL(process.env.ACTIONS_ID_TOKEN_REQUEST_URL);oidcURL.searchParams.set('audience',endpoint);
const identity=await fetch(oidcURL,{headers:{Authorization:'Bearer '+process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN}});
if(!identity.ok)throw Error('GitHub identity unavailable');const {value:token}=await identity.json();if(!token)throw Error('GitHub identity missing');
async function call(body){const response=await fetch(endpoint,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(45000)});const result=await response.json();if(!response.ok)throw Error(result.error||'Worker request failed');return result;}
// On deployment only: verify end-to-end using public source data, without creating a tournament.
if(process.env.GITHUB_EVENT_NAME==='push'){
 const snapshot=await fetchTournament('https://mastercaller.com/tournaments/european-championship/2026/results');
 await call({action:'cache',snapshot});console.log(JSON.stringify({source_verified:true,players:snapshot.roster.length,matches:snapshot.bracket.length,cache_uploaded:true}));
}
const {jobs}=await call({action:'claim'});console.log(JSON.stringify({claimed:jobs.length}));
for(const job of jobs){let snapshot=null,records=[],error=null;
 try{const data=await(job.kind==='create'||job.automatic_setup?fetchTournament(job.url):fetchResults(job.url));records=data.records;snapshot=job.kind==='create'||job.automatic_setup?data:null;}catch(e){error=e.message;}
 const result=await call({...job,action:'finish',snapshot,records,error});console.log(JSON.stringify({kind:job.kind,status:result.status||'processed',received:records.length,source_error:error}));
}
