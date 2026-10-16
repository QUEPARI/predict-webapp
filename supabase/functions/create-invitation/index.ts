import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const origin='https://quepari.github.io';
const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
Deno.serve(async(req:Request)=>{
  if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return new Response(null,{status:403,headers});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return new Response(null,{status:405,headers});
  const authorization=req.headers.get('authorization')||'';
  const user=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const auth=await user.auth.getUser();if(auth.error||!auth.data.user)return Response.json({error:'Inloggen vereist'},{status:401,headers});
  try{
    const body=await req.json();if(typeof body.email!=='string'||body.email.length>254)return Response.json({error:'Ongeldig adres'},{status:400,headers});
    // Reuse exactly the controlled DB paths. The legacy endpoint cannot bypass the account budget.
    const pool=body.pool_id!=null;
    const result=await user.rpc(pool?'invite_pool_member':'create_account_invitation',pool?{p_pool_id:body.pool_id,p_email:body.email}:{p_email:body.email});
    if(result.error)return Response.json({error:'Uitnodiging geweigerd'},{status:403,headers});
    const invitation_link=pool?null:origin+'/predict-webapp/account.html#invite='+result.data;
    return Response.json({success:true,invitation_link,invitation_code:pool?result.data:undefined,expires_in_days:7},{headers});
  }catch{return Response.json({error:'Ongeldige aanvraag'},{status:400,headers});}
});
