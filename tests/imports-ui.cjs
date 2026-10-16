const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
  const server=http.createServer((req,res)=>{
    const file=req.url==='/admin-imports.js'?'admin-imports.js':req.url==='/styles.css'?'styles.css':null;
    res.setHeader('Content-Type',file?.endsWith('.js')?'text/javascript':file?'text/css':'text/html');
    res.end(file?fs.readFileSync(path.join(__dirname,'..',file)):'<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"></head><body><main class="layout"><section id="imports" class="panel stack"></section></main><script type="module">import {loadAdminImports} from "/admin-imports.js";window.qaAbort=new AbortController();loadAdminImports(document.getElementById("imports"),{supabase:window.qaBackend,signal:qaAbort.signal,isCurrent:()=>true,onApplied:()=>window.qaApplied++});</script></body></html>');
  });
  await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
  try{
    browser=await chromium.launch({headless:true,channel:process.env.PLAYWRIGHT_CHANNEL||'msedge'});const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
    await page.addInitScript(()=>{
      window.qaApplied=0;window.qaFail=false;window.qaConflict=false;window.qaSlow=false;window.qaCalls=[];
      const items=Array.from({length:26},(_,i)=>({id:'item-'+i,kind:i===1?'results':'fixtures',state:i<2?'pending':'applied',external_id:'fx_test_'+i,payload:{home_name:i===0?'QA <img src=x onerror=alert(1)>':'QA A',away_name:'QA B',home_score:6,away_score:3,played_on:'2026-10-16',competition:'QA Darts',round:'QA ronde'}}));
      window.qaBackend={functions:{invoke:async(name,args)=>{qaCalls.push([name,args]);return {data:{queued:1,unchanged:2}};}},rpc:async(name,args)=>{
        qaCalls.push([name,args]);
        if(name==='admin_list_tournaments')return {data:[{id:'tour',name:'QA Darts'}]};
        if(name==='list_darts_imports'){if(qaSlow)await new Promise(r=>window.qaRelease=r);return {data:{total:items.length,items:items.slice(args.p_offset,args.p_offset+25)}};}
        if(name==='admin_get_tournament_rounds')return {data:[{round_id:'round',round_name:'QA ronde'}]};
        if(name==='admin_get_matches')return {data:[{match_id:'match',home_name:'QA A',away_name:'QA B',scheduled_start:'2026-10-16T10:00:00Z',score_unit:'legs'}]};
        if(name==='review_darts_import'){
          if(qaFail)return {error:{message:'QA serverfout'}};
          const state=args.p_action==='reject'?'rejected':qaConflict?'conflict':'applied';items.find(x=>x.id===args.p_item_id).state=state;
          return {data:{state,reason:state==='conflict'?'Bestaande uitslag wijkt af':null}};
        }
        return {data:[]};
      }};
    });
    await page.goto('http://127.0.0.1:'+server.address().port+'/');await page.getByLabel('Dartstoernooi',{exact:true}).selectOption('tour');
    await page.locator('article').first().waitFor();assert.equal(await page.locator('article img').count(),0);
    const fixture=page.locator('article').nth(0),result=page.locator('article').nth(1);
    await fixture.getByLabel('Gecontroleerde ronde',{exact:true}).selectOption('round');await fixture.getByLabel('Gecontroleerde score-eenheid').selectOption('legs');await fixture.getByLabel('Benodigd aantal sets of legs').fill('6');await fixture.locator('input[type=checkbox]').check();
    await page.evaluate(()=>window.qaFail=true);await fixture.getByRole('button',{name:'Wedstrijdconcept maken'}).click();await fixture.getByText('QA serverfout').waitFor();assert.equal(await fixture.getByLabel('Benodigd aantal sets of legs').inputValue(),'6');
    await page.evaluate(()=>window.qaFail=false);await fixture.getByRole('button',{name:'Wedstrijdconcept maken'}).click();await fixture.getByText('Wedstrijdconcept gemaakt.',{exact:false}).waitFor();assert.equal(await page.evaluate(()=>qaApplied),1);
    await result.getByLabel('Lokale wedstrijd').selectOption('match');await result.getByLabel('Gecontroleerde ronde',{exact:true}).selectOption('round');await result.getByLabel('Gecontroleerde score-eenheid').selectOption('legs');await result.locator('input[type=checkbox]').check();
    await page.evaluate(()=>window.qaConflict=true);await result.getByRole('button',{name:'Uitslag gecontroleerd verwerken'}).click();await result.getByText('Conflict: Bestaande uitslag wijkt af').waitFor();assert(await result.getByRole('button',{name:'Uitslag gecontroleerd verwerken'}).isDisabled());
    await result.getByRole('button',{name:'Voorstel afwijzen'}).click();await result.getByText('Voorstel afgewezen.',{exact:true}).waitFor();
    await page.getByRole('button',{name:'Volgende voorstellen'}).click();await page.getByText('26–26 van 26').waitFor();assert.equal(await page.locator('article').count(),1);
    await page.getByLabel('Exacte toernooinaam bij DartsAPI').fill('QA Darts');await page.getByRole('button',{name:'Voorstellen ophalen'}).click();await page.getByText('1 nieuwe voorstellen; 2 ongewijzigd.',{exact:false}).waitFor();
    assert(await page.evaluate(()=>qaCalls.some(x=>x[0]==='sync-darts-data'&&x[1].body.competition==='QA Darts')));
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert(!await page.evaluate(()=>JSON.stringify(localStorage).includes('QA Darts')));
    fs.mkdirSync(path.join(__dirname,'../test-results'),{recursive:true});await page.screenshot({path:path.join(__dirname,'../test-results/imports-mobile.png'),fullPage:false});
    await page.evaluate(()=>window.qaSlow=true);await page.getByRole('button',{name:'Wachtrij vernieuwen'}).click();await page.waitForFunction(()=>!!window.qaRelease);
    await page.evaluate(()=>{qaAbort.abort();document.getElementById('imports').innerHTML='Ander scherm';qaRelease();});assert.equal(await page.locator('#imports').innerText(),'Ander scherm');assert.deepEqual(errors,[]);
    console.log('PASS: mobile import queue, escaping, explicit review, draft preservation, conflict block, rejection, pagination, staging and stale-response guard.');
  }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
