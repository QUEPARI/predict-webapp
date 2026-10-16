import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import {readDarts,validDate} from './darts-data.js';
const origin='https://quepari.github.io';
const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
export async function handle(req:Request){
  if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return new Response(null,{status:403,headers});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return new Response(null,{status:405,headers});
  const authorization=req.headers.get('authorization')||'';
  const url=Deno.env.get('SUPABASE_URL')!;
  const user=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const auth=await user.auth.getUser();if(auth.error||!auth.data.user)return Response.json({error:'Inloggen vereist'},{status:401,headers});
  const role=await user.from('user_roles').select('role').eq('user_id',auth.data.user.id).single();
  if(role.error||!['admin','super_admin'].includes(role.data?.role))return Response.json({error:'Geen beheerdersrechten'},{status:403,headers});
  let scope;
  try{
    const text=await req.text();if(text.length>2048)throw Error();scope=JSON.parse(text);
    if(!/^[0-9a-f-]{36}$/i.test(scope.tournament_id)||!['fixtures','results'].includes(scope.kind)||typeof scope.competition!=='string'||!scope.competition.trim()||scope.competition.length>120||!validDate(scope.from)||!validDate(scope.to)||scope.from>scope.to||(Date.parse(scope.to)-Date.parse(scope.from))/86400000>31)throw Error();
  }catch{return Response.json({error:'Kies een toernooi, bronnaam en geldige periode van maximaal 32 dagen'},{status:400,headers});}
  const key=Deno.env.get('DARTS_API_KEY');if(!key)return Response.json({error:'DartsAPI-sleutel ontbreekt in de backend'},{status:503,headers});
  const started=await user.rpc('begin_darts_import',{p_tournament_id:scope.tournament_id,p_kind:scope.kind});
  if(started.error)return Response.json({error:'Import niet gestart. Controleer het dartstoernooi en wacht minstens een minuut tussen imports (maximaal twaalf per uur).'},{status:409,headers});
  const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  try{
    const data=await readDarts(fetch,key,scope);
    const saved=await admin.rpc('finish_darts_import',{p_run_id:started.data,p_actor:auth.data.user.id,p_items:data.items});
    if(saved.error)throw Error('invalid_data');
    return Response.json({...saved.data,pages:data.pages,source_rows:data.fetched,run_id:started.data},{headers});
  }catch(error){
    const code=error instanceof Error&&['rate_limited','invalid_data'].includes(error.message)?error.message:'upstream_error';
    await admin.rpc('finish_darts_import',{p_run_id:started.data,p_actor:auth.data.user.id,p_items:[],p_error:code});
    return Response.json({error:code==='rate_limited'?'DartsAPI-limiet bereikt. Probeer later opnieuw.':'Import afgebroken: brongegevens of paginering zijn niet volledig geldig. Er zijn geen voorstellen opgeslagen.'},{status:502,headers});
  }
}
Deno.serve(handle);
