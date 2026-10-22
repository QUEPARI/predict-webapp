-- Observe disagreements before checking the downstream source bracket. A manual
-- winner may legitimately differ from the source's next-round participants.
create function predict_private.observe_manual_source_results(p_tournament uuid,p_records jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare item jsonb; m public.matches%rowtype; hs integer; aws integer; nr integer; depth integer; cnt integer;
begin
 if jsonb_typeof(p_records) is distinct from 'array' or jsonb_array_length(p_records)>256 then return;end if;
 select max(round_order) into nr from public.tournament_rounds where tournament_id=p_tournament;
 for item in select value from jsonb_array_elements(p_records) loop
  if coalesce(item->>'home_score','')!~'^[0-9]{1,2}$' or coalesce(item->>'away_score','')!~'^[0-9]{1,2}$'
   or coalesce(item->>'depth','')!~'^[0-7]$' or coalesce(item->>'date','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then continue;end if;
  depth:=(item->>'depth')::integer;
  if (select count(*) from jsonb_array_elements(p_records) x where x->>'depth'=item->>'depth' and
   (predict_private.score_name(x->>'home_name')=predict_private.score_name(item->>'home_name') and predict_private.score_name(x->>'away_name')=predict_private.score_name(item->>'away_name') or
    predict_private.score_name(x->>'away_name')=predict_private.score_name(item->>'home_name') and predict_private.score_name(x->>'home_name')=predict_private.score_name(item->>'away_name')))<>1 then continue;end if;
  select count(*) into cnt from public.matches mat join public.tournament_rounds rd on rd.id=mat.round_id
   join predict_private.mastercaller_manual_results manual on manual.match_id=mat.id
   where mat.tournament_id=p_tournament and rd.round_order=nr-depth and
   (predict_private.score_name(mat.home_name)=predict_private.score_name(item->>'home_name') and predict_private.score_name(mat.away_name)=predict_private.score_name(item->>'away_name') or
    predict_private.score_name(mat.away_name)=predict_private.score_name(item->>'home_name') and predict_private.score_name(mat.home_name)=predict_private.score_name(item->>'away_name'));
  if cnt<>1 then continue;end if;
  select mat.* into m from public.matches mat join public.tournament_rounds rd on rd.id=mat.round_id
   join predict_private.mastercaller_manual_results manual on manual.match_id=mat.id
   where mat.tournament_id=p_tournament and rd.round_order=nr-depth and
   (predict_private.score_name(mat.home_name)=predict_private.score_name(item->>'home_name') and predict_private.score_name(mat.away_name)=predict_private.score_name(item->>'away_name') or
    predict_private.score_name(mat.away_name)=predict_private.score_name(item->>'home_name') and predict_private.score_name(mat.home_name)=predict_private.score_name(item->>'away_name'));
  hs:=(item->>'home_score')::integer;aws:=(item->>'away_score')::integer;
  if predict_private.score_name(m.home_name)<>predict_private.score_name(item->>'home_name') then hs:=(item->>'away_score')::integer;aws:=(item->>'home_score')::integer;end if;
  if m.first_to is null or not ((hs=m.first_to and aws<m.first_to) or(aws=m.first_to and hs<m.first_to)) then continue;end if;
  update predict_private.mastercaller_manual_results set source_home_score=hs,source_away_score=aws,source_checked_at=now(),
   conflict=(m.home_score is distinct from hs or m.away_score is distinct from aws) where match_id=m.id;
 end loop;
end $$;
revoke all on function predict_private.observe_manual_source_results(uuid,jsonb) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION predict_private.finish_mastercaller_internal(p_tournament uuid, p_lease uuid, p_records jsonb, p_error text, p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg predict_private.mastercaller_sources%rowtype;issue text;result jsonb;
begin
 perform 1 from public.tournaments where id=p_tournament for update;
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_tournament for update;
 if not found or cfg.lease is distinct from p_lease or cfg.last_attempt<now()-interval '3 minutes' then raise exception 'Verouderde ophaalactie';end if;
 if p_error is null then perform predict_private.observe_manual_source_results(p_tournament,p_records);end if;
 if cfg.automatic_setup and p_error is null then
  begin perform predict_private.sync_mastercaller_schema(p_tournament,p_snapshot);
  exception when others then issue:=left(sqlerrm,300);end;
 end if;
 result:=predict_private.finish_mastercaller_scores(p_tournament,p_lease,p_records,coalesce(p_error,issue));
 if cfg.automatic_setup and p_error is null and issue is null then
  perform predict_private.sync_mastercaller_schema(p_tournament,p_snapshot);
 end if;
 return result;
end $function$;
