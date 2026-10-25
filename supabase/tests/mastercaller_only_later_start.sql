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

 if (select scheduled_start from public.matches where id=mid) is not null then raise exception 'FAIL initial NNB';end if;
 src:=jsonb_set(src,'{bracket,0,start}',to_jsonb((now()+interval '3 hours')::text));perform predict_private.sync_mastercaller_schema(tid,src);
 if (select scheduled_start from public.matches where id=mid)<>now()+interval '3 hours' then raise exception 'FAIL NNB to known';end if;
 src:=jsonb_set(src,'{bracket,0,start}',to_jsonb((now()+interval '1 hour')::text));perform predict_private.sync_mastercaller_schema(tid,src);
 if (select scheduled_start from public.matches where id=mid)<>now()+interval '3 hours' then raise exception 'FAIL moved earlier';end if;
 src:=jsonb_set(src,'{bracket,0,start}','null');perform predict_private.sync_mastercaller_schema(tid,src);
 if (select scheduled_start from public.matches where id=mid)<>now()+interval '3 hours' then raise exception 'FAIL known lost';end if;
 src:=jsonb_set(src,'{bracket,0,start}',to_jsonb((now()+interval '4 hours')::text));perform predict_private.sync_mastercaller_schema(tid,src);
 if (select scheduled_start from public.matches where id=mid)<>now()+interval '4 hours' then raise exception 'FAIL later rejected';end if;
 if (select count(*) from public.match_predictions where match_id=mid)<>2 then raise exception 'FAIL predictions lost';end if;
end $$;
rollback;
