create function predict_private.tournament_prediction_counts() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Login vereist' using errcode='42501';end if;
 with eligible as(
 select m.id,m.tournament_id,m.scheduled_start,mp.id as prediction_id
 from public.matches m join public.tournaments t on t.id=m.tournament_id
 left join public.match_predictions mp on mp.match_id=m.id and mp.user_id=auth.uid()
 where t.status in ('published','active') and m.predictions_enabled and m.status='scheduled' and m.actual_start is null and m.home_score is null and m.away_score is null and m.start_time_confirmed and not m.needs_review and m.round_id is not null and m.scheduled_start>clock_timestamp()
 and (m.score_unit='goals' and m.first_to is null or m.score_unit in ('legs','sets') and m.first_to between 1 and 99)
 and not exists(select 1 from predict_private.knockout_nodes n join predict_private.knockout_tournaments k on k.tournament_id=n.tournament_id where n.match_id=m.id and (n.is_bye or n.home_slot is null or n.away_slot is null or nullif(k.roster[n.home_slot],'') is null or nullif(k.roster[n.away_slot],'') is null))
 ),counts as(select tournament_id,count(*) as open_count,count(*) filter(where prediction_id is null) as remaining_count from eligible group by tournament_id)
 select jsonb_build_object('server_now',clock_timestamp(),'next_deadline',(select min(scheduled_start) from eligible),'tournaments',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'open_count',coalesce(c.open_count,0),'remaining_count',coalesce(c.remaining_count,0))),'[]') from public.tournaments t left join counts c on c.tournament_id=t.id where t.status in ('published','active','completed','archived'))) into result;
 return result;
end $$;
create function public.get_tournament_prediction_counts() returns jsonb language sql security invoker set search_path='' as $$select predict_private.tournament_prediction_counts()$$;
revoke all on function predict_private.tournament_prediction_counts(),public.get_tournament_prediction_counts() from public,anon,authenticated;
grant execute on function predict_private.tournament_prediction_counts(),public.get_tournament_prediction_counts() to authenticated;
