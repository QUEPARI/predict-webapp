import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import webpush from 'npm:web-push@3.6.7';

// This worker has its own secret authentication, not an anonymous/user JWT.
const allowed=(endpoint:string)=>{
 try{const u=new URL(endpoint);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&!u.hash&&
 /^(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)$/.test(u.hostname);}catch{return false;}
};
async function equalSecret(a:string,b:string){
 const digest=async(v:string)=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v)));
 const [x,y]=await Promise.all([digest(a),digest(b)]);let difference=0;for(let i=0;i<x.length;i++)difference|=x[i]^y[i];return difference===0;
}
export async function handle(req:Request){
 if(req.method!=='POST')return new Response(null,{status:405});
 const supplied=req.headers.get('x-push-worker')||'';
 if(!/^[A-Za-z0-9_-]{43}$/.test(supplied))return new Response(null,{status:401});
 try{
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const config=await db.rpc('push_worker_configuration');
  if(config.error||!config.data?.enabled||!config.data?.worker_token||!config.data?.private_key||!config.data?.public_key)return new Response(null,{status:503});
  if(!await equalSecret(supplied,config.data.worker_token))return new Response(null,{status:401});
  webpush.setVapidDetails('https://quepari.github.io/predict-webapp/',config.data.public_key,config.data.private_key);
  const {data,error}=await db.rpc('claim_push_deliveries');if(error)throw new Error('claim');
  let sent=0,failed=0;
  // Claim <=25, send in groups of five; keep CPU/network/time bounded.
  for(let i=0;i<data.length;i+=5){await Promise.all(data.slice(i,i+5).map(async(d:any)=>{
   let status=400;
   if(allowed(d.endpoint))try{
    const r=await webpush.sendNotification({endpoint:d.endpoint,keys:{p256dh:d.p256dh,auth:d.auth}},JSON.stringify(d.payload),{TTL:Math.min(86400,d.ttl),urgency:'normal',timeout:8000});status=r.statusCode;
   }catch(e:any){status=Number.isInteger(e.statusCode)?e.statusCode:503;}
   const done=await db.rpc('finish_push_delivery',{p_id:d.id,p_lease:d.lease,p_status:status});
   if(done.error)throw new Error('ack');
   if(status>=200&&status<300)sent++;else failed++;
  }));}
  return Response.json({processed:data.length,sent,failed},{headers:{'Cache-Control':'no-store'}});
 }catch{return Response.json({error:'Verzending tijdelijk niet beschikbaar'},{status:503});}
}
Deno.serve(handle);
