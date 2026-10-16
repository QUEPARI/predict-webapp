create or replace function predict_private.manage_tournament(p_id uuid,p_action text,p_values jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();t public.tournaments%rowtype;counts jsonb;reason text:=btrim(coalesce(p_values->>'reason',''));new_start timestamptz;deadline_at timestamptz;choices text[];rule jsonb;old_champ predict_private.champion_settings%rowtype;
begin
 select * into t from public.tournaments where id=p_id for update;
 if not found then raise exception 'Toernooi niet gevonden';end if;
 if length(reason)<3 then raise exception 'Geef een reden van minimaal 3 tekens';end if;
 -- Lock match rows as well, so concurrent match submissions finish before lifecycle changes.
 perform 1 from public.matches where tournament_id=p_id order by id for update;
 counts:=predict_private.tournament_counts(p_id);
 if p_action='delete' then
  if p_values->'expected' is distinct from counts or (case when (counts->>'predictions')::bigint=0 and (counts->>'winner_predictions')::bigint=0 and (counts->>'pools')::bigint=0 then coalesce(p_values->>'confirm_empty','false')<>'true' and p_values->>'confirm_name' is distinct from t.name else p_values->>'confirm_name' is distinct from t.name end) then raise exception 'Bevestiging of aantallen gewijzigd. Vernieuw en controleer opnieuw.';end if;
  insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details) values(p_id,actor,p_action,reason,jsonb_build_object('tournament',to_jsonb(t),'counts',counts));
  insert into predict_private.tournament_mutation_permits values(p_id,txid_current(),actor);
  delete from predict_private.darts_import_items where tournament_id=p_id or match_id in(select id from public.matches where tournament_id=p_id);
  delete from public.fixture_import_queue where tournament_id=p_id;
  delete from public.match_predictions where match_id in(select id from public.matches where tournament_id=p_id);
  delete from predict_private.knockout_nodes where tournament_id=p_id;
  delete from predict_private.knockout_tournaments where tournament_id=p_id;
  delete from public.matches where tournament_id=p_id;
  delete from public.round_scoring where tournament_id=p_id;
  delete from public.tournament_scoring where tournament_id=p_id;
  delete from public.tournament_rounds where tournament_id=p_id;
  delete from public.pools where tournament_id=p_id;
  delete from public.tournaments where id=p_id;
  delete from predict_private.tournament_mutation_permits where tournament_id=p_id;
  -- Competitions may be shared; deliberately retain them.
  return true;
 elsif p_action='metadata' then
  if length(btrim(coalesce(p_values->>'name',''))) not between 1 and 120 then raise exception 'Vul een toernooinaam in';end if;
  new_start:=nullif(p_values->>'start','')::timestamptz;
  if new_start is null then raise exception 'Vul de toernooistart in';end if;
  update public.tournaments set name=btrim(p_values->>'name'),starts_at=new_start where id=p_id;
 elsif p_action in ('pause','resume','draft') then
  if p_action='draft' and ((counts->>'predictions')::bigint>0 or (counts->>'results')::bigint>0 or (counts->>'winner_predictions')::bigint>0 or exists(select 1 from public.matches where tournament_id=p_id and (actual_start is not null or status='live'))) then raise exception 'Terug naar concept kan alleen zonder voorspellingen of gestarte wedstrijden. Gebruik pauzeren om bestaande gegevens te behouden.';end if;
  if p_action='pause' and t.status='draft' then raise exception 'Een concept hoeft niet gepauzeerd te worden';end if;
  if p_action='resume' and not exists(select 1 from public.tournament_scoring where tournament_id=p_id and is_locked) then raise exception 'Ga terug naar concept en publiceer via de gecontroleerde publicatieknop';end if;
  if p_action='resume' and t.status not in ('archived','completed') then raise exception 'Alleen een gepauzeerd of afgerond toernooi kan worden hervat';end if;
  update public.matches set predictions_enabled=false where tournament_id=p_id;
  update public.tournaments set status=case p_action when 'pause' then 'archived' when 'resume' then 'published' else 'draft' end where id=p_id;
  if p_action='draft' then
   insert into predict_private.tournament_mutation_permits values(p_id,txid_current(),actor);
   update public.tournament_scoring set is_locked=false where tournament_id=p_id;
   delete from predict_private.tournament_mutation_permits where tournament_id=p_id;
  end if;
 elsif p_action='points' then
  if (counts->>'predictions')::bigint>0 or (counts->>'results')::bigint>0 or (counts->>'winner_predictions')::bigint>0 or exists(select 1 from public.matches where tournament_id=p_id and (actual_start is not null or status='live')) then raise exception 'Punten blijven vast zodra voorspellingen of uitslagen bestaan';end if;
  if jsonb_typeof(p_values->'rules') is distinct from 'array' or jsonb_array_length(p_values->'rules')<>(select count(*) from public.tournament_rounds where tournament_id=p_id) then raise exception 'Vul iedere ronde eenmaal in';end if;
  if (select count(distinct x->>'id') from jsonb_array_elements(p_values->'rules')x)<>jsonb_array_length(p_values->'rules') then raise exception 'Dubbele ronde';end if;
  insert into predict_private.tournament_mutation_permits values(p_id,txid_current(),actor);
  for rule in select * from jsonb_array_elements(p_values->'rules') loop
   if (rule->>'winner_points')::integer is null or (rule->>'exact_points')::integer is null or (rule->>'winner_points')::integer not between 0 and 1000 or (rule->>'exact_points')::integer not between 0 and 1000 then raise exception 'Ongeldige punten';end if;
   update public.round_scoring set winner_points=(rule->>'winner_points')::integer,exact_score_points=(rule->>'exact_points')::integer where tournament_id=p_id and round_id=(rule->>'id')::uuid;
   if not found then raise exception 'Ronde hoort niet bij dit toernooi';end if;
  end loop;
  delete from predict_private.tournament_mutation_permits where tournament_id=p_id;
 elsif p_action='champion' then
  select * into old_champ from predict_private.champion_settings where tournament_id=p_id for update;
  if (counts->>'winner_predictions')::bigint>0 then raise exception 'Winnaarsvraag staat vast zodra iemand voorspeld heeft';end if;
  deadline_at:=nullif(p_values->>'deadline','')::timestamptz;
  if deadline_at is null or deadline_at<=clock_timestamp() or t.starts_at is null or deadline_at>t.starts_at or exists(select 1 from public.matches m left join predict_private.knockout_nodes n on n.match_id=m.id where m.tournament_id=p_id and not coalesce(n.is_bye,false) and (m.actual_start is not null or m.home_score is not null or m.scheduled_start<deadline_at)) then raise exception 'De winnaarsvraag moet sluiten vóór de toernooistart en de eerste wedstrijd';end if;
  choices:=array(select btrim(x) from jsonb_array_elements_text(p_values->'choices')x);
  if cardinality(choices) not between 2 and 128 or exists(select 1 from unnest(choices)x where length(x) not between 1 and 80 or x~'[[:cntrl:]]' or x='Vrijgesteld' or x like 'Winnaar wedstrijd %') or (select count(distinct lower(x)) from unnest(choices)x)<>cardinality(choices) then raise exception 'Vul 2–128 unieke deelnemers in';end if;
  if exists(select 1 from predict_private.knockout_tournaments k where k.tournament_id=p_id and k.roster is distinct from choices) then raise exception 'Sla eerst de volledige deelnemers in het schema op; gebruik diezelfde volgorde voor de winnaarsvraag';end if;
  if (p_values->>'points')::integer is null or (p_values->>'points')::integer not between 0 and 1000 then raise exception 'Vul de bonuspunten in';end if;
  insert into predict_private.champion_settings(tournament_id,deadline,points,choices) values(p_id,deadline_at,(p_values->>'points')::integer,choices) on conflict(tournament_id) do update set deadline=excluded.deadline,points=excluded.points,choices=excluded.choices,actual_winner=null;
 elsif p_action='champion_reset' then
  if (counts->>'winner_predictions')::bigint>0 then raise exception 'Winnaarsvraag met voorspellingen kan niet worden gewist';end if;
  delete from predict_private.champion_settings where tournament_id=p_id;
 elsif p_action='champion_result' then
  if exists(select 1 from predict_private.knockout_tournaments where tournament_id=p_id) then raise exception 'Bij knock-outtoernooien komt de winnaar automatisch uit de finale';end if;
  select * into old_champ from predict_private.champion_settings where tournament_id=p_id for update;
  if old_champ.tournament_id is null or nullif(p_values->>'winner','') is null or clock_timestamp()<old_champ.deadline or not (p_values->>'winner'=any(old_champ.choices)) then raise exception 'Kies na de deadline een geldige winnaar';end if;
  update predict_private.champion_settings set actual_winner=p_values->>'winner' where tournament_id=p_id;
 else raise exception 'Onbekende toernooiactie';end if;
 insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details) values(p_id,actor,p_action,reason,jsonb_build_object('before',to_jsonb(t),'values',p_values,'counts',counts));
 return true;
