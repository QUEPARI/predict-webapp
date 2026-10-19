begin;
do $$
declare a uuid:=gen_random_uuid();sport uuid;tid uuid;job jsonb;source jsonb;result jsonb;mid uuid;day text:=((now()+interval '1 day') at time zone 'Europe/Amsterdam')::date::text;
begin
 insert into public.user_roles values(a,'admin');select id into sport from public.sports where slug='darts';
 source:=jsonb_build_object('url','https://mastercaller.com/tournaments/european-championship/2026/results','title','QA automated','start_date',day,'end_date',day,
 'roster','["QA A","QA B","QA C","QA D"]'::jsonb,'rounds','[{"order":1,"name":"Semi-finals","unit":"legs","first_to":6},{"order":2,"name":"Final","unit":"legs","first_to":6}]'::jsonb,
 'bracket',jsonb_build_array(jsonb_build_object('order',1,'position',1,'home_name','QA A','away_name','QA B','start',null,'date',day),jsonb_build_object('order',1,'position',2,'home_name','QA C','away_name','QA D','start',null,'date',day),jsonb_build_object('order',2,'position',1,'home_name','','away_name','','start',null,'date',null)), 'records','[]'::jsonb);
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 tid:=public.create_mastercaller_game(source,null,1,3,'replacement');
 perform set_config('role','none',true);
 if (select not is_locked from public.tournament_scoring where tournament_id=tid) then raise exception 'FAIL source scoring unlocked';end if;
 if (select status<>'published' from public.tournaments where id=tid) then raise exception 'FAIL auto publication';end if;
 if (select count(*) from public.matches where tournament_id=tid)<>3 then raise exception 'FAIL auto bracket';end if;
 if exists(select 1 from public.matches where tournament_id=tid and (scheduled_start is not null or predictions_enabled is distinct from false)) then raise exception 'FAIL TBA opened';end if;
 if predict_private.mastercaller_interval(tid)<>interval '4 hours' then raise exception 'FAIL pre-start interval';end if;
 update predict_private.mastercaller_sources set last_attempt=now()-interval '1 hour' where tournament_id=tid;
 if jsonb_array_length(public.claim_mastercaller_jobs())<>0 then raise exception 'FAIL pre-start cooldown';end if;
 update predict_private.mastercaller_sources set last_attempt=now()-interval '241 minutes' where tournament_id=tid;
 if jsonb_array_length(public.claim_mastercaller_jobs())<>1 then raise exception 'FAIL pre-start due';end if;
 -- A newly published source time opens the known first-round pair automatically.
 source:=jsonb_set(source,'{bracket,0,start}',to_jsonb((now()+interval '2 hours')::text));
 perform predict_private.sync_mastercaller_schema(tid,source);
 select match_id into mid from predict_private.knockout_nodes where tournament_id=tid and round_no=1 and position=1;
 if (select not predictions_enabled or not start_time_confirmed from public.matches where id=mid) then raise exception 'FAIL source schedule opening';end if;
 -- An elapsed known start moves polling to fifteen minutes.
 update public.matches set scheduled_start=now()-interval '1 hour',predictions_enabled=false where id=mid;
 if predict_private.mastercaller_interval(tid)<>interval '15 minutes' then raise exception 'FAIL started interval';end if;
 update predict_private.mastercaller_sources set last_attempt=now()-interval '14 minutes' where tournament_id=tid;
 if jsonb_array_length(public.claim_mastercaller_jobs())<>0 then raise exception 'FAIL active cooldown';end if;
 update predict_private.mastercaller_sources set last_attempt=now()-interval '16 minutes' where tournament_id=tid;
 if jsonb_array_length(public.claim_mastercaller_jobs())<>1 then raise exception 'FAIL active due';end if;
 -- A TBA time is removed without ever inventing 00:00 as a match start.
 source:=jsonb_set(source,'{bracket,0,start}','null');perform predict_private.sync_mastercaller_schema(tid,source);
 if (select scheduled_start is not null or predictions_enabled is distinct from false from public.matches where id=mid) then raise exception 'FAIL unknown source time';end if;
 -- With date-only start info, completed source results can still be processed.
 update public.tournaments set starts_at=now()-interval '1 day',ends_at=now()+interval '1 day' where id=tid;
 update predict_private.mastercaller_sources set last_attempt=now()-interval '16 minutes' where tournament_id=tid;
 job:=public.claim_mastercaller_jobs()->0;
 result:=public.finish_mastercaller_job(tid,(job->>'lease')::uuid,jsonb_build_array(jsonb_build_object('depth',1,'round','Semi-finals','home_name','QA A','away_name','QA B','home_score',6,'away_score',3,'date',(now() at time zone 'Europe/Amsterdam')::date)),null,source);
 if (result->>'applied')::int<>1 then raise exception 'FAIL auto date-only score %',result;end if;
 if (select scheduled_start is not null or actual_start is not null or home_score<>6 or away_score<>3 from public.matches where id=mid) then raise exception 'FAIL fabricated start or missing result';end if;
 -- Once all results exist there are no jobs, even after a long interval.
 update predict_private.mastercaller_sources set last_attempt=now()-interval '5 hours' where tournament_id=tid;
 update public.matches set status='cancelled',predictions_enabled=false where tournament_id=tid and home_score is null;
 if jsonb_array_length(public.claim_mastercaller_jobs())<>0 then raise exception 'FAIL ended tournament keeps polling';end if;
end $$;
rollback;
