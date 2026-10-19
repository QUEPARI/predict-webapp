begin;
do $$
declare a uuid:=gen_random_uuid();u uuid:=gen_random_uuid();tid uuid;mid uuid;othermid uuid;source jsonb;day text:=((now()+interval '2 days') at time zone 'Europe/Amsterdam')::date::text;v jsonb;prior_status text;
begin
 insert into public.user_roles values(a,'admin');
 source:=jsonb_build_object('url','https://mastercaller.com/tournaments/european-championship/2026/results','title','QA NNB','start_date',day,'end_date',day,
 'roster','["QA A","QA B","QA C","QA D"]'::jsonb,'rounds','[{"order":1,"name":"Semi-finals","unit":"legs","first_to":6},{"order":2,"name":"Final","unit":"legs","first_to":6}]'::jsonb,
 'bracket',jsonb_build_array(jsonb_build_object('order',1,'position',1,'home_name','QA A','away_name','QA B','start',null,'date',day),jsonb_build_object('order',1,'position',2,'home_name','QA C','away_name','QA D','start',null,'date',day),jsonb_build_object('order',2,'position',1,'home_name','','away_name','','start',null,'date',null)), 'records','[]'::jsonb);
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 tid:=public.create_mastercaller_game(source,'QA NNB',1,3,'replacement');
 perform set_config('role','none',true);
 select match_id into mid from predict_private.knockout_nodes where tournament_id=tid and round_no=1 and position=1;
 select match_id into othermid from predict_private.knockout_nodes where tournament_id=tid and round_no=1 and position=2;
 if predict_private.prediction_time_open(gen_random_uuid(),null,false) then raise exception 'FAIL manual null timestamp permitted';end if;
 if (select scheduled_start is not null or not source_time_pending or start_time_confirmed or not predictions_enabled from public.matches where id=mid) then raise exception 'FAIL NNB not open or fabricated time';end if;
 if exists(select 1 from public.matches where tournament_id=tid and round_id in(select id from public.tournament_rounds where tournament_id=tid and round_order=2) and predictions_enabled) then raise exception 'FAIL unknown players opened';end if;
 insert into public.tournament_entries values(tid,u);
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('role','authenticated',true);
 perform public.submit_match_prediction(mid,6,3);perform public.submit_match_prediction(mid,6,2);
 begin perform public.submit_match_prediction(mid,5,2);raise exception 'FAIL invalid score accepted';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 v:=public.get_tournament_prediction_counts();
 if not exists(select 1 from jsonb_array_elements(v->'tournaments')x where (x->>'id')::uuid=tid and (x->>'open_count')::int=2 and (x->>'remaining_count')::int=1) then raise exception 'FAIL NNB counts %',v;end if;
 begin perform public.manage_tournament(tid,'archive','{}');raise exception 'FAIL ordinary user archive';exception when insufficient_privilege then null;end;
 perform set_config('role','none',true);perform set_config('request.jwt.claim.sub',a::text,true);
 begin perform public.manage_tournament(tid,'archive','{}');raise exception 'FAIL incomplete archive';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 -- Known future time arrives: the prediction survives and the individual deadline applies.
 source:=jsonb_set(source,'{bracket,0,start}',to_jsonb((now()+interval '1 hour')::text));perform predict_private.sync_mastercaller_schema(tid,source);
 if (select count(*) from public.match_predictions where match_id=mid)<>1 then raise exception 'FAIL prediction lost';end if;
 perform predict_private.mc_enter(tid);update public.matches set scheduled_start=now()-interval '1 minute',predictions_enabled=false where id=mid;perform predict_private.mc_exit(tid);
 source:=jsonb_set(source,'{bracket,0,start}','null');perform predict_private.sync_mastercaller_schema(tid,source);
 if (select predictions_enabled or not prediction_window_closed from public.matches where id=mid) then raise exception 'FAIL expired deadline reopened as NNB';end if;
 perform predict_private.sync_mastercaller_schema(tid,source);
 if (select predictions_enabled from public.matches where id=mid) then raise exception 'FAIL repeated NNB reopened';end if;
 -- Unknown times close at the tournament start, on the server as well as in the UI.
 perform predict_private.mc_enter(tid);update public.tournaments set starts_at=now()-interval '1 hour',ends_at=now()+interval '1 day' where id=tid;perform predict_private.mc_exit(tid);
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('role','authenticated',true);
 begin perform public.submit_match_prediction(othermid,6,1);raise exception 'FAIL NNB accepted after fallback deadline';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform set_config('role','none',true);perform set_config('request.jwt.claim.sub',a::text,true);
 -- Complete all games and archive management only: no public status or end date change.
 perform predict_private.mc_enter(tid);
 update public.tournaments set ends_at=now()-interval '1 hour' where id=tid;
 update public.matches set predictions_enabled=false,home_score=6,away_score=2,status='finished' where id=mid;
 update public.matches set predictions_enabled=false,home_score=6,away_score=2,status='finished' where id=othermid;
 update public.matches set predictions_enabled=false,home_score=6,away_score=2,status='finished' where tournament_id=tid and home_score is null;
 perform predict_private.mc_exit(tid);
 select status into prior_status from public.tournaments where id=tid;
 perform public.manage_tournament(tid,'archive','{}');
 if (select not admin_archived or status<>prior_status or ends_at+interval '168 hours'<=now() from public.tournaments where id=tid) then raise exception 'FAIL archive shortened player visibility';end if;
 v:=public.admin_tournament_catalog();
 if not exists(select 1 from jsonb_array_elements(v)x where (x->>'id')::uuid=tid and (x->>'admin_archived')::boolean and (x->>'finished')::boolean) then raise exception 'FAIL archive catalog';end if;
 v:=public.get_tournament_prediction_counts();
 if not exists(select 1 from jsonb_array_elements(v->'tournaments')x where (x->>'id')::uuid=tid and (x->>'completed')::boolean) then raise exception 'FAIL completed badge';end if;
 perform public.manage_tournament(tid,'unarchive','{}');if (select admin_archived from public.tournaments where id=tid) then raise exception 'FAIL unarchive';end if;
end $$;
rollback;
