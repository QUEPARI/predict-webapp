const {chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
  const files=['app.js','online-profile.js','online-tournaments.js','index.html','styles.css','manifest.webmanifest'];
  const server=http.createServer((req,res)=>{const f=req.url==='/'?'index.html':req.url.slice(1);if(!files.includes(f)){res.writeHead(404).end();return;}res.setHeader('Content-Type',f.endsWith('.js')?'text/javascript':f.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(path.join(__dirname,'..',f)));});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
  try{
    browser=await chromium.launch({headless:true,channel:process.env.PLAYWRIGHT_CHANNEL||'msedge'});
    const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{
      window.calls=[];window.mockClient={auth:{getUser:async()=>({data:{user:{id:'fake-admin'}}})},from(table){const q={select(){return q;},eq(){return q;},order(){return q;},in(){return q;},single(){return q;},then(resolve){return Promise.resolve({data:table==='user_roles'?{role:'admin'}:table==='profiles'?{username:'admin',display_name:'Admin',theme:'system'}:[]}).then(resolve);}};return q;},rpc:async(name,args)=>{calls.push([name,args]);return {data:name==='create_account_invitation'?'c'.repeat(64):[]};}};
    });
    await page.route('https://cdn.jsdelivr.net/**',r=>r.fulfill({contentType:'text/javascript',body:'export const createClient=()=>window.mockClient;'}));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);await page.getByRole('button',{name:'Beheer',exact:true}).click();
    await page.getByLabel('E-mailadres nieuw account').fill('fictional@example.invalid');await page.getByRole('button',{name:'Account uitnodigen',exact:true}).click();
    const link=page.getByLabel('Accountuitnodigingslink');await link.waitFor();assert((await link.inputValue()).endsWith('/account.html#invite='+'c'.repeat(64)));
    assert.equal(await page.evaluate(()=>JSON.stringify(localStorage).includes('cccccccc')),false);
    await page.getByRole('button',{name:'Uitnodigingen voor dit adres intrekken'}).click();await page.getByText('Openstaande accountuitnodigingen ingetrokken.').waitFor();assert.equal(await link.count(),0);
    assert(await page.evaluate(()=>calls.some(x=>x[0]==='revoke_account_invitations'&&x[1].p_email==='fictional@example.invalid')));
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert.deepEqual(errors,[]);
    console.log('Account invitation admin browser test passed (mock backend).');
  }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
