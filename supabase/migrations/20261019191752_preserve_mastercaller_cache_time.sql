-- Keep the polling clock anchored to the actual source retrieval, not reuse of its cache.
create or replace function predict_private.request_mastercaller_game(p_url text,p_name text,p_winner integer,p_exact integer,p_mode text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=predict_private.ko_admin();u text:=predict_private.mastercaller_url(p_url);snap jsonb;cache_time timestamptz;tid uuid;j uuid;
begin
 if p_winner is null or p_exact is null or p_winner not between 0 and 1000 or p_exact not between 0 and 1000 or p_mode is null or p_mode not in('replacement','additive') or length(coalesce(p_name,''))>120 then raise exception 'Ongeldige toernooigegevens';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor_id::text,0));
 select id into j from predict_private.mastercaller_create_jobs where actor=actor_id and url=u and name is not distinct from p_name and winner_points=p_winner and exact_points=p_exact and mode=p_mode and status in('queued','running') order by created_at desc limit 1;
 if j is not null then return jsonb_build_object('status','queued','job_id',j,'message','Je aanvraag staat al in de GitHub-wachtrij.');end if;
 select snapshot,fetched_at into snap,cache_time from predict_private.mastercaller_cache where url=u and fetched_at>now()-interval '4 hours';
 if snap is not null then
  tid:=predict_private.create_mastercaller_game(snap,p_name,p_winner,p_exact,p_mode);
  update predict_private.mastercaller_sources set last_attempt=cache_time,last_success=cache_time,report=report||jsonb_build_object('checked_at',cache_time) where tournament_id=tid;
  return jsonb_build_object('status','done','id',tid,'name',coalesce(nullif(btrim(p_name),''),snap->>'title'),'participants',jsonb_array_length(snap->'roster'),'matches',jsonb_array_length(snap->'bracket'));
 end if;
 select id into j from predict_private.mastercaller_create_jobs where actor=actor_id and url=u and name is not distinct from p_name and winner_points=p_winner and exact_points=p_exact and mode=p_mode and status in('queued','running') order by created_at desc limit 1;
 if j is null then
  if (select count(*) from predict_private.mastercaller_create_jobs where actor=actor_id and status in('queued','running'))>=3 then raise exception 'Er staan al drie aanvragen klaar';end if;
  insert into predict_private.mastercaller_create_jobs(actor,url,name,winner_points,exact_points,mode) values(actor_id,u,p_name,p_winner,p_exact,p_mode) returning id into j;
 end if;
 return jsonb_build_object('status','queued','job_id',j,'message','In wachtrij bij GitHub. Je toernooi wordt automatisch aangemaakt zodra de bron is opgehaald. Dit kan enkele minuten duren.');
end $$;
