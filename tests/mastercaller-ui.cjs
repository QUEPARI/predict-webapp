const {chromium}=require('playwright'),http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert/strict');
(async()=>{
 const allowed=['knockout.js','score-source.js','round-settings.js','bracket.js','styles.css'];
 const server=http.createServer((req,res)=>{const name=req.url.split('?')[0].slice(1);if(allowed.includes(name)){res.setHeader('Content-Type',name.endsWith('.js')?'text/javascript':'text/css');res.end(fs.readFileSync(path.join(__dirname,'..',name)));}else res.end('<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"></head><body><main id="target" class="layout"></main><script type="module">import {loadKnockoutAdmin} from "/knockout.js";window.ab=new AbortController();loadKnockoutAdmin(document.querySelector("#target"),{supabase:window.mock,signal:ab.signal,isCurrent:()=>true});</script></body></html>');});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  browser=await chromium.launch({headless:true,...(process.env.PREDICT_CHROMIUM?{executablePath:process.env.PREDICT_CHROMIUM}:{}),args:['--no-sandbox','--disable-gpu']});const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.calls=[];window.fail=true;window.mock={rpc:async(name,args)=>{calls.push([name,args]);if(name==='knockout_catalog')return {data:{sports:[{id:'s',name:'Darts',slug:'darts'},{id:'f',name:'Voetbal',slug:'football'}],templates:[],tournaments:window.created?[{id:'t',name:'European Championship 2026'}]:[]}};if(name==='get_knockout_schema')return {data:{name:'European Championship 2026',status:'published',roster:['A','B'],rounds:[{id:'r',name:'Finale',order:1,unit:'legs',first_to:11,winner_points:1,exact_points:3}],matches:[],server_now:new Date().toISOString()}};return {data:null};},functions:{invoke:async(name,args)=>{calls.push([name,args]);if(fail)return {error:{message:'Request failed',context:{json:async()=>({error:'Mastercaller niet bereikbaar (HTTP 418). Automatische verwerking wacht op de bron.'})}}};window.created=true;return {data:{id:'t',name:'European Championship 2026',participants:32,matches:31}};}}};});
  await page.goto('http://127.0.0.1:'+server.address().port);await page.getByText('Nieuw knock-outtoernooi',{exact:true}).click();const form=page.locator('#ko-create form');
  await form.locator('[name=scoreSource]').selectOption('mastercaller_test');
  assert.equal(await form.locator('[data-manual-create]').isVisible(),false);assert.equal(await form.locator('[name=count]').isDisabled(),true);
  assert.equal(await form.locator('[name=name]').getAttribute('required'),null);
  const url='https://mastercaller.nl/toernooien/european-championship/2026/uitslagen';await form.getByLabel('Mastercaller-uitslagenlink').fill(url);
  await form.getByRole('button',{name:'Toernooi uit Mastercaller maken'}).click();await page.getByText('Mastercaller niet bereikbaar (HTTP 418). Automatische verwerking wacht op de bron.',{exact:true}).waitFor();
  assert.equal(await form.getByLabel('Mastercaller-uitslagenlink').inputValue(),url);assert.equal(await page.evaluate(()=>window.created),undefined);
  assert.equal(await form.locator('[data-manual-create]').isVisible(),false,'failure preserves source mode');
  await page.screenshot({path:path.join(__dirname,'../test-results/mastercaller-create-mobile.png'),fullPage:true});
  await form.locator('[name=sport]').selectOption('f');assert.equal(await form.locator('[name=scoreSource]').inputValue(),'manual');
  await form.locator('[name=sport]').selectOption('s');await form.locator('[name=scoreSource]').selectOption('mastercaller_test');await page.evaluate(()=>window.fail=false);
  await form.getByRole('button',{name:'Toernooi uit Mastercaller maken'}).click();await page.getByText('Mastercaller-toernooi aangemaakt: 32 deelnemers. Automatische synchronisatie actief.',{exact:true}).waitFor();
  const request=await page.evaluate(()=>calls.find(c=>c[0]==='sync-mastercaller')[1]);assert.equal(request.body.action,'create');assert.equal(request.body.url,url);assert.equal(request.body.winner_points,1);assert.equal(request.body.exact_points,3);assert.deepEqual(errors,[]);
  console.log('PASS: Mastercaller create mode, no manual schema inputs, URL preservation and actual HTTP error, football fallback, automatic creation and mobile layout.');
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
