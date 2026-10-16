// Geometry checks with a fictitious 48-player Euro Tour bracket.
const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const server=http.createServer((req,res)=>{const file=req.url.slice(1);if(['bracket.js','knockout.js','styles.css'].includes(file)){res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':'text/css');res.end(fs.readFileSync(path.join(__dirname,'..',file)));}else {res.setHeader('Content-Type','text/html');res.end('<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"><main class="layout stack" id="target"></main>');}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{browser=await chromium.launch({headless:true,channel:'msedge'});const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 for(const width of [1280,390,320]){
  await page.setViewportSize({width,height:844});await page.goto('http://127.0.0.1:'+server.address().port);
  await page.evaluate(async()=>{const data={name:'Fictief Euro Tour',status:'published',roster:[],rounds:[],matches:[]};let number=0;
   for(let round=1;round<=6;round++){data.rounds.push({order:round,name:['Ronde 1','Ronde 2','Achtste finales','Kwartfinales','Halve finales','Finale'][round-1]});for(let position=1;position<=2**(6-round);position++){number++;data.matches.push({id:'m'+number,number,round,position,bye:round===1&&position%2===1,home:round===1?'Fictieve deelnemer A':round===2?'Fictieve geplaatste speler':'Winnaar wedstrijd '+number,away:'Fictieve deelnemer B',home_slot:position,away_slot:position+1,first_to:6,unit:'legs',start:'2026-10-17T11:00:00Z',status:'scheduled'});}}
   const {loadKnockoutSchema}=await import('/knockout.js');await loadKnockoutSchema(document.querySelector('#target'),{signal:new AbortController().signal,isCurrent:()=>true,supabase:{rpc:async()=>({data})}},'fake');
  });
  const g=await page.evaluate(()=>{const view=document.querySelector('.ko-bracket'),cols=[...view.querySelectorAll('.ko-round')];return {page:document.documentElement.scrollWidth,viewport:innerWidth,scroll:view.scrollWidth,client:view.clientWidth,rounds:cols.map(c=>({x:c.offsetLeft,y:c.offsetTop})),cards:view.querySelectorAll('article').length,links:view.querySelectorAll('path').length,clipped:[...view.querySelectorAll('article')].some(c=>c.scrollHeight>c.clientHeight)};});
  assert.equal(g.rounds.length,6);assert(g.rounds.every((r,i)=>r.y===0&&r.x===232*i));assert.equal(g.cards,47);assert.equal(g.links,46);assert(g.scroll>g.client);assert(g.page<=g.viewport);assert.equal(g.clipped,false,'Full names and time fit in bracket card');
  await page.getByRole('button',{name:'Volgende ronde in schema'}).click();await page.waitForTimeout(400);assert(await page.locator('.ko-bracket').evaluate(e=>e.scrollLeft>0));
  if(width===390){await page.locator('.ko-bracket').evaluate(e=>e.scrollLeft=0);fs.mkdirSync(path.join(__dirname,'../test-results'),{recursive:true});await page.screenshot({path:path.join(__dirname,'../test-results/bracket-48-mobile.png')});}
 }
 assert.deepEqual(errors,[]);console.log('PASS: 48-player bracket, 16 byes, all rounds in one row, funnel connections, unclipped cards, mobile scrolling and page width.');
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
