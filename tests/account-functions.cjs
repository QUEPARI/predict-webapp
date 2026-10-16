const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {stripTypeScriptTypes}=require('node:module');
function load(name,createClient){
  let handler;
  const source=stripTypeScriptTypes(fs.readFileSync(path.join(__dirname,'../supabase/functions',name,'index.ts'),'utf8')).replace(/^import .*?;\s*/m,'').replace('export async function','async function');
  vm.runInNewContext(source,{Request,Response,URLSearchParams,createClient,console,setTimeout,clearTimeout,Deno:{env:{get:key=>key},serve:f=>handler=f}});
  return handler;
}
(async()=>{
  const calls=[];let claim={user_id:'fake-id',code_id:'fake-code-id',email:'fake-id@accounts.predict.invalid'},fail=false;
  const admin={rpc:async(name,args)=>{calls.push(['rpc',name,args]);return {data:claim};},auth:{admin:{
    createUser:async args=>{calls.push(['create',args]);return {data:{user:{id:args.id}},error:fail?{}:null};},
    updateUserById:async(...args)=>{calls.push(['update',...args]);return {error:fail?{}:null};}
  }}};
  const manual=load('manual-account',()=>admin);
  const request=(body,origin='https://quepari.github.io',method='POST')=>new Request('https://fictitious.invalid',{method,headers:{origin,'Content-Type':'application/json'},...(method==='POST'?{body:JSON.stringify(body)}:{})});
  const valid={username:'qa-user',kind:'activate',code:'a'.repeat(64),password:'fictitious-password'};
  assert.equal((await manual(request({},undefined,'OPTIONS'))).status,204);
  assert.equal((await manual(request(valid,'https://evil.invalid'))).status,403);
  assert.equal((await manual(request({...valid,password:'short'}))).status,400);assert.equal(calls.length,0);
  assert.equal((await manual(request(valid))).status,200);
  assert(calls.some(x=>x[0]==='create'&&x[1].id==='fake-id'&&x[1].email_confirm===true));
  calls.length=0;await manual(request({...valid,kind:'reset'}));
  assert(calls.some(x=>x[0]==='update'&&x[1]==='fake-id'));
  assert(calls.some(x=>x[1]==='complete_manual_password_reset'));
  claim=null;calls.length=0;assert.equal((await manual(request(valid))).status,400);assert(!calls.some(x=>x[0]==='create'));
  let resolved='hidden@example.invalid';
  const login=load('username-login',(_,key)=>key==='SUPABASE_SERVICE_ROLE_KEY'?{rpc:async()=>({data:resolved})}:{auth:{signInWithPassword:async args=>{calls.push(['login',args]);return args.password==='correct'?{data:{session:{access_token:'fake-access',refresh_token:'fake-refresh'}}}:{error:{}};}}});
  assert.equal((await login(request({username:'qa-user',password:'wrong'}))).status,401);
  const success=await(await login(request({username:'QA-USER',password:'correct'}))).json();assert.deepEqual(success,{access_token:'fake-access',refresh_token:'fake-refresh'});
  resolved=null;assert.equal((await login(request({username:'unknown',password:'correct'}))).status,401);
  assert(!JSON.stringify(success).includes('hidden@example.invalid'));
  let currentUser=null;const issued=[];
  const legacy=load('create-invitation',()=>({auth:{getUser:async()=>({data:{user:currentUser}})},rpc:async(...args)=>{issued.push(args);return {data:'b'.repeat(64)};}}));
  assert.equal((await legacy(request({username:'qa-user'}))).status,401);currentUser={id:'fake-admin'};
  assert.equal((await legacy(request({email:'old@example.invalid'}))).status,400);
  const issuedLink=await(await legacy(request({username:'qa-user',kind:'reset'}))).json();assert(issuedLink.invitation_link.includes('kind=reset'));assert.equal(issued[0][0],'issue_manual_account_code');
  await legacy(request({pool_id:'fake-pool',username:'qa-user'}));assert.equal(issued[1][0],'invite_pool_member');
  const paused=load('activate-account-invitation',()=>{throw Error('No mail client should be initialized');});assert.equal((await paused(request({}))).status,410);
  console.log('PASS: manual account and username login handlers, validation, password verification, code authorization, reset and CORS.');
})().catch(e=>{console.error(e);process.exitCode=1;});
