-- Match predictions are visible only to current members of the selected pool,
-- after the actual deadline/start. Manual closure never discloses predictions.
create function predict_private.match_pool_comparison(p_match uuid,p_pool uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m public.matches%rowtype;members jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.pool_members where pool_id=p_pool and user_id=auth.uid()) then raise exception 'Alleen leden van deze poule kunnen vergelijken' using errcode='42501';end if;
 select mat.* into m from public.matches mat join public.pools p on p.tournament_id=mat.tournament_id join public.tournaments t on t.id=mat.tournament_id where mat.id=p_match and p.id=p_pool and t.status in('published','active','completed','archived');
 if not found or exists(select 1 from predict_private.knockout_nodes where match_id=p_match and is_bye) then raise exception 'Wedstrijd hoort niet bij deze poule' using errcode='42501';end if;
 if m.status not in('scheduled','live','finished') or not coalesce(m.scheduled_start<=clock_timestamp() or m.actual_start<=clock_timestamp(),false) then return jsonb_build_object('visible',false,'members','[]'::jsonb);end if;
 with scores as(
 select pm.user_id,coalesce(nullif(pr.display_name,''),pr.username,'Speler') as display_name,mp.home_score as predicted_home,mp.away_score as predicted_away,
 case when m.status='finished' and m.home_score is not null and m.away_score is not null then
 case when mp.id is null then 0 when ts.scoring_mode='additive' then
 (case when sign(mp.home_score-mp.away_score)=sign(m.home_score-m.away_score) then rs.winner_points else 0 end)+
 (case when mp.home_score=m.home_score and mp.away_score=m.away_score then rs.exact_score_points else 0 end)
 when mp.home_score=m.home_score and mp.away_score=m.away_score then rs.exact_score_points
 when sign(mp.home_score-mp.away_score)=sign(m.home_score-m.away_score) then rs.winner_points else 0 end end as points
 from public.pool_members pm left join public.profiles pr on pr.id=pm.user_id
 left join public.match_predictions mp on mp.user_id=pm.user_id and mp.match_id=m.id
 left join public.tournament_scoring ts on ts.tournament_id=m.tournament_id
 left join public.round_scoring rs on rs.tournament_id=m.tournament_id and rs.round_id=m.round_id
 where pm.pool_id=p_pool
 ) select coalesce(jsonb_agg(to_jsonb(s) order by s.points desc nulls last,s.display_name,s.user_id),'[]') into members from scores s;
 return jsonb_build_object('visible',true,'members',members);
end $$;
create function public.get_match_pool_comparison(p_match uuid,p_pool uuid) returns jsonb
language sql security invoker set search_path='' as $$select predict_private.match_pool_comparison(p_match,p_pool)$$;
revoke all on function predict_private.match_pool_comparison(uuid,uuid),public.get_match_pool_comparison(uuid,uuid) from public,anon,authenticated;
grant execute on function predict_private.match_pool_comparison(uuid,uuid),public.get_match_pool_comparison(uuid,uuid) to authenticated;
