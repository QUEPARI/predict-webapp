// Isolated comparison/ranking rendering; no hosted data is changed.
const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const root=path.join(__dirname,'..');
 const server=http.createServer((req,res)=>{const name=req.url.split('?')[0].slice(1);if(['styles.css','pool-comparison.js'].includes(name)){res.setHeader('Content-Type',name.endsWith('.js')?'text/javascript; charset=utf-8':'text/css');return res.end(fs.readFileSync(path.join(root,name)));}res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"></head><body><main class="layout"><div id="comparison"></div><div id="ranking"></div></main></body></html>');});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  browser=await chromium.launch({headless:true,executablePath:process.env.PREDICT_CHROMIUM,args:['--no-sandbox','--disable-gpu']});const page=await browser.newPage();
  await page.goto('http://127.0.0.1:'+server.address().port);
  await page.evaluate(async()=>{
   const {loadTournamentComparison,renderLeaderboard}=await import('/pool-comparison.js');
   const ctx={isCurrent:()=>true,supabase:{rpc:async()=>({data:[{round_id:'r',round_name:'Ronde 1',home_name:'Van Veen',away_name:'Gilding',my_home:6,my_away:3,their_home:4,their_away:6,home_score:6,away_score:3,my_points:15,their_points:0}]})}};
   await loadTournamentComparison(document.querySelector('#comparison'),ctx,'t','v','Dani');
   renderLeaderboard(document.querySelector('#ranking'),[{user_id:'u',display_name:'Dani',rank_position:1,earned_points:10,correct_winners:2,exact_scores:1}],()=>{},{detailed:true,userId:'u'});
  });
  for(const width of [320,390,768,1280])for(const dark of [false,true]){
   await page.setViewportSize({width,height:844});await page.evaluate(d=>document.body.classList.toggle('dark',d),dark);
   for(const [table,indices] of [['.comparison-table',[2,3,4,5,6]],['.ranking-table',[3,4,5]]])for(const i of indices)for(const tag of ['th','td'])assert.equal(await page.locator(table+' '+tag+':nth-child('+i+')').evaluate(e=>getComputedStyle(e).textAlign),'center');
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Page overflow at '+width);
  }
  await page.screenshot({path:path.join(root,'test-results/centered-tables-desktop.png'),fullPage:true});
  console.log('PASS: all comparison scores and points, ranking points/winners/exact centered on mobile/tablet/desktop in light and dark.');
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
