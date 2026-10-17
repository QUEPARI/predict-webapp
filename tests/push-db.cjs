// Isolated Postgres; no hosted database, push provider or real user receives messages.
const {PGlite}=require('../.local-test/node_modules/@electric-sql/pglite');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema predict_private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table auth.users(id uuid primary key);create table public.user_roles(user_id uuid,role text);
 create table public.tournaments(id uuid primary key default gen_random_uuid(),name text,status text);
 create table public.tournament_entries(user_id uuid,tournament_id uuid);
 create table public.matches(id uuid primary key default gen_random_uuid(),tournament_id uuid,round_id uuid default gen_random_uuid(),status text default 'scheduled',predictions_enabled boolean default true,start_time_confirmed boolean default true,needs_review boolean default false,actual_start timestamptz,home_score integer,away_score integer,scheduled_start timestamptz default now()+interval '2 hours',score_unit text default 'legs',first_to integer default 6);
 create table public.match_predictions(match_id uuid,user_id uuid);
 create table predict_private.knockout_nodes(match_id uuid,is_bye boolean,home_slot integer,away_slot integer);`);
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261017170956_web_push_notifications.sql'),'utf8').split('-- Hosted scheduler')[0]);
 const [admin,user,other]=['11111111','22222222','33333333'].map(x=>`${x}-1111-4111-8111-111111111111`);
 const tid='44444444-1111-4111-8111-111111111111';
 await db.query(`insert into auth.users values($1),($2),($3)`,[admin,user,other]);await db.query(`insert into public.user_roles values($1,'admin'),($2,'user')`,[admin,user]);
 await db.query(`insert into public.tournaments values($1,'Push test','published')`,[tid]);await db.query('insert into public.tournament_entries select id,$1 from auth.users',[tid]);
 await db.exec(`update predict_push.config set enabled=true,public_key='test';`);
 const as=async(id,role='authenticated')=>{await db.exec('reset role');await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);await db.exec('set role '+role);};
 const api=async(action,data={})=>(await db.query('select public.push_notifications($1,$2::jsonb) value',[action,JSON.stringify(data)])).rows[0].value;
 const sub=n=>({endpoint:`https://fcm.googleapis.com/fake-${n}`,keys:{p256dh:'A'.repeat(87),auth:'B'.repeat(22)}});
 await as(user);await api('subscribe',sub(1));await api('subscribe',sub(1));assert.equal((await api('config')).ready,true);
 await assert.rejects(()=>api('admin'),/Alleen beheerders/);await assert.rejects(()=>db.query('select * from predict_push.subscriptions'),/permission denied/);
 for(const endpoint of ['https://localhost/x','http://fcm.googleapis.com/x','https://fcm.googleapis.com.evil.invalid/x','https://fcm.googleapis.com@evil.invalid/x','https://fcm.googleapis.com:443/x'])await assert.rejects(()=>api('subscribe',{...sub(1),endpoint}),/Ongeldige/);
 await assert.rejects(()=>api('subscribe',{...sub(1),keys:{p256dh:'bad',auth:'bad'}}),/Ongeldige/);
 await db.exec('begin');for(let i=3;i<=6;i++)await api('subscribe',sub(i));await assert.rejects(()=>api('subscribe',sub(7)),/Maximaal vijf/);await db.exec('rollback');
 await as(other);await api('subscribe',sub(2));await as(admin);assert.equal((await api('admin')).devices,2);
 await db.exec('reset role');
 const m=(await db.query(`insert into public.matches(tournament_id) values($1) returning id`,[tid])).rows[0].id;
 const count=async()=>Number((await db.query('select predict_push.missing_count($1,null) n',[user])).rows[0].n);
 assert.equal(await count(),1);
 for(const patch of ["status='postponed'","status='cancelled'","status='live'","status='finished'","predictions_enabled=false","start_time_confirmed=false","needs_review=true","actual_start=now()","home_score=6,away_score=2","scheduled_start=now()-interval '1 second'","round_id=null","first_to=null"]){
  await db.exec('begin');await db.exec(`update public.matches set ${patch}`);assert.equal(await count(),0,patch);await db.exec('rollback');
 }
 await db.query('insert into predict_private.knockout_nodes values($1,true,1,2)',[m]);assert.equal(await count(),0);await db.exec('update predict_private.knockout_nodes set is_bye=false,away_slot=null');assert.equal(await count(),0);await db.exec('update predict_private.knockout_nodes set away_slot=2');assert.equal(await count(),1);
 await db.query('insert into public.match_predictions values($1,$2)',[m,other]);
 await db.exec('select predict_push.hourly_reminders();select predict_push.hourly_reminders()');assert.equal((await db.query(`select count(*) n from predict_push.deliveries`)).rows[0].n,1);
 await as(admin);assert.deepEqual(await api('preview',{kind:'reminder'}),{devices:1,users:1});
 const request={kind:'reminder',request_id:'55555555-1111-4111-8111-111111111111'};assert.equal((await api('send',request)).devices,1);assert.equal((await api('send',request)).devices,1);
 await assert.rejects(()=>api('send',{...request,kind:'custom',title:'Different',body:'Message'}),/al gebruikt/);
 await as(user);await assert.rejects(()=>db.query('select public.claim_push_deliveries()'),/permission denied/);
 await as('', 'anon');await assert.rejects(()=>api('config'),/permission denied/);
 await db.exec('reset role');await db.query('insert into public.match_predictions values($1,$2)',[m,user]);
 await as('', 'service_role');assert.deepEqual((await db.query('select public.claim_push_deliveries() data')).rows[0].data,[]);
 await db.exec('reset role');assert.equal((await db.query(`select count(*) n from predict_push.deliveries where state='skipped'`)).rows[0].n,2);
 // Announcements include nonparticipants but never drafts; repeated transitions deduplicate.
 await db.query(`insert into public.tournaments values('66666666-1111-4111-8111-111111111111','New game','draft')`);
 await db.exec(`update public.tournaments set status='announced' where name='New game';update public.tournaments set status='draft' where name='New game';update public.tournaments set status='announced' where name='New game'`);
 assert.equal((await db.query(`select count(*) n from predict_push.deliveries where kind='announcement'`)).rows[0].n,2);
 await as('', 'service_role');const claimed=(await db.query('select public.claim_push_deliveries() data')).rows[0].data;assert.equal(claimed.length,2);assert.deepEqual((await db.query('select public.claim_push_deliveries() data')).rows[0].data,[]);
 const d=claimed[0];await db.query('select public.finish_push_delivery($1,$2,503)',[d.id,d.lease]);await db.exec('reset role');await db.exec(`update predict_push.deliveries set available_at=now()-interval '1 second' where state='pending'`);
 await as('', 'service_role');const retried=(await db.query('select public.claim_push_deliveries() data')).rows[0].data.find(x=>x.id===d.id);assert(retried&&retried.lease!==d.lease);
 await db.query('select public.finish_push_delivery($1,$2,201)',[d.id,d.lease]);await db.exec('reset role');assert.equal((await db.query('select state from predict_push.deliveries where id=$1',[d.id])).rows[0].state,'pending');
 await as('', 'service_role');await db.query('select public.finish_push_delivery($1,$2,201)',[d.id,retried.lease]);await db.exec('reset role');assert.equal((await db.query('select state from predict_push.deliveries where id=$1',[d.id])).rows[0].state,'sent');
 // Logging in as another user on a shared device cannot retain the old user's queued messages.
 await as(admin);await api('subscribe',{endpoint:claimed[1].endpoint,keys:{p256dh:'A'.repeat(87),auth:'B'.repeat(22)}});await db.exec('reset role');assert.equal((await db.query('select count(*) n from predict_push.deliveries where id=$1',[claimed[1].id])).rows[0].n,0);
 await as(admin);await api('unsubscribe',{endpoint:claimed[1].endpoint});assert.equal((await api('admin')).devices,1);
 await db.exec('reset role');
 await db.exec('begin');
 await db.exec(`insert into predict_push.deliveries(subscription_id,dedupe_key,kind,title,body,expires_at) select id,'expired-test','custom','Expired','Must not be sent',now()-interval '1 second' from predict_push.subscriptions`);
 await as('', 'service_role');const notExpired=(await db.query('select public.claim_push_deliveries() data')).rows[0].data;assert(!notExpired.some(x=>x.payload.title==='Expired'));await db.exec('reset role');assert.equal((await db.query("select state from predict_push.deliveries where dedupe_key='expired-test'")).rows[0].state,'skipped');await db.exec('rollback');
 // Validate hosted scheduler SQL with inert extension shims: no HTTP or real cron runs.
 await db.exec(`create schema vault;create schema net;create schema cron;
 create table vault.decrypted_secrets(name text,decrypted_secret text);create table net.requests(url text,headers jsonb,body jsonb,timeout integer);
 create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) returns bigint language plpgsql as $$begin insert into net.requests values(url,headers,body,timeout_milliseconds);return 1;end$$;
 create table cron.jobs(name text,expression text,command text);create function cron.schedule(text,text,text) returns bigint language plpgsql as $$begin insert into cron.jobs values($1,$2,$3);return 1;end$$;`);
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261017170956_web_push_notifications.sql'),'utf8').split('-- Hosted scheduler')[1].replace(/create extension if not exists pg_cron;|create extension if not exists pg_net;/g,''));
 assert.equal((await db.query('select count(*) n from cron.jobs')).rows[0].n,2);
 await db.exec(`update predict_push.config set worker_url='https://fake.supabase.co/functions/v1/send-push';select predict_push.dispatch();`);assert.equal((await db.query('select count(*) n from net.requests')).rows[0].n,0);
 await db.exec(`insert into vault.decrypted_secrets values('predict_push_worker_token','fake-not-a-secret');select predict_push.dispatch()`);assert.equal((await db.query('select count(*) n from net.requests')).rows[0].n,1);
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261017171105_push_vault_credentials.sql'),'utf8'));
 await as(user);await assert.rejects(()=>db.query('select predict_push.dispatch()'),/permission denied/);await assert.rejects(()=>db.query('select public.push_worker_configuration()'),/permission denied/);
 await as('', 'service_role');assert.equal((await db.query('select public.push_worker_configuration() data')).rows[0].data.worker_token,'fake-not-a-secret');
 await db.exec('reset role');
 await db.exec(`create view cron.job as select 1::bigint jobid,name jobname from cron.jobs;
 create function cron.unschedule(bigint) returns boolean language plpgsql as $$begin delete from cron.jobs where name='predict-hourly-reminders';return true;end$$;`);
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261017190105_dutch_push_reminder_times.sql'),'utf8'));
 for(const [instant,expected] of [
 ['2026-01-15T11:00:00Z','2026-01-15:12'],['2026-01-15T17:00:00Z','2026-01-15:18'],
 ['2026-07-15T10:00:00Z','2026-07-15:12'],['2026-07-15T16:00:00Z','2026-07-15:18'],
 ['2026-03-28T11:00:00Z','2026-03-28:12'],['2026-03-29T10:00:00Z','2026-03-29:12'],
 ['2026-10-24T10:00:00Z','2026-10-24:12'],['2026-10-25T11:00:00Z','2026-10-25:12'],
 ['2026-07-15T09:59:00Z',null],['2026-07-15T11:00:00Z',null],['2026-07-15T16:01:00Z',null],['2026-01-15T16:00:00Z',null]]){
  assert.equal((await db.query('select predict_push.reminder_slot($1) slot',[instant])).rows[0].slot,expected,instant);
 }
 assert.equal((await db.query("select count(*) n from cron.jobs where name='predict-hourly-reminders'")).rows[0].n,0);
 await db.exec('delete from predict_push.subscriptions');await db.query('delete from public.match_predictions where user_id=$1',[user]);await as(user);await api('subscribe',sub(20));await db.exec('reset role');
 for(const time of ['2026-07-15T09:00:00Z','2026-07-15T10:00:00Z','2026-07-15T10:00:00Z','2026-07-15T16:00:00Z'])await db.query('select predict_push.scheduled_reminders($1)',[time]);
 assert.equal((await db.query('select count(*) n from predict_push.deliveries')).rows[0].n,2);
 await as('', 'service_role');const messages=(await db.query('select public.claim_push_deliveries() data')).rows[0].data;assert.equal(messages.length,2);assert(messages.every(x=>x.payload.title==='PREDICT. Voorspel nu!'&&x.payload.body==='Je hebt nog 1 wedstrijden te voorspellen'));
 await as(user);await assert.rejects(()=>db.query('select predict_push.scheduled_reminders()'),/permission denied/);
 console.log('PASS: 12:00/18:00 Amsterdam schedule, both DST transitions, no off-schedule reminders, per-slot dedupe and exact notification text');
 console.log('PASS: push authorization, private endpoints, eligibility, hourly and announcement dedupe, manual idempotency, leases/retries, stale reminders, shared-device reassignment and scheduler wiring');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
