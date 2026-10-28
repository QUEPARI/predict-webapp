alter function predict_private.champion_winner(uuid) rename to champion_winner_before_source_drafts;
revoke all on function predict_private.champion_winner_before_source_drafts(uuid) from public,anon,authenticated,service_role;
create function predict_private.champion_winner(p_id uuid) returns text language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from predict_private.mastercaller_sources where tournament_id=p_id and source_layout='generic') then
  (select case when m.home_score>m.away_score then m.home_name else m.away_name end from public.matches m join public.tournament_rounds r on r.id=m.round_id where m.tournament_id=p_id and r.round_order=(select max(round_order) from public.tournament_rounds where tournament_id=p_id) and m.status='finished' limit 1)
 else predict_private.champion_winner_before_source_drafts(p_id) end
$$;
revoke all on function predict_private.champion_winner(uuid) from public,anon,authenticated,service_role;
