import {createClient} from '@supabase/supabase-js';
import {verifyGitHub} from './auth.js';
const reply=(b:unknown,s=200)=>Response.json(b,{status:s,headers:{'Cache-Control':'no-store'}});
export async function handle(req:Request){
 if(req.method!=='POST')return reply({error:'Gebruik POST'},405);
 try{await verifyGitHub(req.headers.get('authorization')?.replace(/^Bearer /,'')||'');}catch{return reply({error:'Niet bevoegd'},401);}
 const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const rpc=async(n:string,p?:any)=>{const r=await db.rpc(n,p);if(r.error)throw Error(r.error.message);return r.data;};
 try{
  const body=await req.text();if(body.length>1500000)return reply({error:'Verzoek te groot'},413);const input=JSON.parse(body);
  if(input.action==='claim'){
   const creations=await rpc('claim_mastercaller_creations');const scores=await rpc('claim_mastercaller_jobs',{p_tournament:null,p_actor:null});
   return reply({jobs:[...creations,...scores.map((j:any)=>({...j,kind:'scores'}))]});
  }
  if(input.action==='finish'){
   if(input.kind==='create')return reply(await rpc('finish_mastercaller_creation',{p_job:input.job_id,p_lease:input.lease,p_snapshot:input.snapshot||null,p_error:input.error||null}));
   if(input.kind==='scores'){
    const result=await rpc('finish_mastercaller_job',{p_tournament:input.tournament_id,p_lease:input.lease,p_records:input.records||[],p_error:input.error||null,p_snapshot:input.snapshot||null});
    if(input.snapshot&&!input.error)await rpc('cache_mastercaller_snapshot',{p_snapshot:input.snapshot});return reply(result);
   }
  }
  if(input.action==='cache'&&input.snapshot)return reply({cached:await rpc('cache_mastercaller_snapshot',{p_snapshot:input.snapshot})});
  return reply({error:'Onbekende actie'},400);
 }catch(e){return reply({error:e instanceof Error?e.message:'Verwerking mislukt'},400);}
}
Deno.serve(handle);