end $$;

-- Same-pool comparison. Never disclose predictions merely because a match was manually closed.
create function predict_private.pool_prediction_comparison(p_pool uuid,p_member uuid,p_round uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid;result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.pool_members where pool_id=p_pool and user_id=auth.uid()) or not exists(select 1 from public.pool_members where pool_id=p_pool and user_id=p_member) then raise exception 'Alleen leden van dezelfde poule kunnen vergelijken' using errcode='42501';end if;
 select tournament_id into tid from public.pools where id=p_pool;
 if p_round is not null and not exists(select 1 from public.tournament_rounds where id=p_round and tournament_id=tid) then raise exception 'Ronde hoort niet bij deze poule';end if;
 with scores as(
 select m.id,m.round_id,r.round_order,r.name as round_name,m.home_name,m.away_name,m.scheduled_start,m.home_score,m.away_score,m.status,
 mine.home_score as my_home,mine.away_score as my_away,theirs.home_score as their_home,theirs.away_score as their_away,
 case when m.status='finished' then case when mine.id is null then 0 when ts.scoring_mode='additive' then (case when sign(mine.home_score-mine.away_score)=sign(m.home_score-m.away_score) then rs.winner_points else 0 end)+(case when mine.home_score=m.home_score and mine.away_score=m.away_score then rs.exact_score_points else 0 end) when mine.home_score=m.home_score and mine.away_score=m.away_score then rs.exact_score_points when sign(mine.home_score-mine.away_score)=sign(m.home_score-m.away_score) then rs.winner_points else 0 end end as my_points,
 case when m.status='finished' then case when theirs.id is null then 0 when ts.scoring_mode='additive' then (case when sign(theirs.home_score-theirs.away_score)=sign(m.home_score-m.away_score) then rs.winner_points else 0 end)+(case when theirs.home_score=m.home_score and theirs.away_score=m.away_score then rs.exact_score_points else 0 end) when theirs.home_score=m.home_score and theirs.away_score=m.away_score then rs.exact_score_points when sign(theirs.home_score-theirs.away_score)=sign(m.home_score-m.away_score) then rs.winner_points else 0 end end as their_points
 from public.matches m join public.tournament_rounds r on r.id=m.round_id and r.tournament_id=tid
 left join public.match_predictions mine on mine.match_id=m.id and mine.user_id=auth.uid()
 left join public.match_predictions theirs on theirs.match_id=m.id and theirs.user_id=p_member
 left join public.round_scoring rs on rs.tournament_id=tid and rs.round_id=r.id left join public.tournament_scoring ts on ts.tournament_id=tid
 where m.tournament_id=tid and (p_round is null or m.round_id=p_round) and m.status in ('scheduled','live','finished')
 and (m.scheduled_start<=clock_timestamp() or m.actual_start<=clock_timestamp())
 and not exists(select 1 from predict_private.knockout_nodes n where n.match_id=m.id and n.is_bye)
 ) select coalesce(jsonb_agg(to_jsonb(s) order by s.round_order,s.scheduled_start,s.id),'[]') into result from scores s;
 return result;
