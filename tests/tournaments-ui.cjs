// Browser integration with fake Supabase data. No hosted data is changed.
const {chromium}=require('playwright');
const http=require('node:http');const fs=require('node:fs');const path=require('node:path');const assert=require('node:assert/strict');
(async()=>{
  const files={'/':'index.html','/app.js':'app.js','/pool-comparison.js':'pool-comparison.js','/bracket.js':'bracket.js','/knockout.js':'knockout.js','/tournament-management.js':'tournament-management.js','/online-profile.js':'online-profile.js','/online-tournaments.js':'online-tournaments.js','/styles.css':'styles.css','/manifest.webmanifest':'manifest.webmanifest'};
  const server=http.createServer((req,res)=>{req.url=req.url.split('?')[0];
    const file=files[req.url];if(!file){res.writeHead(404).end();return;}
    res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');
    res.end(fs.readFileSync(path.join(__dirname,'..',file)));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
  try {
    browser=await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_CHANNEL?{channel:process.env.PLAYWRIGHT_CHANNEL}:{})});
    const page=await browser.newPage({viewport:{width:390,height:844},timezoneId:'America/New_York'});const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.clock.install({time:new Date('2026-10-16T14:00:00Z')});
    await page.addInitScript(()=>{
      window.qaJoined=false;window.qaCalls=[];window.qaPredictions=[];window.qaFailSave=false;window.qaFailRead=false;
      window.qaSupabase={auth:{getUser:async()=>({data:{user:{id:'user'}}}),signOut:async()=>({})},
        from(table){
          const filters={};let one=false,from=0,to=999;
          const q={select(){return q;},eq(k,v){filters[k]=v;return q;},neq(){return q;},in(k,v){filters[k]=v;return q;},
            order(){return q;},single(){one=true;return q;},range(a,b){from=a;to=b;return q;},then(resolve,reject){
              if(window.qaFailRead&&table==='matches')return Promise.resolve({error:{message:'Testverbinding verbroken'}}).then(resolve,reject);
              const ms=Array.from({length:53},(_,i)=>({id:'match-'+i,round_id:'round',home_name:'Speler '+i,away_name:'Tegenstander '+i,
                scheduled_start:i===51?'2026-10-17T14:00:00Z':i===52?'2026-10-17T00:30:00Z':'2026-10-16T14:01:00Z',actual_start:null,status:i===1?'postponed':i===2?'finished':'scheduled',
                home_score:i===2?6:null,away_score:i===2?3:null,score_unit:i===3?'goals':'legs',first_to:i===3?null:6,
                start_time_confirmed:true,needs_review:false,predictions_enabled:true}));
              const t={id:'tour',name:'QA <img src=x onerror=alert(1)>',status:'published',starts_at:'2026-10-16T13:00:00Z'};
              let data={profiles:{username:'QA'},user_roles:{role:'user'},tournaments:one?t:[t],
                tournament_entries:window.qaJoined?[{tournament_id:'tour'}]:[],matches:ms.slice(from,to+1),
                tournament_rounds:[{id:'round',name:'Ronde 1',round_order:1}],
                tournament_scoring:[{scoring_mode:'replacement'}],round_scoring:[{round_id:'round',winner_points:1,exact_score_points:3}],
                match_predictions:window.qaPredictions.filter(p=>filters.match_id?.includes(p.match_id)),pool_members:[],pools:[]}[table] || [];
              return Promise.resolve({data,count:table==='matches'?53:undefined}).then(resolve,reject);
            }};return q;
        },
        async rpc(name,args){
          window.qaCalls.push({name,args});
          if(name==='get_tournament_prediction_counts')return {data:{server_now:'2026-10-16T14:00:00Z',next_deadline:'2026-10-16T14:01:00Z',tournaments:[{id:'tour',open_count:49,remaining_count:48}]}};
          if(name==='join_tournament'){window.qaJoined=true;return {data:'tour'};}
          if(name==='get_my_match_points')return {data:[{match_id:'match-2',earned_points:1}]};
          if(name==='submit_match_prediction'){
            if(window.qaFailSave)return {error:{message:'De individuele voorspeldeadline is verstreken.'}};
            window.qaPredictions=window.qaPredictions.filter(p=>p.match_id!==args.p_match_id);
            window.qaPredictions.push({match_id:args.p_match_id,home_score:args.p_home_score,away_score:args.p_away_score});
            return {data:'prediction'};
          }
          return {data:[]};
        }};
    });
    await page.route('https://cdn.jsdelivr.net/**',route=>route.fulfill({contentType:'text/javascript',body:'export const createClient=()=>window.qaSupabase;'}));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.getByText('Je doet nog niet mee aan een toernooi.',{exact:false}).waitFor();
    await page.getByRole('button',{name:'Toernooien',exact:true}).click();
    await page.getByText('49 wedstrijden open om te voorspellen',{exact:true}).waitFor();await page.getByRole('button',{name:'Bekijk toernooi'}).click();
    await page.getByRole('button',{name:'Deelnemen aan dit toernooi'}).waitFor();
    assert.equal(await page.locator('[data-online-predict]').count(),0,'Nonparticipant cannot submit');
    assert.equal(await page.locator('#online-tournaments img').count(),0,'Names escaped');
    await page.getByRole('button',{name:'Deelnemen aan dit toernooi'}).click();
    await page.getByText('Je neemt nu deel aan dit toernooi.').waitFor();
    await page.getByText('Je doet mee · Punten uit afgeronde wedstrijden: 1.',{exact:false}).waitFor();
    await page.getByRole('button',{name:'Spelregels & puntentelling',exact:true}).click();await page.getByRole('heading',{name:'Spelregels & puntentelling'}).waitFor();assert((await page.locator('[data-detail-panel=rules]').textContent()).includes('first-to 6'));assert.equal(await page.locator('.match-rules').count(),0);await page.getByRole('button',{name:'Voorspellingen',exact:true}).click();const card=page.locator('[data-online-match="match-0"]');
    assert(await page.locator('.nav').evaluate(e=>getComputedStyle(e).position==='static'&&e.getBoundingClientRect().top<document.querySelector('#online-tournaments').getBoundingClientRect().top),'Mobile menu above content');await card.locator('[name="home"]').fill('6');await card.locator('[name="away"]').fill('6');
    await card.getByRole('button').click();
    await card.getByText('Vul een geldige eindstand voor dit wedstrijdformaat in.').waitFor();
    assert.equal(await page.evaluate(()=>window.qaCalls.filter(c=>c.name==='submit_match_prediction').length),0);
    await page.locator('[data-online-match="match-3"] [name="home"]').fill('2');
    await card.locator('[name="away"]').fill('4');await card.getByRole('button').click();
    await card.getByText('Opgeslagen in Predict.').waitFor();
    assert.equal(await page.locator('[data-online-match="match-3"] [name="home"]').inputValue(),'2','Saving one card preserves other drafts');
    await page.locator('[data-detail-tab=results]').click();assert.equal(await page.locator('[data-detail-panel=results]').isVisible(),true);
    await page.locator('[data-detail-tab=predictions]').click();assert.equal(await page.locator('[data-online-match="match-3"] [name="home"]').inputValue(),'2');
    const football=page.locator('[data-online-match="match-3"]');
    await football.locator('[name="away"]').fill('2');await football.getByRole('button').click();
    await football.getByText('Opgeslagen in Predict.').waitFor();
    assert(await page.evaluate(()=>window.qaCalls.some(c=>c.name==='submit_match_prediction'&&c.args.p_match_id==='match-3'&&c.args.p_home_score===2&&c.args.p_away_score===2)),'Football draw allowed');
    assert.equal(await page.locator('[data-online-match="match-1"] button').isDisabled(),true,'Postponed closed');
    assert.equal(await page.locator('[data-online-match="match-2"] button').isDisabled(),true,'Finished closed');
    await page.evaluate(()=>window.qaFailSave=true);
    await card.locator('[name="away"]').fill('3');await card.getByRole('button').click();
    await card.getByText('Opslaan mislukt:',{exact:false}).waitFor();
    assert.equal(await card.locator('[name="away"]').inputValue(),'3','Server error preserves draft');
    page.once('dialog',dialog=>dialog.dismiss());
    await page.getByRole('button',{name:'Home',exact:true}).click();
    assert.equal(await card.isVisible(),true,'Declining discard preserves the current form');
    assert.equal(await page.locator('#online-show-all,#online-refresh').count(),0);assert((await card.locator('.match-meta').textContent()).includes('10:01'));assert.equal(await card.locator('h3').count(),0);assert.equal(await card.locator('label').first().textContent(),'Speler 0');assert.equal(await card.locator('[data-open-state]').textContent(),'Open');assert.equal(await page.locator('[data-detail-tab=champion]').isVisible(),false);assert.equal(await page.locator('[data-online-match="match-2"]').isVisible(),true);
    await page.clock.fastForward(61000);
    assert.equal(await card.locator('form button').isDisabled(),true,'Open tab closes at deadline');assert.equal(await card.locator('[data-open-state]').getAttribute('class'),'pill is-closed');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Mobile width');
    fs.mkdirSync(path.join(__dirname,'..','test-results'),{recursive:true});
    await page.evaluate(()=>scrollTo(0,0));
    await page.screenshot({path:path.join(__dirname,'..','test-results','online-tournaments-mobile.png'),fullPage:false});
    page.on('dialog',dialog=>dialog.accept());
    await page.getByRole('button',{name:'Volgende',exact:true}).click();
    await page.locator('[data-online-match="match-50"]').waitFor();
    assert.equal(await page.getByRole('button',{name:'Volgende',exact:true}).isDisabled(),true);assert((await page.locator('[data-online-match="match-52"] .match-meta').textContent()).includes('20:30'));assert.equal(await page.locator('#online-day').inputValue(),'2026-10-16');
    await page.getByRole('button',{name:'Vorige',exact:true}).click();
    await page.locator('[data-online-match="match-0"]').waitFor();
    assert.equal(await page.locator('[data-online-match="match-0"] [name="away"]').inputValue(),'3','Paging preserves unsaved input');
    await page.evaluate(()=>window.qaFailRead=true);
    await page.locator('#online-day').selectOption('2026-10-17');
    await page.getByText('Ophalen mislukt: Testverbinding verbroken').waitFor();
    await page.evaluate(()=>window.qaFailRead=false);
    await page.getByRole('button',{name:'Opnieuw proberen',exact:true}).click();
    await page.locator('[data-online-match="match-51"]').waitFor();assert.equal(await page.locator('[data-pagination]').isVisible(),false);assert.equal(await page.locator('[data-online-match]').count(),1);
    await page.getByRole('button',{name:'Home',exact:true}).click();
    await page.getByRole('button',{name:'Wedstrijden en voorspellingen'}).waitFor();await page.locator('.prediction-attention.remaining').waitFor();assert((await page.locator('.prediction-attention.remaining').textContent()).includes('Nog 48 te voorspellen'));
    assert.equal(await page.evaluate(()=>Object.values(localStorage).some(v=>v.includes('match-0'))),false,'No online predictions cached locally');
    assert.deepEqual(errors,[]);
    console.log('PASS: real routes, join without pool, own prediction create/reload, validation, drafts, server rejection, deadline timer, pagination, mobile width and retry');
  } finally {if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
