import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const origin='https://quepari.github.io';
const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
// Password authentication stays with Supabase Auth. The service key only resolves a
// username privately; it is never used as a replacement for password verification.
export async function handle(req:Request){
  if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return new Response(null,{status:403,headers});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return new Response(null,{status:405,headers});
  const started=Date.now();
  const denied=async()=>{await new Promise(r=>setTimeout(r,Math.max(0,400-(Date.now()-started))));return Response.json({error:'Inloggen mislukt. Controleer je gegevens of probeer over vijftien minuten opnieuw.'},{status:401,headers});};
  try{
    const text=await req.text();if(text.length>2048)return denied();const input=JSON.parse(text);
    if(typeof input.username!=='string'||input.username.length>128||typeof input.password!=='string'||input.password.length<1||input.password.length>128)return denied();
    const url=Deno.env.get('SUPABASE_URL')!;
    const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
    const lookup=await admin.rpc('resolve_username_login',{p_username:input.username});if(lookup.error||!lookup.data)return denied();
    const auth=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
    const login=await auth.auth.signInWithPassword({email:lookup.data,password:input.password});
    if(login.error||!login.data.session)return denied();
    return Response.json({access_token:login.data.session.access_token,refresh_token:login.data.session.refresh_token},{headers});
  }catch{return denied();}
}
Deno.serve(handle);
