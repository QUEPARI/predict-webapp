const vm=require('node:vm'),fs=require('node:fs'),crypto=require('node:crypto'),path=require('node:path'),assert=require('node:assert/strict');
const source=fs.readFileSync('scripts/prepare-push.cjs','utf8'),writes=[],logs=[];
const context=exists=>({require:name=>name==='node:fs'?{existsSync:()=>exists,mkdirSync(){},writeFileSync:(...args)=>writes.push(args)}:require(name),__dirname:path.resolve('scripts'),process:{argv:['node','script','abcdefghijklmnopqrst']},console:{log:s=>logs.push(s)}});
vm.runInNewContext(source,context(false));assert.equal(writes.length,2);
const env=Object.fromEntries(writes[0][1].trim().split('\n').map(line=>line.split('=')));
const key=crypto.createECDH('prime256v1');key.setPrivateKey(Buffer.from(env.PUSH_VAPID_PRIVATE_KEY,'base64url'));assert.equal(key.getPublicKey().toString('base64url'),env.PUSH_VAPID_PUBLIC_KEY);assert.equal(Buffer.from(env.PUSH_WORKER_TOKEN,'base64url').length,32);
assert(writes[1][1].includes(env.PUSH_WORKER_TOKEN));assert(writes.every(x=>x[0].includes('.local-test')));assert(!logs.join('').includes(env.PUSH_WORKER_TOKEN));
assert.throws(()=>vm.runInNewContext(source,context(true)),/already exist/);
console.log('PASS: deployment preparation generates matching VAPID keys, private ignored files, no secret output and no accidental key rotation');
