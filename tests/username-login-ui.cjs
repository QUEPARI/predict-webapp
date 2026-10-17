const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
  const files=['index.html','branding.js','app.js','online-profile.js','online-tournaments.js','styles.css','manifest.webmanifest'];
  const server=http.createServer((req,res)=>{req.url=req.url.split('?')[0];const f=req.url==='/'?'index.html':req.url.slice(1);if(!files.includes(f)){res.writeHead(404).end();return;}res.setHeader('Content-Type',f.endsWith('.js')?'text/javascript':f.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(path.join(__dirname,'..',f)));});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
  try{
    browser=await chromium.launch({headless:true,channel:process.env.PLAYWRIGHT_CHANNEL||'msedge'});const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{window.loggedIn=false;window.failLogin=true;window.calls=[];window.mockClient={auth:{getUser:async()=>({data:{user:loggedIn?{id:'fake-user'}:null}}),setSession:async args=>{calls.push(['session',args]);window.loggedIn=true;return {};},signInWithPassword:async()=>{throw Error('Username login must use controlled lookup');}},functions:{invoke:async(name,args)=>{calls.push([name,structuredClone(args)]);return failLogin?{error:{}}:{data:{access_token:'fake-access',refresh_token:'fake-refresh'}};}},from(table){const q={select(){return q;},eq(){return q;},single(){return q;},in(){return q;},order(){return q;},then(resolve){return Promise.resolve({data:table==='profiles'?{username:'qa-user',display_name:'QA',theme:'system'}:table==='user_roles'?{role:'user'}:[]}).then(resolve);}};return q;}};});
    await page.route('https://cdn.jsdelivr.net/**',r=>r.fulfill({contentType:'text/javascript',body:'export const createClient=()=>window.mockClient;'}));
    await page.goto('http://127.0.0.1:'+server.address().port+'/');await page.getByLabel('Gebruikersnaam',{exact:true}).fill('QA-USER');await page.getByLabel('Wachtwoord',{exact:true}).fill('fictitious-password');
    assert.equal(await page.locator('input[type=email]').count(),0);
    await page.getByRole('button',{name:'Inloggen',exact:true}).click();await page.getByText('Inloggen mislukt.',{exact:false}).waitFor();assert.equal(await page.evaluate(()=>loggedIn),false);
    await page.evaluate(()=>window.failLogin=false);await page.getByRole('button',{name:'Inloggen',exact:true}).click();await page.getByRole('button',{name:'Account',exact:true}).waitFor();
    assert.equal(await page.evaluate(()=>calls[0][0]),'username-login');assert.equal(await page.evaluate(()=>calls[0][1].body.username),'QA-USER');assert(await page.evaluate(()=>calls.some(x=>x[0]==='session')));
    assert(!await page.evaluate(()=>JSON.stringify(localStorage).includes('fictitious-password')));assert.deepEqual(errors,[]);
    console.log('PASS: username login browser, generic failure, verified session handoff and no cached password.');
  }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
