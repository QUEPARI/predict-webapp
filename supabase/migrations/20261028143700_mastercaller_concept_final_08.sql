create function predict_private.sync_generic_source(p_id uuid,p_snapshot jsonb) returns void language plpgsql security definer set search_path='' as $$
declare cfg predict_private.mastercaller_sources%rowtype;f jsonb;m public.matches%rowtype;start_at timestamptz;known boolean;members text[];r jsonb;
begin
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_id;
 if cfg.source_layout<>'generic' or cfg.setup_pending then return;end if;
 if predict_private.mastercaller_url(p_snapshot->>'url') is distinct from cfg.url or coalesce((p_snapshot->>'ready')::boolean,false) is not true or p_snapshot->>'format' is distinct from cfg.setup_snapshot->>'format' then raise exception 'Bronschema is gewijzigd of niet volledig beschikbaar';end if;
 select array_agg(value) into members from jsonb_array_elements_text(cfg.setup_snapshot->'roster');
 if (select array_agg(predict_private.score_name(value) order by predict_private.score_name(value)) from jsonb_array_elements_text(p_snapshot->'roster'))
 is distinct from (select array_agg(predict_private.score_name(x) order by predict_private.score_name(x)) from unnest(members)x) then raise exception 'De deelnemerslijst in de bron is gewijzigd; controleer de loting';end if;
 for f in select * from jsonb_array_elements(p_snapshot->'matches') loop
  select x.* into m from predict_private.mastercaller_match_map map join public.matches x on x.id=map.match_id where map.tournament_id=p_id and map.source_key=f->>'key' for update of x;
  if not found then raise exception 'Bronwedstrijd ontbreekt in het opgeslagen schema';end if;
  if m.status<>'scheduled' or m.actual_start is not null or m.home_score is not null then continue;end if;
  select value into r from jsonb_array_elements(p_snapshot->'rounds') where value->>'order'=f->>'round';
  if r->>'unit' is distinct from m.score_unit or (r->>'first_to')::int is not null and (r->>'first_to')::int is distinct from m.first_to then raise exception 'De spelvorm in de bron is gewijzigd';end if;
  known:=nullif(f->>'home_name','') is not null and nullif(f->>'away_name','') is not null;
  if known and (not exists(select 1 from unnest(members)x where predict_private.score_name(x)=predict_private.score_name(f->>'home_name')) or not exists(select 1 from unnest(members)x where predict_private.score_name(x)=predict_private.score_name(f->>'away_name'))) then raise exception 'Onbekende deelnemers in een bronwedstrijd';end if;
  if not m.needs_review and known and not ((predict_private.score_name(m.home_name)=predict_private.score_name(f->>'home_name') and predict_private.score_name(m.away_name)=predict_private.score_name(f->>'away_name')) or (predict_private.score_name(m.home_name)=predict_private.score_name(f->>'away_name') and predict_private.score_name(m.away_name)=predict_private.score_name(f->>'home_name'))) then raise exception 'De wedstrijdindeling is gewijzigd';end if;
  start_at:=greatest(m.scheduled_start,nullif(f->>'start','')::timestamptz);
  update public.matches set predictions_enabled=false where id=m.id;
  update public.matches set home_name=case when m.needs_review and known then f->>'home_name' else m.home_name end,away_name=case when m.needs_review and known then f->>'away_name' else m.away_name end,
   scheduled_start=start_at,start_time_confirmed=start_at is not null,source_time_pending=start_at is null,needs_review=case when known then false else m.needs_review end,
   prediction_window_closed=m.prediction_window_closed or coalesce(m.scheduled_start<=clock_timestamp(),false),
   predictions_enabled=not m.prediction_window_closed and (m.scheduled_start is null or m.scheduled_start>clock_timestamp()) and (known or not m.needs_review)
    and predict_private.prediction_time_open(p_id,start_at,start_at is not null) and exists(select 1 from public.tournaments where id=p_id and status in('published','active')),updated_at=now() where id=m.id;
 end loop;
end $$;
revoke all on function predict_private.sync_generic_source(uuid,jsonb) from public,anon,authenticated,service_role;
alter function predict_private.sync_mastercaller_schema(uuid,jsonb) rename to sync_mastercaller_schema_legacy;
revoke all on function predict_private.sync_mastercaller_schema_legacy(uuid,jsonb) from public,anon,authenticated,service_role;
create function predict_private.sync_mastercaller_schema(p_tournament uuid,p_snapshot jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from predict_private.mastercaller_sources where tournament_id=p_tournament and source_layout='generic') then
  perform predict_private.mc_enter(p_tournament);perform predict_private.sync_generic_source(p_tournament,p_snapshot);perform predict_private.mc_exit(p_tournament);
 else perform predict_private.sync_mastercaller_schema_legacy(p_tournament,p_snapshot);end if;
end $$;
revoke all on function predict_private.sync_mastercaller_schema(uuid,jsonb) from public,anon,authenticated,service_role;
