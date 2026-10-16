import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const origin='https://quepari.github.io';
const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
// This anonymous endpoint authenticates a single-use 256-bit capability in the DB.
export async function handle(req:Request){
  if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return new Response(null,{status:403,headers});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return new Response(null,{status:405,headers});
  const denied=()=>Response.json({error:'Code ongeldig, verlopen of al gebruikt. Vraag zo nodig een nieuwe code aan de beheerder.'},{status:400,headers});
  try{
    const body=await req.text();if(body.length>2048)return denied();
    const input=JSON.parse(body);
    if(typeof input.username!=='string'||input.username.length>128||!['activate','reset'].includes(input.kind)||
      typeof input.code!=='string'||!/^[0-9a-f]{64}$/.test(input.code)||typeof input.password!=='string'||input.password.length<12||input.password.length>128)return denied();
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
    const claim=await admin.rpc('claim_manual_account_code',{p_username:input.username,p_kind:input.kind,p_token:input.code});
    if(claim.error||!claim.data)return denied();
    const c=claim.data;
    if(input.kind==='activate'){
      const r=await admin.auth.admin.createUser({id:c.user_id,email:c.email,password:input.password,email_confirm:true});
      if(r.error||r.data.user?.id!==c.user_id)return denied();
      // Provisioning of username/profile/user role is atomic with Auth insertion via trigger.
    }else{
      const r=await admin.auth.admin.updateUserById(c.user_id,{password:input.password});if(r.error)return denied();
      const done=await admin.rpc('complete_manual_password_reset',{p_code_id:c.code_id});if(done.error)return denied();
    }
    return Response.json({success:true},{headers});
  }catch{return denied();}
}
Deno.serve(handle);
