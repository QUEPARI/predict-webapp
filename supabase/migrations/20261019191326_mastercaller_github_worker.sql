create table predict_private.mastercaller_cache(url text primary key,snapshot jsonb not null,fetched_at timestamptz not null default now());
create table predict_private.mastercaller_create_jobs(id uuid primary key default gen_random_uuid(),actor uuid not null,url text not null,name text,winner_points integer not null,exact_points integer not null,mode text not null,status text not null default 'queued' check(status in('queued','running','done','failed')),lease uuid,claimed_at timestamptz,created_at timestamptz not null default now(),tournament_id uuid,error text);
alter table predict_private.mastercaller_cache enable row level security;
alter table predict_private.mastercaller_create_jobs enable row level security;
revoke all on predict_private.mastercaller_cache,predict_private.mastercaller_create_jobs from public,anon,authenticated,service_role;
create function predict_private.cache_mastercaller(p_snapshot jsonb) returns boolean language plpgsql security definer set search_path='' as $$declare u text:=predict_private.mastercaller_url(p_snapshot->>'url');begin
 if jsonb_typeof(p_snapshot->'bracket') is distinct from 'array' or jsonb_typeof(p_snapshot->'roster') is distinct from 'array' or jsonb_typeof(p_snapshot->'rounds') is distinct from 'array' or jsonb_typeof(p_snapshot->'records') is distinct from 'array' then raise exception 'Ongeldig bronschema';end if;
 if jsonb_array_length(p_snapshot->'roster') not in(2,4,8,16,32,64,128) or jsonb_array_length(p_snapshot->'bracket')<>jsonb_array_length(p_snapshot->'roster')-1 then raise exception 'Onvolledig bronschema';end if;
 insert into predict_private.mastercaller_cache(url,snapshot) values(u,p_snapshot) on conflict(url) do update set snapshot=excluded.snapshot,fetched_at=now();return true;
end $$;
create function public.cache_mastercaller_snapshot(p_snapshot jsonb) returns boolean language sql security invoker set search_path='' as $$select predict_private.cache_mastercaller(p_snapshot)$$;
revoke all on function predict_private.cache_mastercaller(jsonb),public.cache_mastercaller_snapshot(jsonb) from public,anon,authenticated;
grant execute on function predict_private.cache_mastercaller(jsonb),public.cache_mastercaller_snapshot(jsonb) to service_role;
create function predict_private.request_mastercaller_game(p_url text,p_name text,p_winner integer,p_exact integer,p_mode text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=predict_private.ko_admin();u text:=predict_private.mastercaller_url(p_url);snap jsonb;tid uuid;j uuid;
begin
 if p_winner is null or p_exact is null or p_winner not between 0 and 1000 or p_exact not between 0 and 1000 or p_mode is null or p_mode not in('replacement','additive') or length(coalesce(p_name,''))>120 then raise exception 'Ongeldige toernooigegevens';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor_id::text,0));
 select id into j from predict_private.mastercaller_create_jobs where actor=actor_id and url=u and name is not distinct from p_name and winner_points=p_winner and exact_points=p_exact and mode=p_mode and status in('queued','running') order by created_at desc limit 1;
 if j is not null then return jsonb_build_object('status','queued','job_id',j,'message','Je aanvraag staat al in de GitHub-wachtrij.');end if;
 select snapshot into snap from predict_private.mastercaller_cache where url=u and fetched_at>now()-interval '4 hours';
 if snap is not null then
  tid:=predict_private.create_mastercaller_game(snap,p_name,p_winner,p_exact,p_mode);
  return jsonb_build_object('status','done','id',tid,'name',coalesce(nullif(btrim(p_name),''),snap->>'title'),'participants',jsonb_array_length(snap->'roster'),'matches',jsonb_array_length(snap->'bracket'));
 end if;
 select id into j from predict_private.mastercaller_create_jobs where actor=actor_id and url=u and name is not distinct from p_name and winner_points=p_winner and exact_points=p_exact and mode=p_mode and status in('queued','running') order by created_at desc limit 1;
 if j is null then
  if (select count(*) from predict_private.mastercaller_create_jobs where actor=actor_id and status in('queued','running'))>=3 then raise exception 'Er staan al drie aanvragen klaar';end if;
  insert into predict_private.mastercaller_create_jobs(actor,url,name,winner_points,exact_points,mode) values(actor_id,u,p_name,p_winner,p_exact,p_mode) returning id into j;
 end if;
 return jsonb_build_object('status','queued','job_id',j,'message','In wachtrij bij GitHub. Je toernooi wordt automatisch aangemaakt zodra de bron is opgehaald. Dit kan enkele minuten duren.');
