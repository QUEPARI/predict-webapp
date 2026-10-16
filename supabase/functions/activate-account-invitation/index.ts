import { createClient } from 'npm:@supabase/supabase-js@2.118.0';

const origin = 'https://quepari.github.io';
const redirectTo = origin + '/predict-webapp/account.html';
const cors = {'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
// Anonymous endpoint authenticated by a 256-bit invitation capability, not a user JWT.
// No arbitrary addresses or redirects are passed to Auth before the DB verifies the capability.
export async function handle(req: Request) {
  if(req.headers.get('origin') && req.headers.get('origin')!==origin) return new Response(null,{status:403,headers:cors});
  if(req.method==='OPTIONS') return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST') return new Response(null,{status:405,headers:cors});
  const reply=()=>Response.json({success:true},{headers:cors});
  try {
    const text=await req.text();if(text.length>2048)return reply();
    const input=JSON.parse(text);
    if(typeof input?.token!=='string'||!/^[0-9a-f]{64}$/.test(input.token)||typeof input.email!=='string'||input.email.length>254)return reply();
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data:email,error}=await admin.rpc('reserve_account_invitation_mail',{p_token:input.token,p_email:input.email});
    if(error) return Response.json({error:'Tijdelijk niet beschikbaar'},{status:503,headers:cors});
    if(!email)return reply();
    // Native Auth email confirms ownership. Never expose its tokens, user ID or errors.
    await admin.auth.admin.inviteUserByEmail(email,{redirectTo});
    return reply();
  }catch{return reply();}
}
Deno.serve(handle);
