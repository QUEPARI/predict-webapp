// Email onboarding is paused. Manual username activation never sends email.
const headers={'Access-Control-Allow-Origin':'https://quepari.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'};
Deno.serve((req:Request)=>req.method==='OPTIONS'?new Response(null,{status:204,headers}):
  Response.json({error:'Gebruik een activatiecode van je beheerder. E-mailactivatie is voorlopig uitgeschakeld.'},{status:410,headers}));
