// Isolated PostgreSQL policy tests. No network or hosted records.
const fs=require('node:fs'),assert=require('node:assert/strict');
const {PGlite}=require('../.local-test/node_modules/@electric-sql/pglite');
(async()=>{const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;create schema predict_branding;
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth,storage,predict_branding to authenticated;grant usage on schema storage to anon;
 create table public.user_roles(user_id uuid,role text);insert into public.user_roles values('00000000-0000-0000-0000-000000000001','admin');
 create table public.tournaments(id uuid primary key);insert into public.tournaments values('11111111-1111-1111-1111-111111111111');
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(bucket_id text,name text,metadata jsonb,primary key(bucket_id,name));alter table storage.objects enable row level security;grant select,insert,update,delete on storage.objects to authenticated,anon;`);
 await db.exec(fs.readFileSync('supabase/migrations/20261017082846_tournament_images.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261017090302_jpeg_tournament_images.sql','utf8'));
 assert.deepEqual((await db.query("select allowed_mime_types from storage.buckets where id='tournament-images'")).rows[0].allowed_mime_types,['image/jpeg','image/webp']);
 await db.exec(`set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';set role authenticated;
 insert into storage.objects(bucket_id,name) values('tournament-images','11111111-1111-1111-1111-111111111111/cover.jpg'),('tournament-images','11111111-1111-1111-1111-111111111111/cover.webp');
 update storage.objects set metadata='{}';`);
 assert.equal((await db.query('select * from storage.objects')).rows.length,2);
 await assert.rejects(db.exec("insert into storage.objects values('tournament-images','11111111-1111-1111-1111-111111111111/evil.svg',null)"));
 await assert.rejects(db.exec("insert into storage.objects values('tournament-images','99999999-9999-9999-9999-999999999999/cover.jpg',null)"));
 await db.exec("delete from storage.objects;reset role;set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';set role authenticated;");
 assert.equal((await db.query('select * from storage.objects')).rows.length,0);
 await assert.rejects(db.exec("insert into storage.objects values('tournament-images','11111111-1111-1111-1111-111111111111/cover.jpg',null)"));
 await db.exec('reset role;set role anon;');await assert.rejects(db.exec("insert into storage.objects values('tournament-images','11111111-1111-1111-1111-111111111111/cover.jpg',null)"));
 console.log('PASS: JPEG/WebP bucket, admin upload/update/read/delete, path constraints, ordinary/anonymous write denial.');
 }finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
