// Real browser, mock account backend. No hosted data or real credentials.
const {chromium}=require('playwright');const http=require('node:http');const fs=require('node:fs');const path=require('node:path');const assert=require('node:assert/strict');
(async()=>{
  const files={'/':'index.html','/app.js':'app.js','/online-profile.js':'online-profile.js','/online-tournaments.js':'online-tournaments.js','/styles.css':'styles.css','/manifest.webmanifest':'manifest.webmanifest'};
  const server=http.createServer((req,res)=>{const f=files[req.url];if(!f){res.writeHead(404).end();return;}res.setHeader('Content-Type',f.endsWith('.js')?'text/javascript':f.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(path.join(__dirname,'..',f)));});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
  const profiles={a:{username:'account-a',display_name:'QA <img src=x onerror=alert(1)>',theme:'system'},b:{username:'account-b',display_name:'Ander account',theme:'dark'}};
  try {
    browser=await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_CHANNEL?{channel:process.env.PLAYWRIGHT_CHANNEL}:{})});
    const page=await browser.newPage({viewport:{width:390,height:844}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.emulateMedia({colorScheme:'dark'});
    await page.route('https://profile-qa.invalid/**',async route=>{
      const url=new URL(route.request().url());const uid=url.searchParams.get('uid');
      if(url.pathname==='/save'){const c=route.request().postDataJSON();if(c.p_display_name!=null)profiles[uid].display_name=c.p_display_name.trim();if(c.p_theme!=null)profiles[uid].theme=c.p_theme;}
      await route.fulfill({contentType:'application/json',body:JSON.stringify(profiles[uid])});
    });
    await page.addInitScript(()=>{
      window.qaUid='a';window.qaFailSave=false;window.qaFailPredictions=false;window.qaSlow=false;window.qaReads=[];
      localStorage.setItem('predict-demo-v1',JSON.stringify({user:'Old Demo',predictions:{d1:{home:3,away:0}}}));
      localStorage.setItem('qa-auth-session','session-preserved');
      window.qaSupabase={auth:{getUser:async()=>({data:{user:window.qaUid?{id:window.qaUid}:null}}),signOut:async()=>{window.qaUid=null;return {};},
        signInWithPassword:async({email})=>{window.qaUid=email.startsWith('b')?'b':'a';return {};}},
        from(table){const filters={};let one=false,start=0,end=999;
          const q={select(){return q;},eq(k,v){filters[k]=v;return q;},neq(){return q;},in(){return q;},order(){return q;},single(){one=true;return q;},range(a,b){start=a;end=b;return q;},then(resolve,reject){return (async()=>{
            const uid=window.qaUid;
            if(table==='profiles')return {data:await(await fetch('https://profile-qa.invalid/profile?uid='+filters.id)).json()};
            if(table==='match_predictions'){
              window.qaReads.push({...filters});
              if(window.qaSlow)await new Promise(r=>{window.qaResolve=r;});
              if(window.qaFailPredictions)return {error:{message:'QA leesfout'}};
              const data=filters['matches.tournament_id']==='tour-2'?[]:Array.from({length:26},(_,i)=>({id:uid+'-prediction-'+i,match_id:'match-'+i,home_score:6,away_score:4,
                matches:{tournament_id:'tour-1',home_name:i===0?'Speler <img src=x onerror=alert(1)>':'Speler '+i,away_name:'Tegenstander',status:i===0?'finished':'scheduled',home_score:i===0?6:null,away_score:i===0?3:null}}));
              return {data:data.slice(start,end+1),count:data.length};
            }
            return {data:{user_roles:{role:'user'},tournament_entries:[{tournament_id:'tour-1'},{tournament_id:'tour-2'}],
              tournaments:one?{id:'tour-1',name:'QA toernooi',status:'published'}:[{id:'tour-1',name:'QA toernooi',status:'published'},{id:'tour-2',name:'Zonder voorspellingen',status:'active'}],pools:[],pool_members:[]}[table]||[]};
          })().then(resolve,reject);}};return q;
        },
        async rpc(name,args){
          if(name==='update_my_profile'){
            if(window.qaFailSave)return {error:{message:'QA opslagfout'}};
            const p=await(await fetch('https://profile-qa.invalid/save?uid='+window.qaUid,{method:'POST',body:JSON.stringify(args)})).json();
            return {data:{display_name:p.display_name,theme:p.theme}};
          }
          return {data:name==='get_my_match_points'?[{match_id:'match-0',earned_points:1}]:[]};
        }};
    });
    await page.route('https://cdn.jsdelivr.net/**',r=>r.fulfill({contentType:'text/javascript',body:'export const createClient=()=>window.qaSupabase;'}));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.getByRole('button',{name:'Profiel',exact:true}).click();
    await page.getByRole('button',{name:'Profiel opslaan'}).waitFor();
    await page.waitForFunction(()=>document.body.classList.contains('dark'));
    await page.emulateMedia({colorScheme:'light'});await page.waitForFunction(()=>!document.body.classList.contains('dark'));
    assert.equal(await page.locator('#online-profile img').count(),0);
    assert.equal(await page.getByRole('button',{name:'Verwijder lokale demogegevens'}).count(),0);
    await page.locator('#account-predictions table').waitFor();
    const first=page.locator('#account-predictions tbody tr').first();
    assert((await first.innerText()).includes('6–4'));assert((await first.innerText()).includes('6–3'));assert.equal(await first.locator('td').last().innerText(),'1');
    await page.getByLabel('Weergavenaam',{exact:true}).fill('  Opgeslagen naam  ');
    await page.getByLabel('Thema',{exact:true}).selectOption('light');await page.getByRole('button',{name:'Profiel opslaan'}).click();
    await page.getByText('Profiel opgeslagen in Predict.').waitFor();assert.equal(profiles.a.display_name,'Opgeslagen naam');
    await page.reload();await page.getByRole('button',{name:'Profiel opslaan'}).waitFor();
    assert.equal(await page.getByLabel('Weergavenaam',{exact:true}).inputValue(),'Opgeslagen naam');
    await page.getByRole('button',{name:'Volgende',exact:true}).click();
    await page.getByText('Speler 25 – Tegenstander',{exact:false}).waitFor();
    assert.equal(await page.locator('#account-predictions tbody tr').count(),1);
    await page.getByLabel('Toernooi',{exact:true}).selectOption('tour-2');await page.getByText('Nog geen voorspellingen voor dit toernooi.').waitFor();
    await page.evaluate(()=>window.qaFailPredictions=true);
    await page.getByLabel('Toernooi',{exact:true}).selectOption('tour-1');await page.getByText('Eigen voorspellingen laden mislukt: QA leesfout').waitFor();
    await page.evaluate(()=>window.qaFailPredictions=false);await page.getByRole('button',{name:'Voorspellingen opnieuw proberen'}).click();
    await page.locator('#account-predictions table').waitFor();
    await page.getByLabel('Weergavenaam',{exact:true}).fill('Niet kwijt');await page.evaluate(()=>window.qaFailSave=true);
    await page.getByRole('button',{name:'Profiel opslaan'}).click();await page.getByText('Opslaan mislukt: QA opslagfout').waitFor();
    assert.equal(await page.getByLabel('Weergavenaam',{exact:true}).inputValue(),'Niet kwijt');
    await page.getByRole('button',{name:'Wissel licht/donker'}).click();await page.getByText('Thema opslaan mislukt: QA opslagfout').waitFor();
    assert.equal(await page.locator('body').getAttribute('class'),'');
    await page.evaluate(()=>window.qaFailSave=false);await page.getByRole('button',{name:'Wissel licht/donker'}).click();
    await page.waitForFunction(()=>document.body.classList.contains('dark'));
    assert.equal(await page.getByLabel('Weergavenaam',{exact:true}).inputValue(),'Niet kwijt','Header toggle keeps unsaved name');
    assert.equal(await page.getByLabel('Thema',{exact:true}).inputValue(),'dark');
    page.once('dialog',d=>d.dismiss());await page.getByRole('button',{name:'Home',exact:true}).click();assert.equal(await page.getByLabel('Weergavenaam',{exact:true}).inputValue(),'Niet kwijt');
    await page.getByRole('button',{name:'Profiel opslaan'}).click();await page.getByText('Profiel opgeslagen in Predict.').waitFor();
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
    fs.mkdirSync(path.join(__dirname,'..','test-results'),{recursive:true});await page.evaluate(()=>scrollTo(0,0));
    await page.screenshot({path:path.join(__dirname,'..','test-results','profile-mobile.png'),fullPage:false});
    assert(await page.evaluate(()=>window.qaReads.every(r=>r.user_id==='a'&&r['matches.tournament_id'])));
    const local=await page.evaluate(()=>({...localStorage}));assert.equal(local['predict-demo-v1'],undefined);assert.equal(local['qa-auth-session'],'session-preserved');
    assert.deepEqual(Object.keys(JSON.parse(local['predict-ui-v2'])).sort(),['tab','theme']);
    await page.getByRole('button',{name:'Home',exact:true}).click();await page.evaluate(()=>window.qaSlow=true);
    await page.getByRole('button',{name:'Profiel',exact:true}).click();await page.waitForFunction(()=>!!window.qaResolve);
    await page.getByRole('button',{name:'Home',exact:true}).click();await page.evaluate(()=>{window.qaSlow=false;window.qaResolve();});
    assert.equal(await page.locator('#account-predictions').count(),0,'Late response cannot replace another screen');
    await page.getByRole('button',{name:'Uitloggen'}).click();await page.getByLabel('Gebruikersnaam',{exact:true}).fill('b@example.invalid');await page.getByLabel('Wachtwoord').fill('test-only');
    await page.getByRole('button',{name:'Inloggen',exact:true}).click();await page.getByRole('button',{name:'Profiel',exact:true}).click();
    await page.getByRole('button',{name:'Profiel opslaan'}).waitFor();assert.equal(await page.getByLabel('Weergavenaam',{exact:true}).inputValue(),'Ander account');
    assert.equal(profiles.a.display_name,'Niet kwijt');assert.equal(profiles.b.display_name,'Ander account');assert.deepEqual(errors,[]);
    console.log('PASS: profile persistence/reload, system/header themes, error recovery, draft preservation, own paginated predictions/points, legacy-cache cleanup, stale requests and account separation');
  } finally {if(browser)await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
