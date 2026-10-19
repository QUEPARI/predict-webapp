begin;
do $$
declare a uuid:=gen_random_uuid();sport uuid;tid uuid;manual uuid;mid uuid;job jsonb;source jsonb;result jsonb;records jsonb;start_at timestamptz:=now()-interval '1 hour';day text:=((now()-interval '1 hour') at time zone 'Europe/Amsterdam')::date::text;
begin
 insert into public.user_roles values(a,'admin');select id into sport from public.sports where slug='darts';
 source:=jsonb_build_object('url','https://mastercaller.com/tournaments/european-championship/2026/results','title','QA locked','start_date',day,'end_date',(now() at time zone 'Europe/Amsterdam')::date::text,
 'roster','["QA A","QA B","QA C","QA D"]'::jsonb,'rounds','[{"order":1,"name":"Semi-finals","unit":"legs","first_to":6},{"order":2,"name":"Final","unit":"legs","first_to":6}]'::jsonb,
 'bracket',jsonb_build_array(jsonb_build_object('order',1,'position',1,'home_name','QA A','away_name','QA B','start',start_at,'date',day),jsonb_build_object('order',1,'position',2,'home_name','QA C','away_name','QA D','start',start_at,'date',day),jsonb_build_object('order',2,'position',1,'home_name','','away_name','','start',null,'date',null)), 'records','[]'::jsonb);
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 tid:=public.create_mastercaller_game(source,'QA locked',1,3,'replacement');
 if not (public.get_knockout_schema(tid)->'score_source'->>'locked')::boolean then raise exception 'FAIL schema lock flag';end if;
 if not (public.get_tournament_score_source(tid)->>'automatic_setup')::boolean then raise exception 'FAIL source ownership flag';end if;
 perform set_config('role','none',true);
 select match_id into mid from predict_private.knockout_nodes where tournament_id=tid and round_no=1 and position=1;
 if exists(select 1 from predict_private.mastercaller_write_permits) then raise exception 'FAIL create leaked permit';end if;
 perform set_config('role','authenticated',true);
 begin perform public.edit_knockout(tid,'roster',null,'{"names":["Changed","QA B","QA C","QA D"]}');raise exception 'FAIL automatic roster editable';exception when insufficient_privilege then null;end;
 begin perform public.edit_knockout(tid,'schedule',mid,jsonb_build_object('start',now()+interval '1 day','unit','legs','first_to',6));raise exception 'FAIL automatic schedule editable';exception when insufficient_privilege then null;end;
 begin perform public.admin_record_match_result(mid,6,3);raise exception 'FAIL legacy result bypass';exception when insufficient_privilege then null;end;
 begin perform public.edit_knockout(tid,'close',mid);raise exception 'FAIL manual status bypass';exception when insufficient_privilege then null;end;
 begin perform public.manage_tournament(tid,'draft');raise exception 'FAIL draft bypass';exception when insufficient_privilege then null;end;
 begin perform public.manage_tournament(tid,'metadata',jsonb_build_object('name','QA locked','start',now()+interval '1 day','end',now()+interval '2 days'));raise exception 'FAIL metadata planning bypass';exception when insufficient_privilege then null;end;
 begin perform public.set_tournament_score_source(tid,'manual');raise exception 'FAIL source conversion bypass';exception when insufficient_privilege then null;end;
 begin perform predict_private.mc_enter(tid);raise exception 'FAIL permit exposed';exception when insufficient_privilege then null;end;
 -- Ordinary editorial/lifecycle actions remain usable.
 perform public.manage_tournament(tid,'metadata',jsonb_build_object('name','QA renamed','start',(day::date::timestamp at time zone 'Europe/Amsterdam'),'end',(((now() at time zone 'Europe/Amsterdam')::date+1)::timestamp at time zone 'Europe/Amsterdam')));
 perform public.manage_tournament(tid,'pause');perform public.manage_tournament(tid,'resume');
 manual:=public.create_knockout_game('QA manual',sport,'players',array['M A','M B'],now()+interval '1 day','[{"unit":"legs","first_to":6,"winner_points":1,"exact_points":3}]','replacement',now()+interval '2 days','draft');
 perform public.edit_knockout(manual,'roster',null,'{"names":["Manual corrected","M B"]}');
 if (public.get_knockout_schema(manual)->'score_source'->>'locked')::boolean then raise exception 'FAIL manual incorrectly locked';end if;
 perform set_config('role','none',true);
 update predict_private.mastercaller_sources set last_attempt=now()-interval '5 hours' where tournament_id=tid;
 job:=public.claim_mastercaller_jobs(tid,a)->0;
 records:=jsonb_build_array(jsonb_build_object('depth',1,'round','Semi-finals','home_name','QA A','away_name','QA B','home_score',6,'away_score',3,'date',day),jsonb_build_object('depth',1,'round','Semi-finals','home_name','QA C','away_name','QA D','home_score',6,'away_score',2,'date',day));
 result:=public.finish_mastercaller_job(tid,(job->>'lease')::uuid,records,null,source);
 if (result->>'applied')::int<>2 then raise exception 'FAIL source worker blocked by lock %',result;end if;
 source:=jsonb_set(jsonb_set(source,'{bracket,2,home_name}','"QA A"'),'{bracket,2,away_name}','"QA C"');
 update predict_private.mastercaller_sources set last_attempt=now()-interval '5 hours' where tournament_id=tid;
 job:=public.claim_mastercaller_jobs(tid,a)->0;
 result:=public.finish_mastercaller_job(tid,(job->>'lease')::uuid,jsonb_build_array(jsonb_build_object('depth',0,'round','Final','home_name','QA A','away_name','QA C','home_score',6,'away_score',4,'date',(now() at time zone 'Europe/Amsterdam')::date)),null,source);
 if (result->>'applied')::int<>1 or not predict_private.mc_final_finished(tid) then raise exception 'FAIL source final %',result;end if;
 -- Even an earlier missing score must not keep polling after the final.
 perform predict_private.mc_enter(tid);
 insert into public.matches(tournament_id,round_id,home_name,away_name,scheduled_start,score_unit,first_to) select tid,round_id,'Extra pending A','Extra pending B',start_at,'legs',6 from public.matches where id=mid;
 perform predict_private.mc_exit(tid);
 update predict_private.mastercaller_sources set last_attempt=now()-interval '5 hours' where tournament_id=tid;
 if jsonb_array_length(public.claim_mastercaller_jobs())<>0 or jsonb_array_length(public.claim_mastercaller_jobs(tid,a))<>0 then raise exception 'FAIL fetching after final';end if;
 perform set_config('role','authenticated',true);
 if not (public.get_tournament_score_source(tid)->>'stopped')::boolean then raise exception 'FAIL stop flag';end if;
 perform public.manage_tournament(tid,'delete',jsonb_build_object('confirm_empty',true,'expected',(select x->'counts' from jsonb_array_elements(public.admin_tournament_catalog())x where x->>'id'=tid::text)));
 perform set_config('role','none',true);
 if exists(select 1 from predict_private.mastercaller_write_permits) then raise exception 'FAIL leaked write permit';end if;
end $$;
rollback;
