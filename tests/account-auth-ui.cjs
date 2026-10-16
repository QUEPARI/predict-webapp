// Browser tests with fictitious credentials; every remote request is intercepted.
const {chromium}=require('playwright');
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
  const server=http.createServer((req,res)=>{
    const file=new URL(req.url,'http://local').pathname.slice(1);
    if(!['account.html','account-auth.js','styles.css'].includes(file)){res.writeHead(404).end();return;}
    res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(path.join(__dirname,'..',file)));
  });
  await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
  try{
    browser=await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_CHANNEL?{channel:process.env.PLAYWRIGHT_CHANNEL}:{})});
    const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{
      window.calls=[];window.failVerify=false;window.failUpdate=false;window.failComplete=false;
      window.mockClient={auth:{
        resetPasswordForEmail:async(...args)=>{calls.push(['reset',...args]);return {error:{message:'account does not exist'}};},
        verifyOtp:async args=>{calls.push(['verify',args]);return {error:failVerify?{}:null};},
        setSession:async args=>{calls.push(['session',args]);return {error:failVerify?{}:null};},
        getUser:async()=>({data:{user:{id:'fictitious-user',email_confirmed_at:'2026-10-16'}}}),
        updateUser:async args=>{calls.push(['update',args]);return {error:failUpdate?{}:null};},
        signOut:async args=>{calls.push(['signout',args]);return {};}
      },rpc:async name=>{calls.push(['rpc',name]);return {error:failComplete?{}:null};},
      functions:{invoke:async(...args)=>{calls.push(['invoke',...args]);return {};}}};
    });
    await page.route('https://**/*',r=>{
      if(r.request().url().startsWith('https://cdn.jsdelivr.net/'))return r.fulfill({contentType:'text/javascript',body:'export function createClient(url,key,options){window.clientOptions=options;window.urlAtImport=location.href;return window.mockClient;}'});
      return r.abort();
    });
    async function open(url){await page.goto('about:blank');await page.goto(url);}
    const base=`http://127.0.0.1:${server.address().port}/account.html`;
    await open(base);await page.getByLabel('E-mailadres',{exact:true}).fill('nobody@example.invalid');await page.getByRole('button',{name:'Herstelmail aanvragen'}).click();
    await page.getByText('Als dit adres een account heeft, ontvang je een herstelmail.',{exact:false}).waitFor();
    assert.equal(await page.evaluate(()=>calls[0][2].redirectTo),base);
    assert.equal(await page.evaluate(()=>clientOptions.auth.persistSession),false);
    assert.equal(await page.getByLabel('Wachtwoord (minimaal 12 tekens)').count(),0);
    const token='a'.repeat(64);
    await open(base+'#invite='+token);await page.getByLabel('E-mailadres',{exact:true}).fill('invited@example.invalid');await page.getByRole('button',{name:'Activatiemail aanvragen'}).click();
    await page.getByText('Als de uitnodiging geldig is, ontvang je een activatiemail.',{exact:false}).waitFor();
    assert.equal(await page.evaluate(()=>location.hash),'');assert(!await page.evaluate(()=>urlAtImport.includes('invite=')));
    assert.equal(await page.evaluate(()=>calls[0][2].body.token),token);
    await open(base+'?token_hash=fictitious-hash&type=recovery&next=https://evil.invalid');
    await page.getByRole('button',{name:'Doorgaan',exact:true}).waitFor();
    assert.equal(await page.evaluate(()=>calls.length),0);assert.equal(await page.evaluate(()=>location.search),'');
    await page.getByRole('button',{name:'Doorgaan',exact:true}).click();
    await page.getByLabel('Wachtwoord (minimaal 12 tekens)').fill('fictitious-password');await page.getByLabel('Herhaal wachtwoord').fill('does-not-match');
    await page.getByRole('button',{name:'Wachtwoord opslaan'}).click();await page.getByText('De wachtwoorden zijn niet gelijk.').waitFor();
    assert.equal(await page.evaluate(()=>calls.filter(x=>x[0]==='update').length),0);
    await page.getByLabel('Herhaal wachtwoord').fill('fictitious-password');await page.getByRole('button',{name:'Wachtwoord opslaan'}).click();
    await page.getByRole('heading',{name:'Wachtwoord opgeslagen'}).waitFor();
    assert.equal(await page.evaluate(()=>calls.find(x=>x[0]==='signout')[1].scope),'global');
    assert.equal(await page.evaluate(()=>calls.filter(x=>x[0]==='rpc').length),0);
    assert.equal(await page.evaluate(()=>Object.keys(localStorage).length),0);
    await open(base+'#access_token=fictitious-access&refresh_token=fictitious-refresh&type=invite');
    await page.getByRole('button',{name:'Doorgaan',exact:true}).click();await page.getByLabel('Wachtwoord (minimaal 12 tekens)').fill('fictitious-password');await page.getByLabel('Herhaal wachtwoord').fill('fictitious-password');
    await page.evaluate(()=>window.failComplete=true);await page.getByRole('button',{name:'Wachtwoord opslaan'}).click();await page.getByText('Opslaan mislukt.',{exact:false}).waitFor();
    assert.equal(await page.evaluate(()=>calls.filter(x=>x[0]==='update').length),0);
    await page.evaluate(()=>window.failComplete=false);await page.getByRole('button',{name:'Wachtwoord opslaan'}).click();await page.getByRole('heading',{name:'Wachtwoord opgeslagen'}).waitFor();
    assert(await page.evaluate(()=>calls.some(x=>x[0]==='rpc'&&x[1]==='complete_account_invitation')));
    await open(base+'?token_hash=expired&type=recovery');await page.evaluate(()=>window.failVerify=true);await page.getByRole('button',{name:'Doorgaan',exact:true}).click();
    await page.getByText('Deze link is ongeldig, verlopen of al gebruikt.',{exact:false}).waitFor();assert.equal(await page.getByRole('button',{name:'Wachtwoord opslaan'}).count(),0);
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert.deepEqual(errors,[]);
    console.log('Account invitation/recovery browser tests passed (mock backend).');
  }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
