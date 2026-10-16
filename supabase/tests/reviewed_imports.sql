begin;
-- Test-only helper stages fictitious provider data. It disappears on rollback.
create function pg_temp.stage_darts(a uuid,t uuid,k text,p jsonb) returns uuid language plpgsql as $$
declare run uuid; item uuid;
begin
  insert into public.sports_sync_runs(provider,sync_type,metadata) values('dartsapi',k,jsonb_build_object('flow','reviewed_v1','requested_by',a,'tournament_id',t)) returning id into run;
  perform public.finish_darts_import(run,a,jsonb_build_array(p));
  select id into strict item from predict_private.darts_import_items where kind=k and external_id=p->>'external_id' and payload_hash=encode(extensions.digest(p::text,'sha256'),'hex');
  return item;
end $$;
do $$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); t uuid; r uuid; run uuid; item uuid; m uuid; other uuid;
  f jsonb; result jsonb; data jsonb; before_count integer; mid uuid; prediction uuid; future uuid; snap text;
begin
  select id into strict t from public.tournaments where name='Predict QA - dartstest';
  select id into strict r from public.tournament_rounds where tournament_id=t order by round_order limit 1;
  insert into auth.users(id,email,email_confirmed_at,aud,role) values(a,a||'@predict-import-qa.invalid',now(),'authenticated','authenticated'),(b,b||'@predict-import-qa.invalid',now(),'authenticated','authenticated');
  insert into public.profiles(id,username,display_name) values(a,a::text,'QA importbeheerder'),(b,b::text,'QA deelnemer');
  insert into public.user_roles values(a,'admin'),(b,'user');
  perform set_config('request.jwt.claim.sub',b::text,true);perform set_config('role','authenticated',true);
  begin perform public.begin_darts_import(t,'fixtures');raise exception 'FAIL ordinary import';exception when insufficient_privilege then null;end;
  begin perform public.list_darts_imports(t);raise exception 'FAIL ordinary queue read';exception when insufficient_privilege then null;end;
  begin perform 1 from predict_private.darts_import_items;raise exception 'FAIL direct queue read';exception when insufficient_privilege then null;end;
  begin perform public.finish_darts_import(gen_random_uuid(),a,'[]');raise exception 'FAIL browser forges provider';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',a::text,true);run:=public.begin_darts_import(t,'fixtures');
  begin perform public.begin_darts_import(t,'fixtures');raise exception 'FAIL import budget';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
  f:=jsonb_build_object('external_id','fx_qa_'||replace(a::text,'-',''),'home_name','QA Import A','away_name','QA Import B','played_on',to_char(now()+interval '1 day','YYYY-MM-DD'),'scheduled_start',to_char(now()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'date_confirmed',true,'round','QA ronde','competition','QA bron');
  perform set_config('role','service_role',true);data:=public.finish_darts_import(run,a,jsonb_build_array(f));
  if (data->>'queued')::int<>1 then raise exception 'FAIL stage';end if;
  perform set_config('role','postgres',true);select id into strict item from predict_private.darts_import_items where run_id=run;
  if exists(select 1 from public.external_match_ids where external_id=f->>'external_id') then raise exception 'FAIL staging touched matches';end if;
  mid:=pg_temp.stage_darts(a,t,'fixtures',f);if mid<>item then raise exception 'FAIL dedup';end if;
  perform set_config('role','authenticated',true);
  begin perform public.review_darts_import(item,'apply',null,r,'legs',6,false);raise exception 'FAIL unchecked import';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
  data:=public.review_darts_import(item,'apply',null,r,'legs',6,true);m:=(data->>'match_id')::uuid;
  if m is null or data->>'state'<>'applied' then raise exception 'FAIL fixture review';end if;
  data:=public.review_darts_import(item,'apply',null,r,'legs',6,true);if (data->>'match_id')::uuid<>m then raise exception 'FAIL replay';end if;
  perform set_config('role','postgres',true);
  if not exists(select 1 from public.matches where id=m and needs_review and not predictions_enabled and not start_time_confirmed) then raise exception 'FAIL fixture opened predictions';end if;
  item:=pg_temp.stage_darts(a,t,'fixtures',f||jsonb_build_object('round','Gewijzigde bronronde'));
  perform set_config('role','authenticated',true);data:=public.review_darts_import(item,'apply',null,r,'legs',6,true);
  if data->>'state'<>'conflict' then raise exception 'FAIL changed fixture overwritten';end if;
  perform set_config('role','postgres',true);
  insert into public.tournament_entries(tournament_id,user_id) values(t,b);
  update public.matches set needs_review=false,start_time_confirmed=true,predictions_enabled=true where id=m;
  insert into public.match_predictions(match_id,user_id,home_score,away_score) values(m,b,4,6) returning id into prediction;
  update public.matches set scheduled_start=now()-interval '1 hour',predictions_enabled=false where id=m;
  result:=jsonb_build_object('external_id','mt_qa_'||replace(a::text,'-',''),'home_name','QA Import B','away_name','QA Import A','home_score',6,'away_score',3,'played_on',to_char(now()-interval '1 hour','YYYY-MM-DD'),'source_status','settled','round','QA ronde','competition','QA bron');
  item:=pg_temp.stage_darts(a,t,'results',result);
  perform set_config('role','authenticated',true);data:=public.review_darts_import(item,'apply',m,r,'legs',null,true);
  if data->>'state'<>'applied' then raise exception 'FAIL result review';end if;
  perform set_config('request.jwt.claim.sub',b::text,true);
  if not exists(select 1 from public.get_my_match_points(t) where match_id=m and earned_points=1) then raise exception 'FAIL preserved one-point scoring';end if;
  perform set_config('role','postgres',true);
  if not exists(select 1 from public.matches where id=m and home_score=3 and away_score=6 and status='finished' and not predictions_enabled) then raise exception 'FAIL reversed result order';end if;
  item:=pg_temp.stage_darts(a,t,'results',result||jsonb_build_object('away_score',4));
  perform set_config('role','authenticated',true);perform set_config('request.jwt.claim.sub',a::text,true);
  data:=public.review_darts_import(item,'apply',m,r,'legs',null,true);if data->>'state'<>'conflict' then raise exception 'FAIL conflicting score';end if;
  perform set_config('role','postgres',true);
  if not exists(select 1 from public.matches where id=m and home_score=3 and away_score=6) then raise exception 'FAIL existing score changed';end if;
  if not exists(select 1 from public.match_predictions where id=prediction and home_score=4 and away_score=6) then raise exception 'FAIL prediction changed';end if;
  item:=pg_temp.stage_darts(a,t,'results',result||jsonb_build_object('external_id','mt_blocked_'||replace(a::text,'-',''),'source_status','blocked'));
  perform set_config('role','authenticated',true);data:=public.review_darts_import(item,'apply',m,r,'legs',null,true);
  if data->>'state'<>'conflict' then raise exception 'FAIL walkover';end if;
  data:=public.review_darts_import(item,'reject');if data->>'state'<>'rejected' then raise exception 'FAIL reject';end if;
  perform set_config('role','postgres',true);
  if (select jsonb_array_length(history) from predict_private.darts_import_items where id=item)<>2 then raise exception 'FAIL review audit history';end if;
  -- A stale pending version cannot be applied after new source evidence arrived.
  item:=pg_temp.stage_darts(a,t,'fixtures',f||jsonb_build_object('external_id','fx_stale_'||a,'home_name','QA C','away_name','QA D'));
  mid:=pg_temp.stage_darts(a,t,'fixtures',f||jsonb_build_object('external_id','fx_stale_'||a,'home_name','QA C','away_name','QA D','round','New round'));
  perform set_config('role','authenticated',true);data:=public.review_darts_import(item,'apply',null,r,'legs',6,true);
  if data->>'state'<>'conflict' then raise exception 'FAIL stale proposal';end if;
  perform set_config('role','postgres',true);
  -- A selected future match still cannot receive an early result.
  insert into public.matches(tournament_id,round_id,home_name,away_name,scheduled_start,score_unit,first_to,start_time_confirmed)
    values(t,r,'QA Future A','QA Future B',now()+interval '1 day','legs',6,true) returning id into future;
  item:=pg_temp.stage_darts(a,t,'results',result||jsonb_build_object('external_id','mt_future_'||a,'home_name','QA Future A','away_name','QA Future B','played_on',to_char(now()+interval '1 day','YYYY-MM-DD')));
  perform set_config('role','authenticated',true);
  begin perform public.review_darts_import(item,'apply',future,r,'legs',null,true);raise exception 'FAIL premature result';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
  perform set_config('role','postgres',true);
  if exists(select 1 from public.matches where id=future and home_score is not null) then raise exception 'FAIL early score changed';end if;
  -- Verifying a manually entered matching result leaves the match row untouched.
  update public.matches set scheduled_start=now()-interval '1 hour',status='finished',home_score=6,away_score=3 where id=future;
  select row_to_json(x)::text into snap from public.matches x where id=future;
  item:=pg_temp.stage_darts(a,t,'results',result||jsonb_build_object('external_id','mt_verify_'||a,'home_name','QA Future A','away_name','QA Future B'));
  perform set_config('role','authenticated',true);data:=public.review_darts_import(item,'apply',future,r,'legs',null,true);
  if data->>'state'<>'applied' then raise exception 'FAIL existing manual verification';end if;
  perform set_config('role','postgres',true);
  if (select row_to_json(x)::text from public.matches x where id=future)<>snap then raise exception 'FAIL verification changed match';end if;
  -- Ambiguous same-day rematches are blocked, even when the admin selected one.
  insert into public.matches(tournament_id,round_id,home_name,away_name,scheduled_start,score_unit,first_to,start_time_confirmed)
    values(t,r,'QA Future A','QA Future B',now()-interval '2 hours','legs',6,true);
  item:=pg_temp.stage_darts(a,t,'results',result||jsonb_build_object('external_id','mt_ambiguous_'||a,'home_name','QA Future A','away_name','QA Future B'));
  perform set_config('role','authenticated',true);data:=public.review_darts_import(item,'apply',future,r,'legs',null,true);
  if data->>'state'<>'conflict' then raise exception 'FAIL ambiguous result';end if;
  perform set_config('role','anon',true);perform set_config('request.jwt.claim.sub','',true);
  begin perform public.review_darts_import(item,'reject');raise exception 'FAIL anonymous review';exception when insufficient_privilege then null;end;
  perform set_config('role','postgres',true);
end $$;
select 'PASS: reviewed imports, authorization, rate limit, deduplication, closed fixture, reversed results, conflicts, abnormal result rejection, scoring and prediction preservation; rollback' as result;
rollback;
