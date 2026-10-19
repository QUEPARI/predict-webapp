import {fetchTournament} from '../../supabase/functions/sync-mastercaller/parser.js';
const url='https://mastercaller.com/tournaments/european-championship/2026/results';
const auditedFetch=async(url,options)=>{const r=await fetch(url,options);console.log(JSON.stringify({page:new URL(url).pathname,status:r.status,type:r.headers.get('content-type')}));return r;};
const data=await fetchTournament(url,auditedFetch);
if(data.roster.length!==32||data.bracket.length!==31||data.rounds.length!==5)throw Error('Incomplete tournament');
console.log(JSON.stringify({verified:true,title:data.title,players:data.roster.length,matches:data.bracket.length,rounds:data.rounds.length,start:data.start_date,end:data.end_date,finished:data.records.length}));
