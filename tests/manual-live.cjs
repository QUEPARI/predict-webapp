// Opt-in hosted test. Feed two JSON lines over stdin: {username,code}, then {code}.
// A test administrator must issue both codes for a disposable fictitious account.
// Passwords/tokens stay in process memory. The caller must remove the hosted fixtures.
const assert=require('node:assert/strict'),readline=require('node:readline'),crypto=require('node:crypto');
const lines=readline.createInterface({input:process.stdin})[Symbol.asyncIterator]();
const url='https://sfcozzjcuppfypetbbzn.supabase.co',key='sb_publishable_1opRVzunD94Sd71rKSJAew_0ydMP2VU';
async function call(name,body){const r=await fetch(url+'/functions/v1/'+name,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};}
(async()=>{
  const first=JSON.parse((await lines.next()).value),password=crypto.randomBytes(24).toString('base64url'),nextPassword=crypto.randomBytes(24).toString('base64url');
  assert(first.username.startsWith('live-qa-'));
  const activate=await call('manual-account',{kind:'activate',username:first.username,code:first.code,password});assert.equal(activate.status,200,'activation');
  const login=await call('username-login',{username:first.username.toUpperCase(),password});assert.equal(login.status,200,'username login');assert(login.body.refresh_token);
  assert.equal((await call('manual-account',{kind:'activate',username:first.username,code:first.code,password})).status,400,'one-use code');
  console.log('READY_FOR_RESET: activation, case-insensitive login and replay rejection passed');
  const second=JSON.parse((await lines.next()).value);
  const reset=await call('manual-account',{kind:'reset',username:first.username,code:second.code,password:nextPassword});assert.equal(reset.status,200,'reset');
  assert.equal((await call('username-login',{username:first.username,password})).status,401,'old password rejected');
  const refresh=await fetch(url+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:login.body.refresh_token})});assert(!refresh.ok,'old refresh session revoked');
  assert.equal((await call('username-login',{username:first.username,password:nextPassword})).status,200,'new password works');
  assert.equal((await call('manual-account',{kind:'reset',username:first.username,code:second.code,password})).status,400,'reset replay');
  assert.equal((await call('activate-account-invitation',{token:'a'.repeat(64),email:'qa@example.invalid'})).status,410,'mail route paused');
  console.log('PASS: hosted mail-free activation/login/reset; old password and refresh session rejected; no email sent');
  process.exit(0);
})().catch(e=>{console.error(e.message);process.exit(1);});
