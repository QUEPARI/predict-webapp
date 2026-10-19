import {createClient} from '@supabase/supabase-js';

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
  const result=await userDb.rpc('request_mastercaller_refresh',{p_id:input.tournament_id});
  if(result.error)return reply({error:result.error.message},400);return reply(result.data);
 }catch(e){return reply({error:e instanceof Error?e.message:'Ophalen mislukt'},400);}
}
// Own authentication: validated admin JWT or a Vault-backed worker secret above.
Deno.serve(handle);
