CREATE OR REPLACE FUNCTION predict_private.sync_mastercaller_schema_internal(p_tournament uuid, p_snapshot jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg predict_private.mastercaller_sources%rowtype;k predict_private.knockout_tournaments%rowtype;f jsonb;m public.matches%rowtype;n predict_private.knockout_nodes%rowtype;rule jsonb;start_at timestamptz;nr integer;roster text[];
begin
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_tournament;
 if not cfg.automatic_setup then return;end if;
 if p_snapshot is null or predict_private.mastercaller_url(p_snapshot->>'url') is distinct from cfg.url or jsonb_typeof(p_snapshot->'bracket') is distinct from 'array' then raise exception 'Ongeldig bronschema';end if;
 perform 1 from public.tournaments where id=p_tournament for update;
 select * into k from predict_private.knockout_tournaments where tournament_id=p_tournament;
 select array_agg(value order by ord) into roster from jsonb_array_elements_text(p_snapshot->'roster') with ordinality x(value,ord);
 if cardinality(roster) is distinct from cardinality(k.roster) or exists(select 1 from unnest(roster,k.roster) x(a,b) where predict_private.score_name(a) is distinct from predict_private.score_name(b)) then raise exception 'De loting is gewijzigd; automatische verwerking gepauzeerd';end if;
 select count(*) into nr from public.tournament_rounds where tournament_id=p_tournament;
 if jsonb_array_length(p_snapshot->'rounds')<>nr or jsonb_array_length(p_snapshot->'bracket')<>cardinality(roster)-1 then raise exception 'Onvolledig bronschema';end if;
 for f in select value from jsonb_array_elements(p_snapshot->'bracket') loop
  select * into n from predict_private.knockout_nodes where tournament_id=p_tournament and round_no=(f->>'order')::integer and position=(f->>'position')::integer;
  if not found then raise exception 'Schemapositie ontbreekt';end if;
  select * into m from public.matches where id=n.match_id for update;
  if m.status<>'scheduled' or m.actual_start is not null or m.home_score is not null then continue;end if;
  select value into rule from jsonb_array_elements(p_snapshot->'rounds') where (value->>'order')::integer=n.round_no;
  if rule->>'unit' is distinct from m.score_unit or (rule->>'first_to')::integer is distinct from m.first_to then raise exception 'Het wedstrijdformat in de bron is gewijzigd';end if;
  if (nullif(f->>'home_name','') is not null and n.home_slot is not null and predict_private.score_name(f->>'home_name')<>predict_private.score_name(m.home_name))
   or (nullif(f->>'away_name','') is not null and n.away_slot is not null and predict_private.score_name(f->>'away_name')<>predict_private.score_name(m.away_name)) then raise exception 'Deelnemers wijken af van het bronschema';end if;
  -- Keep known times when missing or earlier; NNB accepts the first known time.
  start_at:=greatest(nullif(f->>'start','')::timestamptz,m.scheduled_start);
  -- A known elapsed deadline stays closed even when the source removes its time.
  update public.matches set predictions_enabled=false where id=m.id;
  -- A source delay must not reopen an already expired prediction window.
  update public.matches set scheduled_start=start_at,start_time_confirmed=start_at is not null,source_time_pending=start_at is null,needs_review=false,
   prediction_window_closed=m.prediction_window_closed or coalesce(m.scheduled_start<=clock_timestamp(),false),
   predictions_enabled=not m.prediction_window_closed and (m.scheduled_start is null or m.scheduled_start>clock_timestamp())
    and predict_private.prediction_time_open(p_tournament,start_at,start_at is not null)
    and n.home_slot is not null and n.away_slot is not null
    and exists(select 1 from public.tournaments where id=p_tournament and status in('published','active')),
   updated_at=now() where id=m.id;
 end loop;
 update predict_private.mastercaller_sources set snapshot=p_snapshot-'records' where tournament_id=p_tournament;
end $function$;
