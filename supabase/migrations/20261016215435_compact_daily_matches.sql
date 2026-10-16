CREATE OR REPLACE FUNCTION predict_private.ko_edit(p_tournament uuid, p_action text, p_match uuid, p_values jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=predict_private.ko_admin(); m public.matches%rowtype; n predict_private.knockout_nodes%rowtype; oldrow jsonb; start_at timestamptz; unit text; ft integer; sport text; winner integer; hs integer; aws integer; reason text;
begin
  perform 1 from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=p_tournament for update of t;
  if not found then raise exception 'Handmatig knock-outtoernooi niet gevonden';end if;
  if p_action='roster' then
    if exists(select 1 from public.matches where tournament_id=p_tournament and (home_score is not null or actual_start is not null or status='live')) or exists(select 1 from public.match_predictions mp join public.matches mat on mat.id=mp.match_id where mat.tournament_id=p_tournament) then raise exception 'Namen kunnen alleen zonder voorspellingen of gestarte wedstrijden worden gewijzigd';end if;
    if jsonb_typeof(p_values->'names') is distinct from 'array' or jsonb_array_length(p_values->'names')<>(select cardinality(roster) from predict_private.knockout_tournaments where tournament_id=p_tournament) or
      exists(select 1 from jsonb_array_elements(p_values->'names')x where jsonb_typeof(x)<>'string' or length(btrim(x#>>'{}'))>80 or (x#>>'{}')~'[[:cntrl:]]') or
      (select count(distinct lower(btrim(x))) from jsonb_array_elements_text(p_values->'names')x where btrim(x)<>'')<>(select count(*) from jsonb_array_elements_text(p_values->'names')x where btrim(x)<>'') then raise exception 'Behoud alle schemaplekken; ingevulde namen moeten uniek zijn';end if;
    update predict_private.knockout_tournaments set roster=array(select btrim(x) from jsonb_array_elements_text(p_values->'names')x) where tournament_id=p_tournament;
    update public.matches mat set predictions_enabled=false where mat.tournament_id=p_tournament;
    update public.matches mat set home_name=coalesce(nullif(k.roster[nod.home_slot],''),case when nod.home_slot is not null then 'Deelnemer '||nod.home_slot end,mat.home_name),away_name=coalesce(nullif(k.roster[nod.away_slot],''),case when nod.away_slot is not null then 'Deelnemer '||nod.away_slot end,mat.away_name) from predict_private.knockout_nodes nod join predict_private.knockout_tournaments k on k.tournament_id=nod.tournament_id where mat.id=nod.match_id and nod.tournament_id=p_tournament;
    insert into public.scoring_audit_log(tournament_id,changed_by,action,old_values,new_values) values(p_tournament,actor,'knockout_roster_edit','{}',p_values);
    return true;
  end if;
  if p_action='publish' then
    if exists(select 1 from predict_private.knockout_tournaments k,unnest(k.roster)x where k.tournament_id=p_tournament and btrim(x)='') then raise exception 'Vul eerst alle deelnemers in het schema in';end if;
    perform public.admin_publish_tournament(p_tournament);
    update public.matches eligible set predictions_enabled=true where eligible.tournament_id=p_tournament and eligible.status='scheduled' and eligible.scheduled_start>clock_timestamp() and eligible.start_time_confirmed and not eligible.needs_review and exists(select 1 from predict_private.knockout_nodes nod where nod.match_id=eligible.id and nod.home_slot is not null and nod.away_slot is not null and not nod.is_bye);
    return true;
  end if;
  select * into m from public.matches where id=p_match and tournament_id=p_tournament for update;
  select * into n from predict_private.knockout_nodes where match_id=m.id;
  if m.id is null or n.is_bye then raise exception 'Wedstrijd ontbreekt of is een vrijstelling';end if;
  oldrow:=to_jsonb(m);reason:=btrim(coalesce(p_values->>'reason',''));
  if p_action='schedule' then
    if m.status not in ('scheduled','postponed') or m.actual_start is not null or m.home_score is not null then raise exception 'Gestarte of afgeronde wedstrijd kan niet opnieuw worden gepland';end if;
    start_at:=nullif(p_values->>'start','')::timestamptz;unit:=p_values->>'unit';ft:=nullif(p_values->>'first_to','')::integer;
    select s.slug into sport from public.tournaments t join public.competitions c on c.id=t.competition_id join public.sports s on s.id=c.sport_id where t.id=p_tournament;
    if (sport='darts' and (unit is null or unit not in ('legs','sets') or ft is null or ft not between 1 and 99)) or (sport='football' and (unit is distinct from 'goals' or ft is not null)) then raise exception 'Ongeldig wedstrijdformaat';end if;
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
