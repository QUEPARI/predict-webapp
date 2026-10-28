const {chromium}=require('playwright'),http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert/strict');
(async()=>{
 const server=http.createServer((req,res)=>{if(req.url.startsWith('/source-draft-management.js')){res.setHeader('Content-Type','text/javascript');res.end(fs.readFileSync(path.join(__dirname,'../source-draft-management.js')));}else res.end('<html><body><div id="target"></div></body></html>');});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
 browser=await chromium.launch({headless:true,executablePath:process.env.PREDICT_CHROMIUM,args:['--no-sandbox']});const page=await browser.newPage({viewport:{width:390,height:844}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:'+server.address().port);
 async function setup(state,dirty=false){await page.evaluate(async({state,dirty})=>{
  const {sourceDraftPanel,bindSourceDraft}=await import('/source-draft-management.js');
  const t={id:'t',status:'draft',start:'2026-11-14',end:'2026-11-22',score_source:{locked:true,setup_pending:true,setup_state:state,format_required:true,setup_error:state==='error'?'HTTP 418':null}};
  const host=document.querySelector('#target');host.innerHTML=sourceDraftPanel(t);host.dataset.koDirty=String(dirty);window.calls=[];window.refreshed=0;window.fail=false;let busy=false;
  bindSourceDraft(host,t,{alive:()=>true,isBusy:()=>busy,onBusy:x=>busy=x,refresh:async()=>refreshed++,rpc:async(n,args)=>{calls.push([n,args]);if(n==='admin_source_draft_preview')return {rounds:[{order:1,name:'Groups',first_to:null},{order:2,name:'Final',first_to:8}],matches:[{round:1,group:'A',home_name:'Alice',away_name:'Bob'}]};if(window.fail)throw Error('Save failed');return true;}});
 },{state,dirty});}
 await setup('waiting');assert.equal(await page.locator('[data-review-source]').count(),0);assert.equal((await page.evaluate(()=>calls)).length,0);
 await page.locator('[data-source-action="announce"]').click();assert.equal((await page.evaluate(()=>calls))[0][1].p_action,'announce');assert.equal(await page.evaluate(()=>refreshed),1);
 await setup('error');assert.match(await page.locator('#target').innerText(),/HTTP 418/);assert.equal(await page.locator('[data-review-source]').count(),0);
 await setup('ready');assert.equal((await page.evaluate(()=>calls)).length,0,'Readiness never auto publishes');await page.locator('[data-review-source]').click();await page.locator('[data-publish-source]').waitFor();assert.match(await page.locator('[data-source-review]').innerText(),/Alice/);
 await page.locator('[data-publish-source] button').click();assert.equal((await page.evaluate(()=>calls)).length,1,'Missing source format must be entered');
 await page.locator('[name=firstTo]').fill('5');await page.locator('[data-publish-source] button').click();const action=(await page.evaluate(()=>calls)).at(-1);assert.equal(action[0],'admin_source_lifecycle');assert.equal(action[1].p_action,'publish');assert.equal(action[1].p_group_first_to,5);
 await setup('ready',true);await page.locator('[data-source-action="announce"]').click();assert.equal((await page.evaluate(()=>calls)).length,0,'Unsaved points/metadata block transitions');
 await setup('ready');await page.evaluate(()=>fail=true);await page.locator('[data-source-action="announce"]').click();assert.match(await page.locator('[data-lifecycle-message]').innerText(),/Save failed/);assert.equal(await page.locator('[data-source-action="announce"]').isEnabled(),true);
 assert.deepEqual(errors,[]);console.log('PASS persistent readiness/errors, explicit preview/publication, format required, unsaved edits protected, retry after errors.');
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
