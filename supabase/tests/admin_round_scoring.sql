begin;
do $$
declare a uuid:=gen_random_uuid();u uuid:=gen_random_uuid();v uuid:=gen_random_uuid();tid uuid;mid uuid;src jsonb;expected jsonb;rules jsonb;r jsonb;pts bigint;pid uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,email_confirmed_at,aud,role) values(a,a||'@round-qa.invalid',now(),'authenticated','authenticated'),(u,u||'@round-qa.invalid',now(),'authenticated','authenticated'),(v,v||'@round-qa.invalid',now(),'authenticated','authenticated');
 insert into public.user_roles values(a,'admin');
 perform set_config('request.jwt.claim.sub',a::text,true);
 src:=jsonb_build_object('url','https://mastercaller.com/tournaments/european-championship/2026/results','title','QA scoring',
 'start_date',((now()+interval '2 days') at time zone 'Europe/Amsterdam')::date::text,'end_date',((now()+interval '3 days') at time zone 'Europe/Amsterdam')::date::text,
 'roster','["QA A","QA B","QA C","QA D"]'::jsonb,'rounds','[{"order":1,"name":"Semi-finals","unit":"legs","first_to":6},{"order":2,"name":"Final","unit":"legs","first_to":6}]'::jsonb,
 'bracket','[{"order":1,"position":1,"home_name":"QA A","away_name":"QA B","start":null},{"order":1,"position":2,"home_name":"QA C","away_name":"QA D","start":null},{"order":2,"position":1,"home_name":"","away_name":"","start":null}]'::jsonb,'records','[]'::jsonb);
 tid:=public.create_mastercaller_game(src,'QA scoring',1,3,'replacement');
 select match_id into mid from predict_private.knockout_nodes where tournament_id=tid and round_no=1 and position=1;
 insert into public.tournament_entries values(tid,u),(tid,v);
 perform set_config('request.jwt.claim.sub',u::text,true);perform public.submit_match_prediction(mid,6,3);
 perform set_config('request.jwt.claim.sub',v::text,true);perform public.submit_match_prediction(mid,6,4);
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform predict_private.mc_enter(tid);update public.tournaments set starts_at=now()-interval '1 hour' where id=tid;update public.matches set scheduled_start=now()-interval '1 minute',predictions_enabled=false where id=mid;perform predict_private.mc_exit(tid);
 perform public.admin_record_source_result(mid,6,3);
 select x->'rules' into expected from jsonb_array_elements(public.admin_tournament_catalog())x where x->>'id'=tid::text;
 select jsonb_agg(jsonb_build_object('id',x->>'id','winner_points',5,'exact_points',11)) into rules from jsonb_array_elements(expected)x;
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('role','authenticated',true);
 begin perform public.admin_save_round_scoring(tid,rules,expected);raise exception 'FAIL non-admin saved';exception when insufficient_privilege then null;end;
 perform set_config('role','none',true);perform set_config('request.jwt.claim.sub',a::text,true);
 begin perform public.admin_save_round_scoring(tid,'[]',expected);raise exception 'FAIL missing rounds';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.admin_save_round_scoring(tid,jsonb_set(rules,'{0,winner_points}','-1'),expected);raise exception 'FAIL negative points';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.admin_save_round_scoring(tid,jsonb_set(rules,'{0,exact_points}','1.5'),expected);raise exception 'FAIL fractional points';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.admin_save_round_scoring(tid,jsonb_build_array(rules->0,rules->0),expected);raise exception 'FAIL duplicate rounds';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform set_config('role','authenticated',true);r:=public.admin_save_round_scoring(tid,rules,expected);perform set_config('role','none',true);
 if r->>'scored_predictions'<>'2' then raise exception 'FAIL count %',r;end if;
 select earned_points into pts from public.get_tournament_leaderboard(tid) where user_id=u;if pts<>11 then raise exception 'FAIL exact %',pts;end if;
 select earned_points into pts from public.get_tournament_leaderboard(tid) where user_id=v;if pts<>5 then raise exception 'FAIL winner %',pts;end if;
 begin perform public.admin_save_round_scoring(tid,rules,expected);raise exception 'FAIL stale update';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 if exists(select 1 from predict_private.tournament_mutation_permits where tournament_id=tid) or exists(select 1 from predict_private.mastercaller_write_permits where tournament_id=tid) then raise exception 'FAIL permits leaked';end if;
 if (select count(*) from public.match_predictions where match_id=mid)<>2 then raise exception 'FAIL predictions changed';end if;
 begin update public.round_scoring set winner_points=99 where tournament_id=tid;raise exception 'FAIL direct source edit';exception when insufficient_privilege then null;when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 -- Exercise final snapshots and preserve an already included 7-point bonus.
 insert into predict_private.tournament_final_snapshots
 select tid,name,starts_at,ends_at,now(),array[u,v],(select jsonb_agg(case when x->>'user_id'=u::text then jsonb_set(x,'{earned_points}',to_jsonb(18)) else x end) from jsonb_array_elements(predict_private.final_rows(tid,null))x) from public.tournaments where id=tid;
 insert into predict_private.pool_final_snapshots values(pid,tid,'Archived pool',array[v],(select jsonb_agg(x) from jsonb_array_elements(predict_private.final_rows(tid,null))x where x->>'user_id'=v::text));
 expected:=r->'rules';select jsonb_agg(jsonb_build_object('id',x->>'id','winner_points',2,'exact_points',4)) into rules from jsonb_array_elements(expected)x;
 r:=public.admin_save_round_scoring(tid,rules,expected);
 select (x->>'earned_points')::bigint into pts from predict_private.tournament_final_snapshots s,jsonb_array_elements(s.standings)x where s.tournament_id=tid and x->>'user_id'=u::text;
 if pts<>11 then raise exception 'FAIL archived bonus preservation %',pts;end if;
 select (standings->0->>'earned_points')::bigint into pts from predict_private.pool_final_snapshots where pool_id=pid;if pts<>2 then raise exception 'FAIL archived pool %',pts;end if;
 if (select count(*) from predict_private.tournament_management_audit where tournament_id=tid and action='round_scoring_recalculated')<>2 then raise exception 'FAIL audit';end if;
 raise notice 'PASS admin scoring, authorization, source locks, validation, stale updates, live and archived standings, bonus preservation and audit';
end $$;
rollback;
