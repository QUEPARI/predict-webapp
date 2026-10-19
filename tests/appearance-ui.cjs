// Browser integration with a fictitious centrally persisted color. No hosted writes.
const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const allowed=['index.html','tournament-images.js','round-settings.js','template-management.js','branding.js','app.js','push-notifications.js','online-profile.js','online-tournaments.js','knockout.js','score-source.js','bracket.js','tournament-management.js','styles.css','manifest.webmanifest'];
 const server=http.createServer((req,res)=>{const f=new URL(req.url,'http://local').pathname.slice(1)||'index.html';if(!allowed.includes(f)){res.writeHead(404).end();return;}res.setHeader('Content-Type',f.endsWith('.js')?'text/javascript':f.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(path.join(__dirname,'..',f)));});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser,accent=null,holdRead=false,releaseRead,readHeld;
 try{
  browser=await chromium.launch({headless:true,channel:'msedge'});const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('https://appearance-qa.invalid/**',async route=>{if(route.request().method()==='GET'&&holdRead){const stale=accent;await new Promise(resolve=>{releaseRead=async()=>{await route.fulfill({contentType:'application/json',body:JSON.stringify({accent:stale})});resolve();};readHeld();});return;}if(route.request().method()==='POST')accent=route.request().postDataJSON().accent;await route.fulfill({contentType:'application/json',body:JSON.stringify({accent})});});
  await page.addInitScript(()=>{
   window.qaRole=localStorage.getItem('qa-role')||'admin';window.qaTheme='light';window.qaFail=false;
   window.qaSupabase={auth:{getUser:async()=>({data:{user:localStorage.getItem('qa-out')?null:{id:'qa-admin'}}}),signOut:async()=>{localStorage.setItem('qa-out','1');return {}; }},
    from(table){const q={select(){return q;},eq(){return q;},neq(){return q;},order(){return q;},single(){return q;},then(resolve){return Promise.resolve({data:table==='profiles'?{username:'qa-admin',display_name:'QA',theme:window.qaTheme}:table==='user_roles'?{role:window.qaRole}:[]}).then(resolve);}};return q;},
    async rpc(name,args){
     if(name==='get_app_appearance')return {data:await(await fetch('https://appearance-qa.invalid/color')).json()};
     if(name==='set_app_appearance'){if(window.qaRole!=='admin')return {error:{message:'Geen toegang'}};if(window.qaFail)return {error:{message:'QA opslagfout'}};return {data:await(await fetch('https://appearance-qa.invalid/color',{method:'POST',body:JSON.stringify({accent:args.p_accent})})).json()};}
     if(name==='update_my_profile'){window.qaTheme=args.p_theme;return {data:{username:'qa-admin',display_name:args.p_display_name,theme:args.p_theme}};}
     if(name==='knockout_catalog')return {data:{sports:[{id:'s',slug:'darts',name:'Darts'}],templates:[],tournaments:[]}};
     return {data:[]};
    }};
  });
  await page.route('https://cdn.jsdelivr.net/**',r=>r.fulfill({contentType:'text/javascript',body:'export const createClient=()=>window.qaSupabase;'}));
  const base='http://127.0.0.1:'+server.address().port;
  const settings=async()=>{await page.getByRole('button',{name:'Beheer',exact:true}).click();await page.getByRole('button',{name:'Instellingen',exact:true}).click();await page.getByLabel('Kleurcode').waitFor();};
  const save=async color=>{await page.getByLabel('Kleurcode').fill(color);await page.getByRole('button',{name:'Kleur opslaan',exact:true}).click();await page.getByText('Accentkleur opgeslagen.',{exact:true}).waitFor();};
  await page.goto(base);await settings();await save('#7733cc');assert.equal(accent,'#7733cc');assert.equal(await page.locator('.account-disc').evaluate(e=>getComputedStyle(e).backgroundColor),'rgb(119, 51, 204)');
  await page.reload();await settings();assert.equal(await page.getByLabel('Kleurcode').inputValue(),'#7733cc');
  const held=new Promise(resolve=>readHeld=resolve);holdRead=true;await page.getByRole('button',{name:'Opnieuw ophalen'}).click();await held;await save('#2459b8');holdRead=false;await releaseRead();await page.waitForFunction(()=>document.querySelector('[data-appearance-message]').textContent==='');assert.equal(await page.getByLabel('Kleurcode').inputValue(),'#2459b8','Delayed read cannot replace successful save');await save('#7733cc');
  await page.evaluate(()=>window.qaFail=true);await page.getByLabel('Kleurcode').fill('#2459b8');await page.getByRole('button',{name:'Kleur opslaan',exact:true}).click();await page.getByText('Opslaan mislukt: QA opslagfout').waitFor();assert.equal(accent,'#7733cc');assert.equal(await page.getByLabel('Kleurcode').inputValue(),'#2459b8');await page.evaluate(()=>window.qaFail=false);
  for(const color of ['#ffffff','#000000','#ffff00']){
   await save(color);
   const readable=await page.locator('.accent-previews').evaluate(host=>{const rgb=s=>s.match(/\d+(?:\.\d+)?/g).slice(0,3).map(Number),lum=a=>a.map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4;}).reduce((s,x,i)=>s+x*[.2126,.7152,.0722][i],0),ratio=(a,b)=>(Math.max(a,b)+.05)/(Math.min(a,b)+.05);return [...host.querySelectorAll('.accent-sample')].every(e=>{const c=getComputedStyle(e),p=getComputedStyle(e.parentElement),a=lum(rgb(c.backgroundColor));return ratio(a,lum(rgb(c.color)))>=4.5&&ratio(a,lum(rgb(p.backgroundColor)))>=4.5;});});assert(readable,'Readable light/dark previews for '+color);
  }
  await page.getByRole('button',{name:'Standaardkleur herstellen'}).click();await page.getByText('Standaardkleur hersteld.').waitFor();assert.equal(accent,null);assert.equal(await page.locator('.account-disc').evaluate(e=>getComputedStyle(e).backgroundColor),'rgb(18, 111, 107)');
  await save('#7733cc');await page.getByRole('button',{name:'Account',exact:true}).click();await page.getByLabel('Thema',{exact:true}).selectOption('dark');await page.getByRole('button',{name:'Account opslaan'}).click();await page.getByText('Account opgeslagen in Predict.').waitFor();assert(await page.locator('body').evaluate(e=>e.classList.contains('dark')));assert.notEqual(await page.locator('.account-disc').evaluate(e=>getComputedStyle(e).backgroundColor),'rgb(88, 198, 176)');
  await settings();assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));fs.mkdirSync(path.join(__dirname,'../test-results'),{recursive:true});await page.screenshot({path:path.join(__dirname,'../test-results/appearance-dark-mobile.png')});
  await page.getByRole('button',{name:'Account',exact:true}).click();await page.getByRole('button',{name:'Uitloggen',exact:true}).click();await page.getByLabel('Gebruikersnaam',{exact:true}).waitFor();await page.reload();await page.waitForFunction(()=>document.body.style.getPropertyValue('--accent')!=='');assert.equal(accent,'#7733cc');
  await page.evaluate(()=>{localStorage.removeItem('qa-out');localStorage.setItem('qa-role','user');});await page.reload();await page.getByRole('heading',{name:'Mijn spellen'}).waitFor();assert.equal(await page.getByRole('button',{name:'Beheer',exact:true}).count(),0);assert.equal(await page.getByRole('button',{name:'Instellingen',exact:true}).count(),0);assert.deepEqual(errors,[]);
  console.log('PASS: central accent save/reload, failed save retains input, light/dark contrast, reset, login branding and admin-only controls.');
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
