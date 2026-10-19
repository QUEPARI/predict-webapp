begin;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();u uuid:=gen_random_uuid();result jsonb;j uuid;job jsonb;tid uuid;day text:=((now()+interval '2 days') at time zone 'Europe/Amsterdam')::date::text;snap jsonb;
begin
 insert into public.user_roles values(a,'admin'),(b,'admin');
 snap:=jsonb_build_object('url','https://mastercaller.com/tournaments/european-championship/2026/results','title','QA GitHub','start_date',day,'end_date',day,'roster','["QA A","QA B"]'::jsonb,'rounds','[{"order":1,"name":"Final","unit":"legs","first_to":6}]'::jsonb,'bracket',jsonb_build_array(jsonb_build_object('order',1,'position',1,'home_name','QA A','away_name','QA B','start',null,'date',day)),'records','[]'::jsonb);
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('role','authenticated',true);
 begin perform public.request_mastercaller_game(snap->>'url');raise exception 'FAIL ordinary user queued';exception when insufficient_privilege then null;end;
 begin perform public.claim_mastercaller_creations();raise exception 'FAIL user claimed';exception when insufficient_privilege then null;end;
 begin perform public.cache_mastercaller_snapshot(snap);raise exception 'FAIL user cached';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',a::text,true);
 result:=public.request_mastercaller_game(snap->>'url','QA queue',10,15,'replacement');j:=(result->>'job_id')::uuid;
 if j is null or result->>'status'<>'queued' then raise exception 'FAIL missing queue %',result;end if;
 result:=public.request_mastercaller_game(snap->>'url','QA queue',10,15,'replacement');if (result->>'job_id')::uuid<>j then raise exception 'FAIL duplicate queue';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 begin perform public.get_mastercaller_creation_status(j);raise exception 'FAIL another admin reads job';exception when insufficient_privilege then null;end;
 perform set_config('role','none',true);
 job:=public.claim_mastercaller_creations()->0;if (job->>'job_id')::uuid<>j then raise exception 'FAIL job claim';end if;
 if jsonb_array_length(public.claim_mastercaller_creations())<>0 then raise exception 'FAIL duplicate lease';end if;
 begin perform public.finish_mastercaller_creation(j,gen_random_uuid(),snap);raise exception 'FAIL wrong lease';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 result:=public.finish_mastercaller_creation(j,(job->>'lease')::uuid,snap);tid:=(result->>'id')::uuid;
 if tid is null or result->>'status'<>'done' then raise exception 'FAIL creation %',result;end if;
 if current_setting('request.jwt.claim.sub')<>b::text then raise exception 'FAIL actor not restored';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 result:=public.get_mastercaller_creation_status(j);if (result->>'id')::uuid<>tid or result->>'status'<>'done' then raise exception 'FAIL status %',result;end if;
 result:=public.request_mastercaller_game(snap->>'url','QA fresh cache',1,3,'replacement');if result->>'status'<>'done' or result->>'id' is null then raise exception 'FAIL cache create %',result;end if;
 perform public.request_mastercaller_refresh(tid);
 perform set_config('role','none',true);
 update predict_private.mastercaller_sources set last_attempt=now()-interval '2 minutes' where tournament_id=tid;
 job:=public.claim_mastercaller_jobs()->0;if (job->>'tournament_id')::uuid<>tid then raise exception 'FAIL manual refresh not priority %',job;end if;
 if (select fetch_requested from predict_private.mastercaller_sources where tournament_id=tid) then raise exception 'FAIL refresh not consumed';end if;
 -- Cached schema is ignored after four hours; revoked administrator cannot complete pending work.
 update predict_private.mastercaller_cache set fetched_at=now()-interval '5 hours';
 result:=public.request_mastercaller_game(snap->>'url','QA revoked',1,3,'replacement');j:=(result->>'job_id')::uuid;job:=public.claim_mastercaller_creations()->0;
 delete from public.user_roles where user_id=a;
 result:=public.finish_mastercaller_creation(j,(job->>'lease')::uuid,snap);if result->>'status'<>'failed' then raise exception 'FAIL revoked admin created';end if;
end $$;
rollback;
