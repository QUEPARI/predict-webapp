const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {stripTypeScriptTypes}=require('node:module');
function load(name,createClient){
  let handler;
  const source=stripTypeScriptTypes(fs.readFileSync(path.join(__dirname,'../supabase/functions',name,'index.ts'),'utf8')).replace(/^import .*?;\s*/m,'').replace('export async function','async function');
  vm.runInNewContext(source,{Request,Response,createClient,console,Deno:{env:{get:()=> 'fictitious-env'},serve:f=>handler=f}});
  return handler;
}
(async()=>{
  const calls=[];let email=null,rpcError=null,authError=null;
  const activate=load('activate-account-invitation',()=>({rpc:async(...args)=>{calls.push(['rpc',...args]);return {data:email,error:rpcError};},auth:{admin:{inviteUserByEmail:async(...args)=>{calls.push(['mail',...args]);return {error:authError};}}}}));
  const request=(body,origin='https://quepari.github.io',method='POST')=>new Request('https://fictitious.invalid',{method,headers:{origin,'Content-Type':'application/json'},...(method==='POST'?{body:JSON.stringify(body)}:{})});
  assert.equal((await activate(request({},undefined,'OPTIONS'))).status,204);
  assert.equal((await activate(request({},'https://evil.invalid'))).status,403);
  assert.equal((await activate(request({},undefined,'GET'))).status,405);
  await activate(request({token:'bad',email:'qa@example.invalid'}));assert.equal(calls.length,0);
  const valid={token:'a'.repeat(64),email:'qa@example.invalid',redirectTo:'https://evil.invalid'};
  let response=await activate(request(valid));assert.equal(calls.length,1);assert.equal((await response.json()).success,true);
  email='qa@example.invalid';response=await activate(request(valid));assert.equal(calls.at(-1)[0],'mail');assert.equal(calls.at(-1)[2].redirectTo,'https://quepari.github.io/predict-webapp/account.html');
  authError={message:'User already registered'};assert.deepEqual(await(await activate(request(valid))).json(),{success:true});
  rpcError={message:'database offline'};assert.equal((await activate(request(valid))).status,503);
  let user=null;const rpcCalls=[];
  const create=load('create-invitation',()=>({auth:{getUser:async()=>({data:{user}})},rpc:async(...args)=>{rpcCalls.push(args);return {data:'b'.repeat(64)};}}));
  assert.equal((await create(request({email:'qa@example.invalid'}))).status,401);
  user={id:'fake-admin'};let output=await(await create(request({email:'qa@example.invalid'}))).json();
  assert.equal(rpcCalls[0][0],'create_account_invitation');assert(output.invitation_link.endsWith('#invite='+'b'.repeat(64)));
  output=await(await create(request({email:'qa@example.invalid',pool_id:'fake-pool'}))).json();assert.equal(rpcCalls[1][0],'invite_pool_member');assert.equal(output.invitation_code,'b'.repeat(64));
  console.log('Account Edge Function handler tests passed (mock Auth and database).');
})().catch(e=>{console.error(e);process.exitCode=1;});
