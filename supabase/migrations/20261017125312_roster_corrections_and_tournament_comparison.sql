-- Correct labels by stable roster slot; preserve existing predictions, scores and settings.
create or replace function predict_private.champion_roster_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if predict_private.management_permitted(old.tournament_id) then return new;end if;
 if new.roster is distinct from old.roster and exists(select 1 from predict_private.champion_settings where tournament_id=old.tournament_id) then raise exception 'Deelnemers staan vast zolang de winnaarsvraag is ingesteld';end if;return new;end $$;

create or replace function public.guard_started_match_predictions() returns trigger language plpgsql set search_path='' as $$begin
 -- A permitted label correction changes no deadline, status or prediction flag.
 if TG_OP='UPDATE' and predict_private.management_permitted(new.tournament_id)
   and (to_jsonb(new)-'home_name'-'away_name')=(to_jsonb(old)-'home_name'-'away_name') then return new;end if;
 if new.predictions_enabled and (new.status<>'scheduled' or new.actual_start is not null or new.scheduled_start is null or not new.start_time_confirmed or new.scheduled_start<=clock_timestamp())
 then raise exception 'Voorspellingen moeten gesloten zijn zodra de wedstrijd begonnen is of de deadline verstreken is.';end if;return new;
end $$;

CREATE OR REPLACE FUNCTION predict_private.ko_edit(p_tournament uuid, p_action text, p_match uuid, p_values jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=predict_private.ko_admin(); m public.matches%rowtype; n predict_private.knockout_nodes%rowtype; oldrow jsonb; start_at timestamptz; unit text; ft integer; sport text; winner integer; hs integer; aws integer; reason text; rule jsonb;old_names text[];new_names text[];
begin
  perform 1 from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=p_tournament for update of t;
  if not found then raise exception 'Handmatig knock-outtoernooi niet gevonden';end if;
  if p_action in('undo_postpone','reset_result') then
    select * into m from public.matches where id=p_match and tournament_id=p_tournament for update;
    if not found then raise exception 'Wedstrijd niet gevonden';end if;
    select * into n from predict_private.knockout_nodes where match_id=m.id;
    if n.match_id is null or n.is_bye then raise exception 'Geen herstelactie voor een vrijstelling';end if;
    oldrow:=to_jsonb(m);
    if p_action='undo_postpone' then
      if m.status<>'postponed' or m.home_score is not null or m.actual_start is not null then raise exception 'Alleen een niet-gestarte uitgestelde wedstrijd kan worden teruggezet';end if;
      update public.matches set status='scheduled',predictions_enabled=false,updated_at=now() where id=m.id;
    else
      if m.status<>'finished' or m.home_score is null or m.away_score is null then raise exception 'Alleen een ingevulde uitslag kan ongedaan worden gemaakt';end if;
      -- The normal advancement trigger retracts the winner and blocks the whole
      -- transaction if a following match already has predictions or has started.
      update public.matches set predictions_enabled=false,home_score=null,away_score=null,
        actual_start=null,status='scheduled',updated_at=now() where id=m.id;
      update predict_private.knockout_nodes set tie_winner=null where match_id=m.id;
    end if;
    insert into public.match_audit_log(match_id,changed_by,action,old_values,new_values)
      values(m.id,actor,'knockout_'||p_action,oldrow,jsonb_build_object('status','scheduled','predictions_enabled',false));
    return true;
  end if;
  if p_action='rounds' then
    if not exists(select 1 from public.tournaments where id=p_tournament and status in('draft','announced')) or
       exists(select 1 from public.match_predictions mp join public.matches mat on mat.id=mp.match_id where mat.tournament_id=p_tournament) or
       exists(select 1 from public.matches where tournament_id=p_tournament and (home_score is not null or actual_start is not null or status='live')) or
       exists(select 1 from predict_private.champion_predictions where tournament_id=p_tournament) then raise exception 'Ronde-instellingen kunnen alleen in een concept zonder voorspellingen of gestarte wedstrijden worden gewijzigd';end if;
    if jsonb_typeof(p_values->'rules') is distinct from 'array' or jsonb_array_length(p_values->'rules')<>(select count(*) from public.tournament_rounds where tournament_id=p_tournament) or
       (select count(distinct x->>'id') from jsonb_array_elements(p_values->'rules')x)<>jsonb_array_length(p_values->'rules') then raise exception 'Vul iedere ronde eenmaal in';end if;
    if p_values->>'mode' is null or p_values->>'mode' not in('replacement','additive') then raise exception 'Kies een geldige puntenmethode';end if;
    select s.slug into sport from public.tournaments t join public.competitions c on c.id=t.competition_id join public.sports s on s.id=c.sport_id where t.id=p_tournament;
    insert into predict_private.tournament_mutation_permits values(p_tournament,txid_current(),actor);
    for rule in select * from jsonb_array_elements(p_values->'rules') loop
      if not exists(select 1 from public.tournament_rounds where id=(rule->>'id')::uuid and tournament_id=p_tournament) then raise exception 'Ronde hoort niet bij dit toernooi';end if;
      unit:=rule->>'unit';ft:=nullif(rule->>'first_to','')::integer;
      if (sport='darts' and (unit is null or unit not in('legs','sets') or (ft is not null and ft not between 1 and 99))) or (sport='football' and (unit is distinct from 'goals' or ft is not null)) or
         (rule->>'winner_points')::integer not between 0 and 1000 or (rule->>'exact_points')::integer not between 0 and 1000 then raise exception 'Ongeldig rondeformaat of puntenschema';end if;
      update public.matches set predictions_enabled=false,score_unit=unit,first_to=ft,updated_at=now() where tournament_id=p_tournament and round_id=(rule->>'id')::uuid;
      update public.round_scoring set winner_points=(rule->>'winner_points')::integer,exact_score_points=(rule->>'exact_points')::integer where tournament_id=p_tournament and round_id=(rule->>'id')::uuid;
      if not found then insert into public.round_scoring(tournament_id,round_id,winner_points,exact_score_points) values(p_tournament,(rule->>'id')::uuid,(rule->>'winner_points')::integer,(rule->>'exact_points')::integer);end if;
    end loop;
    update public.tournament_scoring set scoring_mode=p_values->>'mode' where tournament_id=p_tournament;
    update public.tournaments set starts_at=nullif(p_values->>'start','')::timestamptz,ends_at=case when p_values?'end' then nullif(p_values->>'end','')::timestamptz else ends_at end where id=p_tournament;
    delete from predict_private.tournament_mutation_permits where tournament_id=p_tournament;
    insert into public.scoring_audit_log(tournament_id,changed_by,action,old_values,new_values) values(p_tournament,actor,'knockout_draft_rounds','{}',p_values);
    return true;
  end if;
  if p_action='roster' then
    if jsonb_typeof(p_values->'names') is distinct from 'array' or jsonb_array_length(p_values->'names')<>(select cardinality(roster) from predict_private.knockout_tournaments where tournament_id=p_tournament) or
      exists(select 1 from jsonb_array_elements(p_values->'names')x where jsonb_typeof(x)<>'string' or length(btrim(x#>>'{}'))>80 or (x#>>'{}')~'[[:cntrl:]]') or
      (select count(distinct lower(btrim(x))) from jsonb_array_elements_text(p_values->'names')x where btrim(x)<>'')<>(select count(*) from jsonb_array_elements_text(p_values->'names')x where btrim(x)<>'') then raise exception 'Behoud alle schemaplekken; ingevulde namen moeten uniek zijn';end if;
    select roster into old_names from predict_private.knockout_tournaments where tournament_id=p_tournament for update;
    new_names:=array(select btrim(x) from jsonb_array_elements_text(p_values->'names')x);
    if exists(select 1 from unnest(new_names) x where x='') and
      (exists(select 1 from public.tournaments where id=p_tournament and status not in('draft','announced')) or
       exists(select 1 from predict_private.champion_settings where tournament_id=p_tournament) or
       exists(select 1 from public.matches mat where mat.tournament_id=p_tournament and (mat.actual_start is not null or mat.home_score is not null or mat.status='live')) or
       exists(select 1 from public.match_predictions mp join public.matches mat on mat.id=mp.match_id where mat.tournament_id=p_tournament))
    then raise exception 'Een bestaande deelnemer mag niet worden leeggemaakt';end if;
    perform 1 from public.matches where tournament_id=p_tournament order by id for update;
    insert into predict_private.tournament_mutation_permits values(p_tournament,txid_current(),actor);
    update predict_private.knockout_tournaments set roster=new_names where tournament_id=p_tournament;
    update public.matches mat set home_name=coalesce(nullif(new_names[nod.home_slot],''),case when nod.home_slot is not null then 'Deelnemer '||nod.home_slot end,mat.home_name),
      away_name=coalesce(nullif(new_names[nod.away_slot],''),case when nod.away_slot is not null then 'Deelnemer '||nod.away_slot end,mat.away_name)
      from predict_private.knockout_nodes nod where mat.id=nod.match_id and nod.tournament_id=p_tournament;
    -- Champion choices use labels; map each label through its unchanged slot.
    update predict_private.champion_settings c set
      choices=array(select coalesce(new_names[array_position(old_names,x)],x) from unnest(c.choices)x),
      actual_winner=coalesce(new_names[array_position(old_names,c.actual_winner)],c.actual_winner) where tournament_id=p_tournament;
    update predict_private.champion_predictions c set choice=coalesce(new_names[array_position(old_names,c.choice)],c.choice) where tournament_id=p_tournament;
    delete from predict_private.tournament_mutation_permits where tournament_id=p_tournament;
    insert into public.scoring_audit_log(tournament_id,changed_by,action,old_values,new_values)
      values(p_tournament,actor,'knockout_name_correction',jsonb_build_object('names',old_names),jsonb_build_object('names',new_names));
    return true;
  end if;
  if p_action='publish' then
    if cardinality(predict_private.ko_publication_issues(p_tournament,(select starts_at from public.tournaments where id=p_tournament)))>0 then raise exception 'Publiceren kan nog niet: %',array_to_string(predict_private.ko_publication_issues(p_tournament,(select starts_at from public.tournaments where id=p_tournament)),'; ');end if;
    perform public.admin_publish_tournament(p_tournament);
    update public.matches eligible set predictions_enabled=true where eligible.tournament_id=p_tournament and eligible.status='scheduled' and eligible.scheduled_start>clock_timestamp() and eligible.start_time_confirmed and not eligible.needs_review and exists(select 1 from predict_private.knockout_nodes nod where nod.match_id=eligible.id and nod.home_slot is not null and nod.away_slot is not null and not nod.is_bye);
    return true;
  end if;
  select * into m from public.matches where id=p_match and tournament_id=p_tournament for update;
  select * into n from predict_private.knockout_nodes where match_id=m.id;
  if m.id is null or n.is_bye then raise exception 'Wedstrijd ontbreekt of is een vrijstelling';end if;
  oldrow:=to_jsonb(m);reason:='Automatisch schemabeheer: '||p_action;
  if p_action='schedule' then
    if m.status not in ('scheduled','postponed') or m.actual_start is not null or m.home_score is not null then raise exception 'Gestarte of afgeronde wedstrijd kan niet opnieuw worden gepland';end if;
    start_at:=nullif(p_values->>'start','')::timestamptz;unit:=p_values->>'unit';ft:=nullif(p_values->>'first_to','')::integer;
    select s.slug into sport from public.tournaments t join public.competitions c on c.id=t.competition_id join public.sports s on s.id=c.sport_id where t.id=p_tournament;
    if (sport='darts' and (unit is null or unit not in ('legs','sets') or (ft is null and not exists(select 1 from public.tournaments where id=p_tournament and status in('draft','announced'))) or (ft is not null and ft not between 1 and 99))) or (sport='football' and (unit is distinct from 'goals' or ft is not null)) then raise exception 'Ongeldig wedstrijdformaat';end if;
    if (unit is distinct from m.score_unit or ft is distinct from m.first_to) and exists(select 1 from public.match_predictions where match_id=m.id) then raise exception 'Spelvorm met bestaande voorspellingen kan niet worden gewijzigd';end if;
    if (m.scheduled_start<=clock_timestamp() or exists(select 1 from public.match_predictions where match_id=m.id)) and length(reason)<3 then raise exception 'Geef een reden voor de deadlinecorrectie';end if;
    update public.matches set predictions_enabled=false where id=m.id;
    update public.matches set scheduled_start=start_at,start_time_confirmed=start_at is not null,score_unit=unit,first_to=ft,needs_review=false,updated_at=now() where id=m.id;
    -- Preserve only a genuinely open, still-future fixture after a pure time correction.
    -- A past deadline, manual closure, format change or postponement requires explicit reopening.
    if m.predictions_enabled and m.status='scheduled' and m.start_time_confirmed and not m.needs_review
       and m.scheduled_start>clock_timestamp() and start_at>clock_timestamp()
       and unit is not distinct from m.score_unit and ft is not distinct from m.first_to
       and exists(select 1 from public.tournaments where id=p_tournament and status in ('published','active'))
    then
      update public.matches set predictions_enabled=true where id=m.id;
    end if;
  elsif p_action='open' then
    if n.home_slot is null or n.away_slot is null or m.status not in ('scheduled','postponed') or m.actual_start is not null or m.home_score is not null or m.needs_review or m.scheduled_start is null or m.scheduled_start<=clock_timestamp() then raise exception 'Vul twee deelnemers en een toekomstige starttijd in';end if;
    if not exists(select 1 from public.tournaments where id=p_tournament and status in ('published','active')) then raise exception 'Publiceer eerst het toernooi';end if;
    if length(reason)<3 then raise exception 'Geef een reden voor vrijgave of heropening';end if;
    update public.matches set predictions_enabled=true,status='scheduled',updated_at=now() where id=m.id;
  elsif p_action in ('close','postpone','cancel','start') then
    if m.status='finished' then raise exception 'Wedstrijd is al afgerond';end if;
    if length(reason)<3 then raise exception 'Geef een reden';end if;
    if p_action='start' and (n.home_slot is null or n.away_slot is null) then raise exception 'Deelnemers ontbreken';end if;
    update public.matches set predictions_enabled=false,status=case p_action when 'postpone' then 'postponed' when 'cancel' then 'cancelled' when 'start' then 'live' else status end,
      actual_start=case when p_action='start' then coalesce(actual_start,clock_timestamp()) else actual_start end,updated_at=now() where id=m.id;
  elsif p_action='result' then
    if n.home_slot is null or n.away_slot is null then raise exception 'Deelnemers ontbreken';end if;
    hs:=(p_values->>'home_score')::integer;aws:=(p_values->>'away_score')::integer;
    if hs is null or aws is null or hs not between 0 and 99 or aws not between 0 and 99 then raise exception 'Ongeldige uitslag';end if;
    winner:=case when hs>aws then n.home_slot when aws>hs then n.away_slot else (p_values->>'winner_slot')::integer end;
    if winner is null or winner not in(n.home_slot,n.away_slot) then raise exception 'Kies de winnaar bij een gelijkspel';end if;
    update predict_private.knockout_nodes set tie_winner=winner where match_id=m.id;
    if m.status='finished' then
      if length(reason)<3 then raise exception 'Geef een reden voor uitslagcorrectie';end if;
      if m.score_unit in ('sets','legs') and not ((hs=m.first_to and aws<m.first_to) or (aws=m.first_to and hs<m.first_to)) then raise exception 'Uitslag past niet bij het formaat';end if;
      update public.matches set home_score=hs,away_score=aws,predictions_enabled=false,updated_at=now() where id=m.id;
    else perform public.admin_record_match_result(m.id,hs,aws);end if;
  else raise exception 'Onbekende beheeractie';end if;
  insert into public.match_audit_log(match_id,changed_by,action,old_values,new_values) values(m.id,actor,'knockout_'||p_action,oldrow,jsonb_build_object('values',p_values,'reason',reason));
  return true;
end $function$
;

create function predict_private.tournament_prediction_comparison(p_tournament uuid,p_member uuid,p_round uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid:=p_tournament;result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.tournaments where id=tid and status in('published','active','completed','archived')) or
   (not exists(select 1 from public.tournament_entries where tournament_id=tid and user_id=auth.uid()) and not exists(select 1 from public.user_roles where user_id=auth.uid() and role in('admin','super_admin'))) or
   not exists(select 1 from public.tournament_entries where tournament_id=tid and user_id=p_member)
 then raise exception 'Alleen deelnemers van hetzelfde toernooi kunnen vergelijken' using errcode='42501';end if;
 if p_round is not null and not exists(select 1 from public.tournament_rounds where id=p_round and tournament_id=tid) then raise exception 'Ronde hoort niet bij dit toernooi';end if;
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
create function public.get_tournament_prediction_comparison(p_tournament uuid,p_member uuid,p_round uuid default null) returns jsonb language sql security invoker set search_path='' as $$select predict_private.tournament_prediction_comparison(p_tournament,p_member,p_round)$$;
revoke all on function predict_private.tournament_prediction_comparison(uuid,uuid,uuid),public.get_tournament_prediction_comparison(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function predict_private.tournament_prediction_comparison(uuid,uuid,uuid),public.get_tournament_prediction_comparison(uuid,uuid,uuid) to authenticated;
