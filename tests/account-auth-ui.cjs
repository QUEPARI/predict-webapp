const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
  const server=http.createServer((req,res)=>{const f=new URL(req.url,'http://local').pathname.slice(1);if(!['account.html','account-auth.js','styles.css'].includes(f)){res.writeHead(404).end();return;}res.setHeader('Content-Type',f.endsWith('.js')?'text/javascript':f.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(path.join(__dirname,'..',f)));});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
  try{
    browser=await chromium.launch({headless:true,channel:process.env.PLAYWRIGHT_CHANNEL||'msedge'});
    const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{window.calls=[];window.failSave=false;window.mockClient={functions:{invoke:async(name,args)=>{calls.push([name,structuredClone(args)]);return failSave?{error:{}}:{data:{success:true}};}}};});
    await page.route('https://**/*',r=>r.request().url().startsWith('https://cdn.jsdelivr.net/')?r.fulfill({contentType:'text/javascript',body:'export function createClient(url,key,options){window.clientOptions=options;window.urlAtImport=location.href;return window.mockClient;}'}):r.abort());
    const base='http://127.0.0.1:'+server.address().port+'/account.html',code='a'.repeat(64);
    await page.goto(base+'#kind=activate&username=qa-user&code='+code);
    await page.getByLabel('Gebruikersnaam',{exact:true}).waitFor();
    assert.equal(await page.getByLabel('Gebruikersnaam',{exact:true}).inputValue(),'qa-user');assert.equal(await page.evaluate(()=>location.hash),'');assert(!await page.evaluate(()=>urlAtImport.includes('code=')));
    assert.equal(await page.evaluate(()=>clientOptions.auth.persistSession),false);
    assert.equal(await page.evaluate(()=>calls.length),0);assert.equal(await page.locator('input[type=email]').count(),0);
    await page.getByLabel('Wachtwoord (minimaal 12 tekens)').fill('fictitious-password');await page.getByLabel('Herhaal wachtwoord').fill('different-password');
    await page.getByRole('button',{name:'Wachtwoord opslaan'}).click();await page.getByText('De wachtwoorden zijn niet gelijk.').waitFor();assert.equal(await page.evaluate(()=>calls.length),0);
    await page.getByLabel('Herhaal wachtwoord').fill('fictitious-password');await page.evaluate(()=>window.failSave=true);await page.getByRole('button',{name:'Wachtwoord opslaan'}).click();await page.getByText('Opslaan mislukt.',{exact:false}).waitFor();
    assert.equal(await page.getByLabel('Eenmalige code').inputValue(),code);
    await page.evaluate(()=>window.failSave=false);await page.getByRole('button',{name:'Wachtwoord opslaan'}).click();await page.getByRole('heading',{name:'Wachtwoord opgeslagen'}).waitFor();
    assert.equal(await page.evaluate(()=>calls[0][0]),'manual-account');assert.equal(await page.evaluate(()=>calls[0][1].body.kind),'activate');
    assert.equal(await page.evaluate(()=>Object.keys(localStorage).length),0);
    await page.goto('about:blank');await page.goto(base);await page.getByRole('heading',{name:'Wachtwoord herstellen'}).waitFor();
    await page.getByLabel('Gebruikersnaam',{exact:true}).fill('qa-user');await page.getByLabel('Eenmalige code').fill(code);await page.getByLabel('Wachtwoord (minimaal 12 tekens)').fill('new-fictitious-password');await page.getByLabel('Herhaal wachtwoord').fill('new-fictitious-password');await page.getByRole('button',{name:'Wachtwoord opslaan'}).click();await page.getByRole('heading',{name:'Wachtwoord opgeslagen'}).waitFor();
    assert.equal(await page.evaluate(()=>calls[0][1].body.kind),'reset');
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert.deepEqual(errors,[]);
    console.log('PASS: mail-free activation/reset browser, URL cleanup, password confirmation, retry and no persistent secrets.');
  }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
