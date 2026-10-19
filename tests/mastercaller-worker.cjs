const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),{stripTypeScriptTypes}=require('node:module');
(async()=>{
 let handler,fetches=0,writes=0,verified=false,role='admin',claims=[];
 const db={auth:{getUser:async token=>token==='valid'?{data:{user:{id:'admin-id'}}}:{error:{message:'invalid'}}},from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{role}})})})}),rpc:async(name)=>{if(name==='request_mastercaller_game')return {data:{id:'created-id'}};if(name==='verify_mastercaller_worker')return {data:verified};if(name==='claim_mastercaller_jobs')return {data:claims};if(name==='finish_mastercaller_job'){writes++;return {data:{applied:1}};}return {data:'created-id'};}};
 const src=fs.readFileSync(require('path').join(__dirname,'../supabase/functions/sync-mastercaller/index.ts'),'utf8').replace(/^import .*;\n/gm,'').replace('export async function handle','async function handle');
 const context={createClient:()=>db,fetchResults:async()=>{fetches++;return {records:[]};},fetchTournament:async()=>{fetches++;return {title:'EC',url:'https://mastercaller.com/tournaments/european-championship/2026/results',rounds:[],roster:Array(32),bracket:Array(31)};},Deno:{env:{get:()=>''},serve:f=>handler=f},Response,Request,JSON,URL};
 vm.runInNewContext(stripTypeScriptTypes(src),context);
 assert.equal((await handler(new Request('https://example.test',{method:'OPTIONS'}))).status,204);
 assert.equal((await handler(new Request('https://example.test',{method:'POST',body:'{}'}))).status,401);
 assert.equal((await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer invalid'},body:'{}'}))).status,401);
 assert.equal((await handler(new Request('https://example.test',{method:'POST',headers:{'x-mastercaller-worker':'f'.repeat(64)},body:'{}'}))).status,401);
 role='user';assert.equal((await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer valid'},body:'{}'}))).status,403);assert.equal(fetches,0);assert.equal(writes,0);
 role='admin';let response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer valid'},body:JSON.stringify({action:'create',url:'https://mastercaller.com/tournaments/european-championship/2026/results'})}));assert.equal(response.status,200);assert.equal((await response.json()).id,'created-id');
 verified=true;claims=[{tournament_id:'t',lease:'lease',url:'url',automatic_setup:true}];response=await handler(new Request('https://example.test',{method:'POST',headers:{'x-mastercaller-worker':'f'.repeat(64)},body:'{}'}));assert.equal(response.status,200);assert.equal(writes,0);assert.equal(fetches,0);
 console.log('PASS: preflight, anonymous/invalid JWT/ordinary user/invalid worker denied before source access; authenticated queue request; legacy worker never fetches from Supabase.');
})().catch(e=>{console.error(e);process.exitCode=1;});
