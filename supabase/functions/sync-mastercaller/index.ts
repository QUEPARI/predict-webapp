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
  if(input.action==='preview'){
   const parsed=await fetchTournament(input.url);
   return reply({title:parsed.title,rounds:parsed.rounds,count:parsed.records.length,participants:parsed.roster.length});
  }
  if(!worker&&input.action==='create'){
   const snapshot=await fetchTournament(input.url);
   const userDb=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:'Bearer '+sessionToken}},auth:{persistSession:false,autoRefreshToken:false}});
   const created=await userDb.rpc('create_mastercaller_game',{p_snapshot:snapshot,p_name:input.name||null,p_winner:input.winner_points??1,p_exact:input.exact_points??3,p_mode:input.mode||'replacement'});
   if(created.error)return reply({error:created.error.message},400);
   return reply({id:created.data,name:input.name||snapshot.title+' '+new URL(snapshot.url).pathname.split('/')[3],participants:snapshot.roster.length,matches:snapshot.bracket.length});
  }
  if(!worker&&!/^[a-f0-9-]{36}$/i.test(input.tournament_id||''))return reply({error:'Kies een toernooi'},400);
  const claim=await db.rpc('claim_mastercaller_jobs',{p_tournament:worker?null:input.tournament_id,p_actor:actor});
  if(claim.error)return reply({error:'Ophalen niet gestart. Controleer de broninstelling.'},400);
  if(!claim.data.length)return reply({message:'Nog niet opnieuw beschikbaar. Wacht één minuut, of controleer of Mastercaller is ingesteld.',processed:0});
  const reports=[];
  for(const job of claim.data){
   let parsed:any=null,error:string|null=null;
   try{parsed=await (job.automatic_setup?fetchTournament(job.url):fetchResults(job.url));}catch(e){error=e instanceof Error?e.message:'Bron niet bereikbaar';}
   const done=await db.rpc('finish_mastercaller_job',{p_tournament:job.tournament_id,p_lease:job.lease,p_records:parsed?.records||[],p_error:error,p_snapshot:job.automatic_setup?parsed:null});
   if(done.error)throw Error('Verwerking niet afgerond; probeer later opnieuw.');
   reports.push(done.data);
  }
  return reply({processed:reports.length,reports});
 }catch(e){return reply({error:e instanceof Error?e.message:'Ophalen mislukt'},400);}
}
// Own authentication: validated admin JWT or a Vault-backed worker secret above.
Deno.serve(handle);