end $$;
create function public.request_mastercaller_game(p_url text,p_name text default null,p_winner integer default 1,p_exact integer default 3,p_mode text default 'replacement') returns jsonb language sql security invoker set search_path='' as $$select predict_private.request_mastercaller_game(p_url,p_name,p_winner,p_exact,p_mode)$$;
create function predict_private.mastercaller_creation_status(p_job uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 perform predict_private.ko_admin();
 select jsonb_build_object('status',j.status,'id',j.tournament_id,'name',t.name,'participants',cardinality(k.roster),'matches',(select count(*) from public.matches where tournament_id=t.id),'error',j.error) into result from predict_private.mastercaller_create_jobs j left join public.tournaments t on t.id=j.tournament_id left join predict_private.knockout_tournaments k on k.tournament_id=t.id where j.id=p_job and j.actor=auth.uid();
 if result is null then raise exception 'Aanvraag niet gevonden' using errcode='42501';end if;return result;
end $$;
create function public.get_mastercaller_creation_status(p_job uuid) returns jsonb language sql security invoker set search_path='' as $$select predict_private.mastercaller_creation_status(p_job)$$;
revoke all on function predict_private.request_mastercaller_game(text,text,integer,integer,text),public.request_mastercaller_game(text,text,integer,integer,text),predict_private.mastercaller_creation_status(uuid),public.get_mastercaller_creation_status(uuid) from public,anon;
grant execute on function predict_private.request_mastercaller_game(text,text,integer,integer,text),public.request_mastercaller_game(text,text,integer,integer,text),predict_private.mastercaller_creation_status(uuid),public.get_mastercaller_creation_status(uuid) to authenticated;
create function predict_private.claim_mastercaller_creations() returns jsonb language plpgsql security definer set search_path='' as $$declare j record;items jsonb:='[]';l uuid;begin
 for j in select * from predict_private.mastercaller_create_jobs where status='queued' or status='running' and claimed_at<now()-interval '5 minutes' order by created_at limit 3 for update skip locked loop
  l:=gen_random_uuid();update predict_private.mastercaller_create_jobs set status='running',lease=l,claimed_at=now() where id=j.id;
  items:=items||jsonb_build_array(jsonb_build_object('kind','create','job_id',j.id,'lease',l,'url',j.url));
 end loop;return items;
end $$;
create function public.claim_mastercaller_creations() returns jsonb language sql security invoker set search_path='' as $$select predict_private.claim_mastercaller_creations()$$;
create function predict_private.finish_mastercaller_creation(p_job uuid,p_lease uuid,p_snapshot jsonb,p_error text) returns jsonb language plpgsql security definer set search_path='' as $$
declare j predict_private.mastercaller_create_jobs%rowtype;tid uuid;old_actor text:=current_setting('request.jwt.claim.sub',true);problem text:=p_error;
begin
 select * into j from predict_private.mastercaller_create_jobs where id=p_job for update;
 if not found or j.status<>'running' or j.lease is distinct from p_lease or j.claimed_at<now()-interval '5 minutes' then raise exception 'Verouderde ophaalactie';end if;
 if problem is null then
  begin
   if predict_private.mastercaller_url(p_snapshot->>'url') is distinct from j.url then raise exception 'Verkeerde bron';end if;
   perform predict_private.cache_mastercaller(p_snapshot);
   -- Recheck the original queued administrator's live role before acting on that exact request.
   perform set_config('request.jwt.claim.sub',j.actor::text,true);
   tid:=predict_private.create_mastercaller_game(p_snapshot,j.name,j.winner_points,j.exact_points,j.mode);
  exception when others then problem:=left(sqlerrm,300);end;
  perform set_config('request.jwt.claim.sub',coalesce(old_actor,''),true);
 end if;
 update predict_private.mastercaller_create_jobs set status=case when problem is null then 'done' else 'failed' end,tournament_id=tid,error=left(problem,300),lease=null where id=j.id;
 return jsonb_build_object('status',case when problem is null then 'done' else 'failed' end,'id',tid);
end $$;
create function public.finish_mastercaller_creation(p_job uuid,p_lease uuid,p_snapshot jsonb,p_error text default null) returns jsonb language sql security invoker set search_path='' as $$select predict_private.finish_mastercaller_creation(p_job,p_lease,p_snapshot,p_error)$$;
revoke all on function predict_private.claim_mastercaller_creations(),public.claim_mastercaller_creations(),predict_private.finish_mastercaller_creation(uuid,uuid,jsonb,text),public.finish_mastercaller_creation(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function predict_private.claim_mastercaller_creations(),public.claim_mastercaller_creations(),predict_private.finish_mastercaller_creation(uuid,uuid,jsonb,text),public.finish_mastercaller_creation(uuid,uuid,jsonb,text) to service_role;
alter table predict_private.mastercaller_sources add column fetch_requested boolean not null default false;
create function predict_private.request_mastercaller_refresh(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform predict_private.ko_admin();perform 1 from predict_private.mastercaller_sources where tournament_id=p_id for update;
 if not found then raise exception 'Kies een Mastercaller-toernooi';end if;
 if predict_private.mc_final_finished(p_id) then return jsonb_build_object('message','Finale afgerond — ophalen gestopt.','processed',0);end if;
 update predict_private.mastercaller_sources set fetch_requested=true where tournament_id=p_id;
 return jsonb_build_object('message','Ophalen staat in de GitHub-wachtrij. De uitslagen worden na de volgende uitvoering verwerkt.','processed',0);
end $$;
create function public.request_mastercaller_refresh(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select predict_private.request_mastercaller_refresh(p_id)$$;
revoke all on function predict_private.request_mastercaller_refresh(uuid),public.request_mastercaller_refresh(uuid) from public,anon;
grant execute on function predict_private.request_mastercaller_refresh(uuid),public.request_mastercaller_refresh(uuid) to authenticated;
create or replace function public.claim_mastercaller_jobs(p_tournament uuid default null,p_actor uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare cfg record;items jsonb:='[]';newlease uuid;
begin
 if p_tournament is not null and (p_actor is null or not exists(select 1 from public.user_roles where user_id=p_actor and role in('admin','super_admin'))) then raise exception 'Geen beheerdersrechten';end if;
 for cfg in select mc.* from predict_private.mastercaller_sources mc join public.tournaments t on t.id=mc.tournament_id
 where not predict_private.mc_final_finished(t.id)
 and (p_tournament is not null and t.id=p_tournament or p_tournament is null and (mc.fetch_requested or t.status in('published','active')
  and (t.ends_at is null or t.ends_at>now()-interval '1 day') and exists(select 1 from public.matches m where m.tournament_id=t.id and m.home_score is null and m.status in('scheduled','live'))))
 and (mc.last_attempt is null or mc.last_attempt<now()-case when p_tournament is not null or mc.fetch_requested then interval '1 minute' else predict_private.mastercaller_interval(t.id) end)
 order by mc.last_attempt nulls first limit 3 for update of mc skip locked loop
  newlease:=gen_random_uuid();update predict_private.mastercaller_sources set lease=newlease,last_attempt=now(),fetch_requested=false where tournament_id=cfg.tournament_id;
  items:=items||jsonb_build_array(jsonb_build_object('tournament_id',cfg.tournament_id,'url',cfg.url,'lease',newlease,'automatic_setup',cfg.automatic_setup));
 end loop;return items;
end $$;

-- Hosted scheduler: GitHub now drives the same 4h/15m claim checks.
select cron.unschedule(jobid) from cron.job where jobname='predict-mastercaller-test';
