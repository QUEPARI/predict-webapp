// Prepare deployment credentials locally. Does not contact Supabase or send notifications.
const {createECDH,randomBytes}=require('node:crypto'),fs=require('node:fs'),path=require('node:path');
const project=process.argv[2];if(!/^[a-z]{20}$/.test(project||''))throw new Error('Usage: node scripts/prepare-push.cjs <supabase-project-ref>');
const folder=path.join(__dirname,'../.local-test/push-deployment');
if(fs.existsSync(folder))throw new Error('Deployment credentials already exist. Reuse them; do not rotate VAPID keys for existing subscriptions.');
fs.mkdirSync(folder,{recursive:true,mode:0o700});
const ecdh=createECDH('prime256v1');ecdh.generateKeys();const publicKey=ecdh.getPublicKey().toString('base64url'),privateKey=ecdh.getPrivateKey().toString('base64url'),token=randomBytes(32).toString('base64url');
fs.writeFileSync(path.join(folder,'secrets.env'),`PUSH_VAPID_PUBLIC_KEY=${publicKey}\nPUSH_VAPID_PRIVATE_KEY=${privateKey}\nPUSH_WORKER_TOKEN=${token}\n`,{mode:0o600});
const store=(name,value)=>`do $$declare existing uuid;begin select id into existing from vault.secrets where name='${name}'; if existing is null then perform vault.create_secret('${value}','${name}');else perform vault.update_secret(existing,'${value}');end if;end $$;`;
fs.writeFileSync(path.join(folder,'activate.sql'),`-- Deployment secrets; never commit.\nbegin;\n${store('predict_push_worker_token',token)}\n${store('predict_push_vapid_private_key',privateKey)}\nupdate predict_push.config set public_key='${publicKey}',worker_url='https://${project}.supabase.co/functions/v1/send-push',enabled=true where singleton;\ncommit;\n`,{mode:0o600});
console.log('Prepared ignored deployment files in .local-test/push-deployment. No credentials printed; nothing deployed.');