end $$;
create function public.get_pool_prediction_comparison(p_pool uuid,p_member uuid,p_round uuid default null) returns jsonb language sql security invoker set search_path='' as $$select predict_private.pool_prediction_comparison(p_pool,p_member,p_round)$$;
revoke all on function predict_private.pool_prediction_comparison(uuid,uuid,uuid),public.get_pool_prediction_comparison(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function predict_private.pool_prediction_comparison(uuid,uuid,uuid),public.get_pool_prediction_comparison(uuid,uuid,uuid) to authenticated;
create or replace function public.can_view_match_prediction(p_match_id uuid,p_prediction_user_id uuid) returns boolean language sql volatile security definer set search_path='' as $$
 select exists(select 1 from public.matches m join public.pools p on p.tournament_id=m.tournament_id join public.pool_members viewer on viewer.pool_id=p.id join public.pool_members author on author.pool_id=p.id
 where m.id=p_match_id and viewer.user_id=auth.uid() and author.user_id=p_prediction_user_id and m.status in ('scheduled','live','finished') and (m.scheduled_start<=clock_timestamp() or m.actual_start<=clock_timestamp()))
$$;
create function predict_private.admin_match_results() returns jsonb language plpgsql security definer set search_path='' as $$begin perform predict_private.ko_admin();return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'home_score',home_score,'away_score',away_score)),'[]') from public.matches);end $$;
create function public.admin_match_results() returns jsonb language sql security invoker set search_path='' as $$select predict_private.admin_match_results()$$;
revoke all on function predict_private.admin_match_results(),public.admin_match_results() from public,anon,authenticated;
grant execute on function predict_private.admin_match_results(),public.admin_match_results() to authenticated;
revoke all on function public.can_view_match_prediction(uuid,uuid) from public,anon;
grant execute on function public.can_view_match_prediction(uuid,uuid) to authenticated;
