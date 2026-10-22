begin;
do $test$
declare root_id uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid(); player_id uuid:=gen_random_uuid();
 sport uuid; tid uuid; mid uuid; second_id uuid; final_id uuid; source jsonb; records jsonb; job jsonb; result jsonb;
 day text:=(now() at time zone 'Europe/Amsterdam')::date::text;
begin
 insert into auth.users(id,email,email_confirmed_at,aud,role) values
 (root_id,root_id||'@qa.invalid',now(),'authenticated','authenticated'),
 (admin_id,admin_id||'@qa.invalid',now(),'authenticated','authenticated'),
 (player_id,player_id||'@qa.invalid',now(),'authenticated','authenticated');
 insert into public.profiles(id,username) values(root_id,'qa-root-'||root_id),(admin_id,'qa-admin-'||admin_id),(player_id,'qa-player-'||player_id);
 insert into public.user_roles values(root_id,'super_admin'),(admin_id,'admin'),(player_id,'user');
 perform set_config('request.jwt.claim.sub',player_id::text,true);perform set_config('role','authenticated',true);
 begin perform public.admin_list_accounts();raise exception 'FAIL player directory access';exception when insufficient_privilege then null;end;
 begin perform public.admin_set_account_role(player_id,'admin');raise exception 'FAIL player role escalation';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 if not exists(select 1 from jsonb_array_elements(public.admin_list_accounts()) x where x->>'id'=player_id::text) then raise exception 'FAIL missing user';end if;
 if exists(select 1 from jsonb_array_elements(public.admin_list_accounts()) x where (x->>'can_change_role')::boolean) then raise exception 'FAIL admin role controls';end if;
 begin perform public.admin_set_account_role(player_id,'admin');raise exception 'FAIL admin delegates roles';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',root_id::text,true);
 perform public.admin_set_account_role(player_id,'admin');
 perform set_config('role','none',true);
 if not exists(select 1 from public.user_roles where user_id=player_id and role='admin') then raise exception 'FAIL promotion';end if;
 perform set_config('role','authenticated',true);
 perform public.admin_set_account_role(player_id,'user');
 begin perform public.admin_set_account_role(root_id,'user');raise exception 'FAIL root self-demotion';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.admin_set_account_role(player_id,'super_admin');raise exception 'FAIL new root allowed';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.admin_set_account_role(gen_random_uuid(),'admin');raise exception 'FAIL unknown user';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 begin update public.user_roles set role='admin' where user_id=player_id;exception when insufficient_privilege then null;end;
 perform set_config('role','none',true);
 if exists(select 1 from public.user_roles where user_id=player_id and role<>'user') then raise exception 'FAIL direct role write';end if;
 if (select count(*) from predict_private.account_role_audit where target=player_id)<>2 then raise exception 'FAIL role audit';end if;
 select id into sport from public.sports where slug='darts';
 source:=jsonb_build_object('url','https://mastercaller.com/tournaments/european-championship/2026/results','title','QA fallback','start_date',day,'end_date',day,
 'roster','["QA A","QA B","QA C","QA D"]'::jsonb,'rounds','[{"order":1,"name":"Semi-finals","unit":"legs","first_to":6},{"order":2,"name":"Final","unit":"legs","first_to":6}]'::jsonb,
 'bracket',jsonb_build_array(jsonb_build_object('order',1,'position',1,'home_name','QA A','away_name','QA B','start',now()+interval '1 hour','date',day),jsonb_build_object('order',1,'position',2,'home_name','QA C','away_name','QA D','start',null,'date',day),jsonb_build_object('order',2,'position',1,'home_name','','away_name','','start',now()+interval '2 hours','date',day)),'records','[]'::jsonb);
 perform set_config('role','authenticated',true);
 tid:=public.create_mastercaller_game(source,'QA fallback',1,3,'replacement');
 perform set_config('role','none',true);
 select match_id into mid from predict_private.knockout_nodes where tournament_id=tid and round_no=1 and position=1;
 select match_id into second_id from predict_private.knockout_nodes where tournament_id=tid and round_no=1 and position=2;
 select match_id into final_id from predict_private.knockout_nodes where tournament_id=tid and round_no=2;
 perform set_config('role','authenticated',true);
 begin perform public.admin_record_source_result(mid,6,3);raise exception 'FAIL future result';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',player_id::text,true);perform public.join_tournament(tid);perform public.submit_match_prediction(mid,6,3);
 begin perform public.admin_record_source_result(mid,6,3);raise exception 'FAIL player result';exception when insufficient_privilege then null;end;
 perform set_config('role','none',true);
 source:=jsonb_set(source,'{bracket,0,start}',to_jsonb((now()-interval '1 hour')::text));perform predict_private.sync_mastercaller_schema(tid,source);
 perform set_config('request.jwt.claim.sub',admin_id::text,true);perform set_config('role','authenticated',true);
 begin perform public.admin_record_source_result(mid,5,3);raise exception 'FAIL invalid format';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.admin_record_source_result(final_id,6,3);raise exception 'FAIL unknown participants';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform public.admin_record_source_result(mid,6,3);
 -- Date-only source fixtures are supported without inventing an actual start.
 perform public.admin_record_source_result(second_id,6,2);
 if (select earned_points from public.get_tournament_leaderboard(tid) where user_id=player_id)<>3 then raise exception 'FAIL scoring';end if;
 begin perform public.edit_knockout(tid,'roster',null,jsonb_build_object('names',source->'roster'));raise exception 'FAIL schema lock relaxed';exception when insufficient_privilege then null;end;
 perform set_config('role','none',true);
 if not exists(select 1 from predict_private.knockout_nodes where match_id=final_id and home_slot=1 and away_slot=3) then raise exception 'FAIL advancement';end if;
 if exists(select 1 from predict_private.mastercaller_write_permits) then raise exception 'FAIL leaked manual permit';end if;
 if not exists(select 1 from public.match_predictions where match_id=mid and user_id=player_id and home_score=6 and away_score=3) then raise exception 'FAIL prediction lost';end if;
 records:=jsonb_build_array(jsonb_build_object('depth',1,'round','Semi-finals','home_name','QA A','away_name','QA B','home_score',6,'away_score',3,'date',day));
 update predict_private.mastercaller_sources set last_attempt=now()-interval '5 hours' where tournament_id=tid;
 job:=public.claim_mastercaller_jobs(tid,admin_id)->0;
 result:=public.finish_mastercaller_job(tid,(job->>'lease')::uuid,records,null,source);
 if (result->>'unchanged')::integer<>1 then raise exception 'FAIL identical source';end if;
 update predict_private.mastercaller_sources set last_attempt=now()-interval '5 hours' where tournament_id=tid;
 job:=public.claim_mastercaller_jobs(tid,admin_id)->0;
 result:=public.finish_mastercaller_job(tid,(job->>'lease')::uuid,jsonb_set(records,'{0,away_score}','4'),null,source);
 if jsonb_array_length(result->'issues')<>1 or not exists(select 1 from predict_private.mastercaller_manual_results where match_id=mid and conflict and source_away_score=4) then raise exception 'FAIL source conflict not recorded';end if;
 if not exists(select 1 from public.matches where id=mid and home_score=6 and away_score=3) then raise exception 'FAIL manual overwritten';end if;
 perform set_config('role','authenticated',true);
 if not (public.get_tournament_score_source(tid)->'manual_results' @> jsonb_build_array(jsonb_build_object('match_id',mid,'conflict',true))) then raise exception 'FAIL conflict hidden';end if;
 perform set_config('request.jwt.claim.sub',player_id::text,true);perform public.submit_match_prediction(final_id,6,3);
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 begin perform public.admin_record_source_result(mid,3,6);raise exception 'FAIL changed winner after next prediction';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform set_config('role','none',true);
 if exists(select 1 from predict_private.mastercaller_write_permits) then raise exception 'FAIL failed mutation leaked permit';end if;
 update predict_private.mastercaller_sources set last_attempt=now()-interval '5 hours' where tournament_id=tid;
 job:=public.claim_mastercaller_jobs(tid,admin_id)->0;
 result:=public.finish_mastercaller_job(tid,(job->>'lease')::uuid,records,null,source);
 if exists(select 1 from predict_private.mastercaller_manual_results where match_id=mid and conflict) then raise exception 'FAIL resolved conflict remains';end if;
 perform set_config('role','anon',true);
 begin perform public.admin_list_accounts();raise exception 'FAIL anon list';exception when insufficient_privilege then null;end;
 begin perform public.admin_record_source_result(mid,6,3);raise exception 'FAIL anon result';exception when insufficient_privilege then null;end;
end $test$;
rollback;
