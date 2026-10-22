import {createClient} from '@supabase/supabase-js';
import {fetchResults,fetchTournament} from './parser.js';

const headers={'Access-Control-Allow-Origin':'https://quepari.github.io','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Cache-Control':'no-store'};
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers});
export async function handle(req:Request){
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'Gebruik POST'},405);
 const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  let actor:string|null=null,sessionToken:string|null=null;
  const worker=req.headers.get('x-mastercaller-worker');
  if(worker){
   if(!/^[a-f0-9]{64}$/.test(worker))return reply({error:'Niet bevoegd'},401);
   const check=await db.rpc('verify_mastercaller_worker',{p_token:worker});
   if(check.error||check.data!==true)return reply({error:'Niet bevoegd'},401);
  }else{
   const token=req.headers.get('authorization')?.replace(/^Bearer /,'');
   if(!token)return reply({error:'Log opnieuw in'},401);
   const user=await db.auth.getUser(token);if(user.error||!user.data.user)return reply({error:'Log opnieuw in'},401);
   actor=user.data.user.id;
   sessionToken=token;
   const role=await db.from('user_roles').select('role').eq('user_id',actor).maybeSingle();
   if(role.error||!['admin','super_admin'].includes(role.data?.role))return reply({error:'Geen beheerdersrechten'},403);
  }
  const body=await req.text();if(body.length>2000)return reply({error:'Verzoek te groot'},400);
  const input=JSON.parse(body||'{}');
  if(worker)return reply({message:'Ophalen loopt nu via GitHub Actions.',processed:0});
  const userDb=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:'Bearer '+sessionToken}},auth:{persistSession:false,autoRefreshToken:false}});
  if(input.action==='create'){
   const result=await userDb.rpc('request_mastercaller_game',{p_url:input.url,p_name:input.name||null,p_winner:input.winner_points??1,p_exact:input.exact_points??3,p_mode:input.mode||'replacement'});
   if(result.error)return reply({error:result.error.message},400);return reply(result.data);
  }
  if(!/^[a-f0-9-]{36}$/i.test(input.tournament_id||''))return reply({error:'Kies een toernooi'},400);
  // A manual click performs the fetch now; it must not report a queued job as completed.
  // The same claim/lease as the scheduled worker prevents duplicate source requests.
  const claimed=await db.rpc('claim_mastercaller_jobs',{p_tournament:input.tournament_id,p_actor:actor});
  if(claimed.error)return reply({error:claimed.error.message},400);
  const job=claimed.data?.[0];
  if(!job){
   const state=await userDb.rpc('get_tournament_score_source',{p_tournament:input.tournament_id});
   if(state.error)return reply({error:state.error.message},400);
   return reply({error:state.data?.stopped?'De finale is afgerond; ophalen is gestopt.':state.data?.source!=='mastercaller_test'?'Dit toernooi heeft geen Mastercaller-bron.':'Er loopt al een ophaalactie of er is minder dan één minuut geleden opgehaald. Probeer het over één minuut opnieuw.'},409);
  }
  let snapshot=null,records=[],sourceError=null;
  try{
   const data=await(job.automatic_setup?fetchTournament(job.url):fetchResults(job.url));
   records=data.records;snapshot=job.automatic_setup?data:null;
  }catch(e){
   sourceError=e instanceof Error?e.message:'Mastercaller ophalen mislukt.';
   if(e instanceof Error&&['TimeoutError','AbortError'].includes(e.name))sourceError='Mastercaller reageert niet binnen 15 seconden. Er zijn geen nieuwe gegevens verwerkt.';
   else if(e instanceof TypeError)sourceError='Verbinding met Mastercaller mislukt. Er zijn geen nieuwe gegevens verwerkt.';
  }
  const finished=await db.rpc('finish_mastercaller_job',{p_tournament:job.tournament_id,p_lease:job.lease,p_records:records,p_error:sourceError,p_snapshot:snapshot});
  if(finished.error)return reply({error:'Verwerken van de brongegevens mislukt: '+finished.error.message},500);
  if(sourceError||finished.data?.error)return reply({error:sourceError||finished.data.error},502);
  return reply({status:'completed',...finished.data});
 }catch(e){return reply({error:e instanceof Error?e.message:'Ophalen mislukt'},400);}
}
// Own authentication: validated admin JWT or a Vault-backed worker secret above.
Deno.serve(handle);
