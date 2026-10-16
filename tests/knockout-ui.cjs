const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const vm=require('node:vm');
 for(const file of ['sync-darts-data','sync-darts-fixtures']){
   let handler;vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../supabase/functions',file,'index.ts'),'utf8'),{Deno:{serve:f=>handler=f},Response,fetch:()=>{throw Error('Unexpected provider call');}});
   assert.equal(handler({method:'POST'}).status,410);assert.equal(handler({method:'OPTIONS'}).status,204);
 }
 const helpers=await import('../knockout.js');
 assert.equal(helpers.dutchToUTC('2026-10-16T22:00'),'2026-10-16T20:00:00.000Z');
 assert.equal(helpers.dutchToUTC('2026-12-16T22:00'),'2026-12-16T21:00:00.000Z');
 assert.throws(()=>helpers.dutchToUTC('2026-03-29T02:30'),/bestaat niet/);assert.throws(()=>helpers.dutchToUTC('2026-10-25T02:30'),/tweemaal/);
 const server=http.createServer((req,res)=>{if(['/knockout.js','/styles.css'].includes(req.url)){res.setHeader('Content-Type',req.url.endsWith('.js')?'text/javascript':'text/css');res.end(fs.readFileSync(path.join(__dirname,'..',req.url)));}else res.end('<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"></head><body><main id="target" class="layout"></main><script type="module">import {loadKnockoutAdmin} from "/knockout.js";window.ab=new AbortController();loadKnockoutAdmin(document.getElementById("target"),{supabase:window.mock,signal:ab.signal,isCurrent:()=>true});</script></body></html>');});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  browser=await chromium.launch({headless:true,channel:'msedge'});const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
  await page.addInitScript(()=>{window.calls=[];window.qaError=false;const data={name:'QA toernooi',status:'draft',roster:['QA A','QA B','QA C'],server_now:'2026-10-16T10:00:00Z',rounds:[{id:'r1',name:'Halve finales',order:1},{id:'r2',name:'Finale',order:2}],matches:[{id:'bye',number:1,round:1,home:'QA A',away:'Vrijgesteld',bye:true},{id:'m',number:2,round:1,home:'QA <img src=x> B',away:'QA C',home_slot:2,away_slot:3,unit:'legs',first_to:6,status:'scheduled',start:'2026-10-16T09:00:00Z'},{id:'f',number:3,round:2,home:'QA A',away:'Winnaar wedstrijd 2',home_slot:1,unit:'sets',first_to:3,status:'scheduled'}]};window.mock={rpc:async(name,args)=>{calls.push([name,args]);if(name==='knockout_catalog')return {data:{sports:[{id:'s',name:'Darts',slug:'darts'}],tournaments:[{id:'t',name:'QA toernooi'}]}};if(name==='create_knockout_tournament')return {data:'t'};if(name==='get_knockout_schema')return {data};if(name==='edit_knockout'){if(qaError)return {error:{message:'QA fout'}};if(args.p_action==='publish')data.status='published';return {data:true};}return {data:null};}};});
  await page.goto('http://127.0.0.1:'+server.address().port);await page.getByText('Nieuw knock-outtoernooi',{exact:true}).click();const f=page.locator('#ko-create form');
  await f.getByLabel('Toernooinaam',{exact:true}).fill('QA nieuw');await f.getByLabel('Aantal deelnemers').fill('3');await f.getByLabel('Aantal deelnemers').press('Tab');await f.getByLabel('Namen in lotingsvolgorde, één per regel').fill('QA A\nQA B\nQA C');await f.getByLabel('Toernooistart (Nederland)').fill('2026-12-01T19:00');
  for(const fieldset of await f.locator('fieldset').all()){await fieldset.getByLabel('First-to').fill('6');await fieldset.getByLabel('Punten juiste winnaar').fill('1');await fieldset.getByLabel('Punten exacte score').fill('3');}
  await f.getByRole('button',{name:'Concepttoernooi en schema maken'}).click();await page.getByRole('heading',{name:'Volledig toernooischema'}).waitFor();assert.equal(await page.locator('article img').count(),0);
  assert.equal(await page.evaluate(()=>calls.find(x=>x[0]==='create_knockout_tournament')[1].p_roster.length),3);
  await page.locator('#ko-filter').selectOption('Uitslag nodig');assert.equal(await page.locator('#ko-cards article:visible').count(),1);
  const match=page.locator('#ko-cards article').nth(1);await match.getByLabel('Reden voor wijziging / vrijgave').fill('QA reden');await page.evaluate(()=>qaError=true);await match.getByRole('button',{name:'Datum en spelvorm opslaan'}).click();await page.getByText('QA fout',{exact:true}).waitFor();assert.equal(await match.getByLabel('Reden voor wijziging / vrijgave').inputValue(),'QA reden');
  const overflow=await page.evaluate(()=>[...document.querySelectorAll('body *')].filter(e=>e.getBoundingClientRect().right>innerWidth+1).map(e=>({tag:e.tagName,cls:e.className,id:e.id,width:e.getBoundingClientRect().width})).slice(0,12));
  if(overflow.length)console.log(overflow);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert.deepEqual(errors,[]);
  await page.getByText('Nieuw knock-outtoernooi',{exact:true}).click();await page.locator('#ko-editor h3').first().scrollIntoViewIfNeeded();
  fs.mkdirSync(path.join(__dirname,'../test-results'),{recursive:true});await page.screenshot({path:path.join(__dirname,'../test-results/knockout-mobile.png')});
  console.log('PASS: mobile creation, explicit scoring, roster, complete bracket, escaping, due filter, preserved error input and Dutch DST.');
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
