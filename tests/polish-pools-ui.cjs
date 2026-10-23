const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const root=path.join(__dirname,'..'),app=fs.readFileSync(path.join(root,'app.js'),'utf8');
 const pools=app.slice(app.indexOf('async function loadPrivatePools('),app.indexOf('// Replace the remaining tournament demo routes'));
 const binding=fs.readFileSync(path.join(root,'pool-invitations.js'),'utf8').replace('export function','function');
 const server=http.createServer((req,res)=>{if(req.url==='/styles.css'){res.setHeader('Content-Type','text/css');return res.end(fs.readFileSync(path.join(root,'styles.css')));}if(req.url==='/pool-fixture.js'){res.setHeader('Content-Type','text/javascript');return res.end(binding+'\n'+pools);}res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"></head><body><main class="layout"><div id="private-pools" class="stack"></div></main><script src="/pool-fixture.js"></script></body></html>');});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  browser=await chromium.launch({headless:true,executablePath:process.env.PREDICT_CHROMIUM,args:['--no-sandbox','--disable-gpu']});const page=await browser.newPage({viewport:{width:390,height:844}});const errors=[];page.on('pageerror',e=>errors.push(e.message));let allow=true;page.on('dialog',d=>allow?d.accept():d.dismiss());
  await page.addInitScript(()=>{
   window.currentUser={id:'owner'};window.currentRole='user';window.pending=false;window.calls=[];
   window.esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
   const pool={id:'pool',name:'Darts met vrienden',tournament_id:'t',owner_id:'owner'};
   window.supabase={from(table){let filters={},one=false;const q={select(){return q},eq(k,v){filters[k]=v;return q},order(){return q},single(){one=true;return q},then(ok){let data=table==='pools'?[pool]:table==='pool_members'?filters.pool_id?[{user_id:'owner'},{user_id:'member'}]:[{pool_id:'pool'}]:table==='tournaments'?[{id:'t',name:'European Championship',status:'published'}]:[];return Promise.resolve({data:one?data[0]:data}).then(ok)}};return q;},async rpc(name,args){calls.push([name,args]);if(name==='get_my_pool_invitations')return {data:pending?[{id:'inv',pool_id:'pool',pool_name:'Dartsuitnodiging',tournament_id:'t',tournament_name:'European Championship'}]:[]};if(name==='get_tournament_leaderboard')return {data:[{user_id:'owner',display_name:'Dani',rank_position:1,earned_points:10,correct_winners:2},{user_id:'member',display_name:'Een heel lange gebruikersnaam <img src=x>',rank_position:2,earned_points:5,correct_winners:1}]};if(name==='respond_pool_invitation')pending=false;return {data:true};}};
  });
  await page.goto('http://127.0.0.1:'+server.address().port);await page.evaluate(()=>loadPrivatePools(document.querySelector('#private-pools'),'t'));
  assert.equal(await page.locator('[aria-label="Poule-uitnodigingen"]').count(),0);assert.equal(await page.getByText('Geen openstaande uitnodigingen.').count(),0);
  assert((await page.locator('#private-create-form').boundingBox()).height<250);assert((await page.locator('.pool-card').boundingBox()).height<230);
  await page.locator('[data-pool-detail]').click();await page.locator('.pool-members-table').waitFor();assert.equal(await page.locator('.pool-members-table tbody tr').count(),2);assert.equal(await page.locator('[data-remove-member]').count(),1);assert.equal(await page.locator('[data-transfer-member]').count(),1);assert.equal(await page.locator('img').count(),0);
  for(const [width,height] of [[320,844],[390,844],[768,1024],[1024,768],[1024,1366],[1366,1024],[1280,800]])for(const dark of [false,true]){
   await page.setViewportSize({width,height});await page.evaluate(dark=>document.body.classList.toggle('dark',dark),dark);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Page overflow '+width+'/'+dark);
   const table=await page.locator('.pool-members-table').boundingBox();assert(table.x+table.width<=width+1,'Member table must fit');
   const h=await page.locator('[data-remove-member]').evaluate(e=>e.getBoundingClientRect().height);assert(h>=32&&h<=36,'Compact actions retain useful targets');
  }
  await page.setViewportSize({width:390,height:844});await fs.promises.mkdir(path.join(root,'test-results'),{recursive:true});await page.screenshot({path:path.join(root,'test-results/compact-pool-members-dark.png'),fullPage:true});await page.evaluate(()=>document.body.classList.remove('dark'));await page.screenshot({path:path.join(root,'test-results/compact-pool-members-light.png'),fullPage:true});
  allow=false;await page.locator('[data-remove-member]').click();assert.equal(await page.evaluate(()=>calls.filter(c=>c[0]==='manage_pool_member').length),0);
  allow=true;await page.locator('[data-transfer-member]').click();await page.locator('[data-pool-detail]').waitFor();assert(await page.evaluate(()=>calls.some(([n,a])=>n==='manage_pool_member'&&a.p_action==='transfer'&&a.p_user_id==='member'&&a.p_pool_id==='pool')));
  await page.evaluate(()=>{pending=true;return loadPrivatePools(document.querySelector('#private-pools'));});await page.locator('[data-accept-invitation]').waitFor();await page.locator('[data-decline-invitation]').click();await page.locator('[data-pool-detail]').waitFor();assert.equal(await page.locator('[aria-label="Poule-uitnodigingen"]').count(),0);
  await page.evaluate(()=>{currentUser={id:'member'};return loadPrivatePools(document.querySelector('#private-pools'));});await page.locator('[data-pool-detail]').click();await page.locator('.pool-members-table').waitFor();assert.equal(await page.locator('[data-remove-member],[data-transfer-member]').count(),0);
  assert.deepEqual(errors,[]);console.log('PASS: hidden empty invitations, compact cards/forms, safe member table, small actions, confirmation and transfer RPC, invitation response, non-owner restrictions, mobile/tablet/desktop light and dark without overflow.');
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
