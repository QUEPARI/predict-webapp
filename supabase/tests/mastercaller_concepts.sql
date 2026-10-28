begin;
do $$
declare a uuid:=gen_random_uuid();u uuid:=gen_random_uuid();tid uuid;gid uuid;job jsonb;answer jsonb;snap jsonb;pending jsonb;rules jsonb;expected jsonb;mid uuid;records jsonb;claims jsonb;day text:=((now()+interval '2 days') at time zone 'Europe/Amsterdam')::date::text;
begin
 insert into auth.users(id,email,email_confirmed_at,aud,role) values(a,a||'@concept-qa.invalid',now(),'authenticated','authenticated'),(u,u||'@concept-qa.invalid',now(),'authenticated','authenticated');
 insert into public.user_roles values(a,'admin'),(u,'user');
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 answer:=public.request_mastercaller_game('https://mastercaller.nl/toernooien/qa-concept-lifecycle/2026/uitslagen','QA bronconcept',1,3,'replacement');tid:=(answer->>'id')::uuid;
 if (public.request_mastercaller_game('https://mastercaller.com/tournaments/qa-concept-lifecycle/2026/results','Duplicaat',1,3,'replacement')->>'id')::uuid<>tid then raise exception 'FAIL duplicate concept';end if;
 perform set_config('role','none',true);
 if (select status from public.tournaments where id=tid)<>'draft' then raise exception 'FAIL not a concept';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('role','authenticated',true);
 if exists(select 1 from jsonb_array_elements(public.get_active_tournament_catalog()->'tournaments')x where x->>'id'=tid::text) then raise exception 'FAIL hidden concept visible';end if;
 begin perform public.request_mastercaller_game('https://mastercaller.com/tournaments/qa-denied/2026/results','Forbidden',1,3,'replacement');raise exception 'FAIL ordinary user created';exception when insufficient_privilege then null;end;
 begin perform public.claim_mastercaller_setups();raise exception 'FAIL user claims setup';exception when insufficient_privilege then null;end;
 perform set_config('role','none',true);perform set_config('request.jwt.claim.sub',a::text,true);
 select x into job from jsonb_array_elements(public.claim_mastercaller_setups())x where x->>'tournament_id'=tid::text;
 if job is null then raise exception 'FAIL initial check not queued';end if;
 if exists(select 1 from jsonb_array_elements(public.claim_mastercaller_jobs())x where x->>'tournament_id'=tid::text) then raise exception 'FAIL concept polled for scores';end if;
 snap:=jsonb_build_object('url','https://mastercaller.com/tournaments/qa-concept-lifecycle/2026/results','title','QA','start_date',day,'end_date',day,'format','knockout','ready',true,'roster','["A","B","C","D"]'::jsonb,
 'rounds','[{"order":1,"name":"Halve finales","unit":"legs","first_to":6},{"order":2,"name":"Finale","unit":"legs","first_to":11}]'::jsonb,
 'matches','[{"key":"k:1:1","round":1,"position":1,"home_name":"A","away_name":"B","start":null},{"key":"k:1:2","round":1,"position":2,"home_name":"C","away_name":"D","start":null},{"key":"k:2:1","round":2,"position":1,"home_name":"","away_name":"","start":null}]'::jsonb,'records','[]'::jsonb);
 pending:=jsonb_set(jsonb_set(snap,'{ready}','false'),'{roster}','[]');pending:=jsonb_set(pending,'{reason}','"Eerste ronde nog onbekend"');
 begin perform public.finish_mastercaller_setup(tid,gen_random_uuid(),pending);raise exception 'FAIL stale lease';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 answer:=public.finish_mastercaller_setup(tid,(job->>'lease')::uuid,pending);
 if answer->>'status'<>'waiting' then raise exception 'FAIL waiting state %',answer;end if;
 if (select setup_next_check_at<clock_timestamp()+interval '23 hours 59 minutes' from predict_private.mastercaller_sources where tournament_id=tid) then raise exception 'FAIL not 24h cadence';end if;
 if exists(select 1 from jsonb_array_elements(public.claim_mastercaller_setups())x where x->>'tournament_id'=tid::text) then raise exception 'FAIL duplicate check within 24h';end if;
 perform set_config('role','authenticated',true);perform public.admin_source_lifecycle(tid,'announce');perform set_config('role','none',true);
 if (select status from public.tournaments where id=tid)<>'announced' then raise exception 'FAIL preview';end if;
 begin perform public.admin_source_lifecycle(tid,'publish');raise exception 'FAIL pending publication';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 update predict_private.mastercaller_sources set setup_next_check_at=now(),last_attempt=now()-interval '2 minutes' where tournament_id=tid;
 select x into job from jsonb_array_elements(public.claim_mastercaller_setups())x where x->>'tournament_id'=tid::text;
 answer:=public.finish_mastercaller_setup(tid,(job->>'lease')::uuid,null,'Mastercaller niet bereikbaar (HTTP 418)');
 if answer->>'status'<>'error' then raise exception 'FAIL outage treated as waiting';end if;
 if (select starts_at is null from public.tournaments where id=tid) then raise exception 'FAIL previous metadata lost';end if;
 update predict_private.mastercaller_sources set setup_next_check_at=now(),last_attempt=now()-interval '2 minutes' where tournament_id=tid;
 select x into job from jsonb_array_elements(public.claim_mastercaller_setups())x where x->>'tournament_id'=tid::text;
 answer:=public.finish_mastercaller_setup(tid,(job->>'lease')::uuid,snap);
 if answer->>'status'<>'ready' then raise exception 'FAIL ready %',answer;end if;
 if (select status from public.tournaments where id=tid)<>'announced' or exists(select 1 from public.matches where tournament_id=tid) then raise exception 'FAIL automatic publication';end if;
 select x->'rules' into expected from jsonb_array_elements(public.admin_tournament_catalog())x where x->>'id'=tid::text;
 select jsonb_agg(jsonb_build_object('id',x->>'id','winner_points',10,'exact_points',15)) into rules from jsonb_array_elements(expected)x;
 perform set_config('role','authenticated',true);perform public.admin_save_round_scoring(tid,rules,expected);perform public.admin_source_lifecycle(tid,'publish');perform set_config('role','none',true);
 if (select count(*) from public.matches where tournament_id=tid)<>3 or (select count(*) from public.matches where tournament_id=tid and predictions_enabled)<>2 then raise exception 'FAIL publication or NNB permissions';end if;
 if exists(select 1 from public.round_scoring where tournament_id=tid and winner_points<>10) then raise exception 'FAIL round points overwritten';end if;
 if exists(select 1 from predict_private.mastercaller_write_permits where tournament_id=tid) then raise exception 'FAIL leaked permit';end if;
 -- A later polling pass must keep stable match IDs and never move times earlier.
 select match_id into mid from predict_private.mastercaller_match_map where tournament_id=tid and source_key='k:1:1';
 snap:=jsonb_set(snap,'{matches,0,start}',to_jsonb((now()+interval '4 hours')::text));perform predict_private.sync_mastercaller_schema(tid,snap);
 snap:=jsonb_set(snap,'{matches,0,start}',to_jsonb((now()+interval '2 hours')::text));perform predict_private.sync_mastercaller_schema(tid,snap);
 if (select scheduled_start from public.matches where id=mid)<>now()+interval '4 hours' then raise exception 'FAIL earlier source time';end if;
 -- Group-stage publication requires an explicit first-to when the source omits it.
 answer:=public.request_mastercaller_game('https://mastercaller.com/tournaments/qa-groups-lifecycle/2026/results','QA groepen',1,3,'replacement');gid:=(answer->>'id')::uuid;
 select x into job from jsonb_array_elements(public.claim_mastercaller_setups())x where x->>'tournament_id'=gid::text;
 snap:=jsonb_set(jsonb_set(snap,'{url}','"https://mastercaller.com/tournaments/qa-groups-lifecycle/2026/results"'),'{format}','"groups"');
 snap:=jsonb_set(snap,'{rounds}','[{"order":1,"name":"Groepsfase","unit":"legs","first_to":null},{"order":2,"name":"Finale","unit":"legs","first_to":8}]');
 snap:=jsonb_set(snap,'{matches}','[{"key":"g:AB","round":1,"position":1,"group":"A","home_name":"A","away_name":"B"},{"key":"g:AC","round":1,"position":2,"group":"A","home_name":"A","away_name":"C"},{"key":"g:AD","round":1,"position":3,"group":"A","home_name":"A","away_name":"D"},{"key":"g:BC","round":1,"position":4,"group":"A","home_name":"B","away_name":"C"},{"key":"g:BD","round":1,"position":5,"group":"A","home_name":"B","away_name":"D"},{"key":"g:CD","round":1,"position":6,"group":"A","home_name":"C","away_name":"D"},{"key":"k:1:1","round":2,"position":1,"home_name":"","away_name":""}]');
 answer:=public.finish_mastercaller_setup(gid,(job->>'lease')::uuid,snap);if answer->>'status'<>'ready' then raise exception 'FAIL groups readiness %',answer;end if;
 begin perform public.admin_source_lifecycle(gid,'publish');raise exception 'FAIL guessed group first-to';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform set_config('role','authenticated',true);perform public.admin_source_lifecycle(gid,'publish',5);perform set_config('role','none',true);
 if (select count(*) from public.matches where tournament_id=gid)<>7 or (select count(*) from public.matches where tournament_id=gid and predictions_enabled)<>6 then raise exception 'FAIL group/KO separation';end if;
 answer:=public.get_knockout_schema(gid);if answer->>'format'<>'groups' or jsonb_array_length(answer->'matches')<>7 then raise exception 'FAIL group schema';end if;
end $$;
rollback;
