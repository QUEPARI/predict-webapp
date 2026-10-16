// Browser integration test with a mock backend: never changes hosted data.
// Install playwright, then run: node tests/pools-ui.cjs
const {chromium} = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

(async () => {
  const server = http.createServer((req,res) => {
    const file = {'/':'index.html','/app.js':'app.js','/pool-comparison.js':'pool-comparison.js','/online-profile.js':'online-profile.js','/online-tournaments.js':'online-tournaments.js','/styles.css':'styles.css','/manifest.webmanifest':'manifest.webmanifest'}[req.url];
    if (!file) {res.writeHead(404).end(); return;}
    res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html');
    res.end(fs.readFileSync(path.join(__dirname,'..',file)));
  });
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_CHANNEL ? {channel:process.env.PLAYWRIGHT_CHANNEL} : {})});
    const page = await browser.newPage({viewport:{width:390,height:844}});
    const errors=[]; page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => {
      const uid='11111111-1111-4111-8111-111111111111';
      const tid='22222222-2222-4222-8222-222222222222';
      const pid='33333333-3333-4333-8333-333333333333';
      const member='44444444-4444-4444-8444-444444444444';
      window.qaCalls=[]; window.qaFail=false;
      const pool={id:pid,name:'Vrienden <img src=x onerror=alert(1)>',owner_id:uid,tournament_id:tid};
      const rows=[{user_id:uid,display_name:'Eigenaar',earned_points:1,correct_winners:1,rank_position:1},
        {user_id:member,display_name:'Lid',earned_points:0,correct_winners:0,rank_position:2}];
      window.qaSupabase={
        auth:{getUser:async()=>({data:{user:{id:uid}}}),signOut:async()=>({})},
        from(table) {
          const filters={}; const chain={select(){return chain;},eq(k,v){filters[k]=v;return chain;},neq(){return chain;},order(){return chain;},single(){return chain;},
            then(resolve,reject){
              let data={profiles:{username:'QA eigenaar'},user_roles:{role:'user'},tournaments:[{id:tid,name:'QA toernooi',status:'published'}],
                tournament_entries:[{tournament_id:tid}],pools:[pool],pool_members:filters.pool_id?[{user_id:uid},{user_id:member}]:[{pool_id:pid}],
                tournament_rounds:[{id:'round-1',name:'Ronde 1'}]}[table] || [];
              return Promise.resolve({data}).then(resolve,reject);
            }}; return chain;
        },
        async rpc(name,args){
          window.qaCalls.push({name,args});
          if (window.qaFail) return {error:{message:'Geen toegang tot deze poule'}};
          if(name==='get_pool_prediction_comparison')return {data:[{id:'m',round_id:'round-1',round_name:'Ronde 1',home_name:'QA A',away_name:'QA B',my_home:6,my_away:4,their_home:6,their_away:3,home_score:6,away_score:4,my_points:3,their_points:1}]};
          return {data:name==='get_tournament_leaderboard'?rows:name==='invite_pool_member'?'a'.repeat(64):pid};
        }
      };
    });
    await page.route('https://cdn.jsdelivr.net/**',route => route.fulfill({contentType:'text/javascript',body:'export const createClient=()=>window.qaSupabase;'}));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.getByRole('button',{name:'Mijn poules',exact:true}).click();
    await page.getByRole('button',{name:'Leden en klassement'}).waitFor();
    assert.equal(await page.locator('#private-pools img').count(),0,'Names must be escaped');
    await page.getByRole('button',{name:'Leden en klassement'}).click();
    await page.getByRole('heading',{name:'Leden (2)'}).waitFor();
    await page.getByLabel('Gebruikersnaam van het lid',{exact:true}).fill('friend@example.invalid');
    await page.getByRole('button',{name:'Uitnodigingscode maken'}).click();
    await page.locator('#private-created-code').waitFor();
    assert.equal(await page.locator('#private-created-code').inputValue(),'a'.repeat(64));
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,'Mobile page must not overflow horizontally');
    fs.mkdirSync(path.join(__dirname,'..','test-results'),{recursive:true});
    await page.screenshot({path:path.join(__dirname,'..','test-results','private-pools-mobile.png'),fullPage:true});
    await page.locator('[data-compare-member="44444444-4444-4444-8444-444444444444"]').first().click();await page.getByText('Jij en Lid',{exact:true}).waitFor();assert.equal(await page.locator('.comparison-table tbody tr').count(),1);assert((await page.locator('.comparison-table').textContent()).includes('6–4'));assert((await page.locator('.comparison-table').textContent()).includes('6–3'));
    await page.getByLabel('Klassement per ronde').selectOption('round-1');
    await page.waitForFunction(()=>window.qaCalls.some(c=>c.name==='get_tournament_leaderboard'&&c.args.p_round_id==='round-1'));
    await page.getByRole('button',{name:'← Mijn poules',exact:true}).click();
    await page.getByLabel('Poulenaam',{exact:true}).fill('Collega’s');
    await page.getByRole('button',{name:'Poule aanmaken',exact:true}).click();
    await page.getByRole('button',{name:'Leden en klassement'}).waitFor();
    assert(await page.evaluate(()=>window.qaCalls.some(c=>c.name==='create_pool'&&c.args.p_name==='Collega’s')));
    await page.getByLabel('Uitnodigingscode',{exact:true}).fill('b'.repeat(64));
    await page.getByRole('button',{name:'Lid worden',exact:true}).click();
    await page.waitForFunction(()=>window.qaCalls.some(c=>c.name==='accept_pool_invitation'));
    await page.getByRole('button',{name:'Leden en klassement'}).click();
    await page.getByRole('button',{name:'Beheer overdragen'}).waitFor();
    page.on('dialog',dialog=>dialog.accept());
    await page.getByRole('button',{name:'Beheer overdragen'}).click();
    await page.waitForFunction(()=>window.qaCalls.some(c=>c.name==='manage_pool_member'&&c.args.p_action==='transfer'));
    await page.getByRole('button',{name:'Klassementen',exact:true}).click();
    await page.getByLabel('Poule',{exact:true}).selectOption('33333333-3333-4333-8333-333333333333');
    await page.waitForFunction(()=>window.qaCalls.filter(c=>c.name==='get_tournament_leaderboard'&&c.args.p_pool_id).length>=3);
    await page.getByRole('button',{name:'Mijn poules',exact:true}).click();
    await page.getByRole('button',{name:'Leden en klassement'}).waitFor();
    await page.evaluate(()=>window.qaFail=true);
    await page.getByLabel('Poulenaam',{exact:true}).fill('Afgewezen');
    await page.getByRole('button',{name:'Poule aanmaken',exact:true}).click();
    await page.getByText('Geen toegang tot deze poule',{exact:true}).waitFor();
    assert.equal(await page.getByRole('button',{name:'Poule aanmaken',exact:true}).isEnabled(),true);
    assert.equal(await page.evaluate(()=>Object.values(localStorage).some(v=>v.includes('a'.repeat(64)))),false,'Invitation secret must not persist');
    assert.deepEqual(errors,[]);
    console.log('PASS: mobile UI, escaped names, create/join/invite/transfer, pool/round filters, error recovery, no stored invitation token, no browser exceptions');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve=>server.close(resolve));
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
