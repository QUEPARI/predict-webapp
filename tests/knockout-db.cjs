// Local PostgreSQL (PGlite) only. Never connects to hosted Supabase.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {PGlite}=require('../.local-test/node_modules/@electric-sql/pglite');
(async()=>{
 const db=new PGlite();
 try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema predict_private;
 grant usage on schema auth,predict_private to authenticated,anon;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table public.user_roles(user_id uuid primary key,role text);
 create table public.sports(id uuid primary key default gen_random_uuid(),name text,slug text);
 insert into public.sports(name,slug) values('Darts','darts'),('Football','football');
 create table public.competitions(id uuid primary key default gen_random_uuid(),sport_id uuid references public.sports(id),name text);
 create table public.tournaments(id uuid primary key default gen_random_uuid(),competition_id uuid references public.competitions(id),name text,status text default 'draft',starts_at timestamptz,ends_at timestamptz);
 create table public.tournament_rounds(id uuid primary key default gen_random_uuid(),tournament_id uuid references public.tournaments(id),name text,round_order integer,unique(id,tournament_id));
 create table public.matches(id uuid primary key default gen_random_uuid(),tournament_id uuid references public.tournaments(id),round_id uuid,home_name text,away_name text,scheduled_start timestamptz,actual_start timestamptz,status text default 'scheduled' check(status in('scheduled','postponed','live','finished','cancelled')),home_score integer check(home_score>=0),away_score integer check(away_score>=0),score_unit text check(score_unit in('goals','legs','sets')),first_to integer check(first_to>0),created_at timestamptz default now(),updated_at timestamptz default now(),start_time_confirmed boolean default false,data_source text,needs_review boolean default false,review_reason text,last_synced_at timestamptz,predictions_enabled boolean default false,foreign key(round_id,tournament_id) references public.tournament_rounds(id,tournament_id),check((home_score is null)=(away_score is null)));
 create table public.tournament_scoring(tournament_id uuid primary key references public.tournaments(id),scoring_mode text default 'replacement',is_locked boolean default false);
 create table public.round_scoring(id uuid default gen_random_uuid(),tournament_id uuid,round_id uuid,winner_points integer default 0,exact_score_points integer default 0);
 create table public.match_predictions(id uuid primary key default gen_random_uuid(),match_id uuid references public.matches(id),user_id uuid,home_score integer,away_score integer,updated_at timestamptz default now(),unique(match_id,user_id));
 create table public.tournament_entries(tournament_id uuid,user_id uuid);
 create table public.match_audit_log(id uuid default gen_random_uuid(),match_id uuid,changed_by uuid,action text,old_values jsonb not null,new_values jsonb);
 create table public.scoring_audit_log(tournament_id uuid,changed_by uuid,action text,old_values jsonb,new_values jsonb);
 `);
 await db.exec(fs.readFileSync(path.join(__dirname,'fixtures/knockout-legacy-functions.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(__dirname,'fixtures/knockout-legacy-guards.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261016181258_manual_knockout.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261016183915_knockout_templates.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/tests/manual_knockout.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/tests/knockout_templates.sql'),'utf8'));
 const {rows}=await db.query('select count(*)::int n from public.tournaments');assert.equal(rows[0].n,0,'SQL suite rolls back every tournament');
 console.log('PASS: local PostgreSQL migration and transactional knockout integration tests; no hosted connection.');
 }finally{await db.close();}
})().catch(e=>{console.error({message:e.message,detail:e.detail,where:e.where,internalQuery:e.internalQuery});process.exitCode=1;});
