-- Respect tournament-specific excluded source rounds without changing source keys.
do $$declare definition text;begin
 select pg_get_functiondef('predict_private.sync_generic_source(uuid,jsonb)'::regprocedure) into definition;
 if position('for f in select * from jsonb_array_elements(p_snapshot->''matches'') loop' in definition)=0 then raise exception 'Unexpected source synchronizer';end if;
 execute replace(definition,'for f in select * from jsonb_array_elements(p_snapshot->''matches'') loop',
 'for f in select * from jsonb_array_elements(p_snapshot->''matches'') loop
  if coalesce(cfg.setup_snapshot->''excluded_rounds'',''[]''::jsonb) @> jsonb_build_array((f->>''round'')::integer) then continue;end if;');
end $$;

-- Excluded rounds must also be omitted from result processing and conflict reports.
create or replace function predict_private.finish_mastercaller(p_tournament uuid,p_lease uuid,p_records jsonb,p_error text,p_snapshot jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;excluded jsonb;round_count integer;
begin
 perform 1 from public.tournaments where id=p_tournament for update;
 select setup_snapshot->'excluded_rounds',jsonb_array_length(setup_snapshot->'rounds') into excluded,round_count
 from predict_private.mastercaller_sources where tournament_id=p_tournament;
 if jsonb_typeof(excluded)='array' and jsonb_array_length(excluded)>0 then
  select coalesce(jsonb_agg(record order by ordinal),'[]'::jsonb) into p_records
  from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) with ordinality rows(record,ordinal)
  where not (excluded @> jsonb_build_array(round_count-(record->>'depth')::integer));
 end if;
 perform predict_private.mc_enter(p_tournament);
 result:=predict_private.finish_mastercaller_internal(p_tournament,p_lease,p_records,p_error,p_snapshot);
 perform predict_private.mc_exit(p_tournament);return result;
end $$;
