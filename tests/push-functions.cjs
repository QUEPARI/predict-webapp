const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
(async()=>{
 const calls=[],deliveries=[201,410,429,503].map((status,i)=>({id:String(i),lease:'lease-'+i,endpoint:'https://fcm.googleapis.com/test-'+i,p256dh:'fake',auth:'fake',ttl:3600,payload:{title:'Test',body:'No real recipient'},status}));
 deliveries.push({...deliveries[0],id:'4',endpoint:'https://localhost/internal'});
 let handler,claimError=false;
 const db={rpc:async(name,args)=>{calls.push([name,args]);return name==='push_worker_configuration'?{data:{enabled:true,worker_token:env.PUSH_WORKER_TOKEN,public_key:env.PUSH_VAPID_PUBLIC_KEY,private_key:env.PUSH_VAPID_PRIVATE_KEY}}:name==='claim_push_deliveries'?{data:deliveries,error:claimError?{}:null}:{error:null};}};
 const env={PUSH_WORKER_TOKEN:'x'.repeat(43),PUSH_VAPID_PUBLIC_KEY:'public',PUSH_VAPID_PRIVATE_KEY:'private',SUPABASE_URL:'https://fake.invalid',SUPABASE_SERVICE_ROLE_KEY:'fake'};
 const source=stripTypeScriptTypes(fs.readFileSync('supabase/functions/send-push/index.ts','utf8')).replace(/^import .*;\s*$/gm,'').replace('export async function','async function');
 const pushCalls=[];
 vm.runInNewContext(source,{Request,Response,URL,crypto,TextEncoder,console,createClient:()=>db,webpush:{setVapidDetails:()=>{},sendNotification:async(sub,payload,options)=>{pushCalls.push([sub,JSON.parse(payload),options]);const status=deliveries.find(d=>d.endpoint===sub.endpoint).status;if(status!==201)throw {statusCode:status};return {statusCode:201};}},Deno:{env:{get:k=>env[k]},serve:f=>handler=f}});
 const request=(token=env.PUSH_WORKER_TOKEN,method='POST')=>new Request('https://fake.invalid',{method,headers:{'x-push-worker':token}});
 assert.equal((await handler(request('wrong'))).status,401);assert.equal(calls.length,0);
 assert.equal((await handler(request('y'.repeat(43)))).status,401);assert.equal(calls.length,1);assert.equal(calls[0][0],'push_worker_configuration');calls.length=0;
 assert.equal((await handler(request(undefined,'GET'))).status,405);
 const r=await handler(request());assert.equal(r.status,200);assert.deepEqual(await r.json(),{processed:5,sent:1,failed:4});assert.equal(pushCalls.length,4);assert.equal(calls.filter(x=>x[0]==='finish_push_delivery').length,5);
 assert.equal(calls.find(x=>x[1]?.p_id==='4')[1].p_status,400);assert.equal(pushCalls[0][2].timeout,8000);
 claimError=true;assert.equal((await handler(request())).status,503);
 env.PUSH_VAPID_PRIVATE_KEY='';assert.equal((await handler(request())).status,503);
 // Service worker never trusts a destination from a notification payload.
 const events={},shown=[],opened=[];let wait;
 vm.runInNewContext(fs.readFileSync('push-worker.js','utf8'),{URL,self:{addEventListener:(k,f)=>events[k]=f,skipWaiting:()=>{},registration:{scope:'https://example.test/predict-webapp/',showNotification:async(...x)=>shown.push(x)},clients:{claim:async()=>{},matchAll:async()=>[],openWindow:async url=>opened.push(url)}}});
 events.push({data:{json:()=>({title:'Nieuw spel',body:'Test',url:'https://evil.invalid'})},waitUntil:p=>wait=p});await wait;assert.equal(shown[0][0],'Nieuw spel');assert.equal(shown[0][1].data.url,'https://example.test/predict-webapp/');
 events.notificationclick({notification:{close(){}},waitUntil:p=>wait=p});await wait;assert.deepEqual(opened,['https://example.test/predict-webapp/']);
 console.log('PASS: worker secret authentication, bounded sends, HTTP outcomes, retry acknowledgement, endpoint defense and safe notification clicks');
})().catch(e=>{console.error(e);process.exitCode=1;});
