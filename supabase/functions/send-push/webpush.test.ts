import webpush from 'npm:web-push@3.6.7';
import ece from 'npm:http_ece@1.2.0';
import { createECDH, randomBytes } from 'node:crypto';

Deno.test('real VAPID signing and RFC8291 encryption round trip (no network)',()=>{
 const vapid=webpush.generateVAPIDKeys();
 const receiver=createECDH('prime256v1');receiver.generateKeys();const auth=randomBytes(16);
 const subscription={endpoint:'https://fcm.googleapis.com/fake',keys:{p256dh:receiver.getPublicKey().toString('base64url'),auth:auth.toString('base64url')}};
 const payload=JSON.stringify({title:'Predict test',body:'Alleen een lokale encryptietest.'});
 const request=webpush.generateRequestDetails(subscription,payload,{vapidDetails:{subject:'https://quepari.github.io/predict-webapp/',publicKey:vapid.publicKey,privateKey:vapid.privateKey},TTL:3600});
 if(!request.headers.Authorization.startsWith('vapid ')||request.headers['Content-Encoding']!=='aes128gcm')throw new Error('Missing VAPID/encryption headers');
 const plain=ece.decrypt(request.body,{version:'aes128gcm',privateKey:receiver,authSecret:auth});
 if(plain.toString()!==payload)throw new Error('Encrypted payload mismatch');
});

