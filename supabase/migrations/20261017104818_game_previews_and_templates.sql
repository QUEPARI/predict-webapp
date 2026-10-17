-- Upcoming games may be announced without opening participation or predictions.
alter table public.tournaments drop constraint if exists tournaments_status_check;
alter table public.tournaments add constraint tournaments_status_check check(status in('draft','announced','published','active','completed','archived'));
drop policy if exists matches_read on public.matches;
create policy matches_read on public.matches for select to authenticated using(exists(select 1 from public.tournaments t where t.id=matches.tournament_id and t.status in('published','active','completed','archived')));
drop policy if exists rounds_read on public.tournament_rounds;
create policy rounds_read on public.tournament_rounds for select to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_rounds.tournament_id and t.status in('published','active','completed','archived')));
drop policy if exists round_scoring_read on public.round_scoring;
create policy round_scoring_read on public.round_scoring for select to authenticated using(exists(select 1 from public.tournaments t where t.id=round_scoring.tournament_id and t.status in('published','active','completed','archived')));
drop policy if exists tournament_scoring_read on public.tournament_scoring;
create policy tournament_scoring_read on public.tournament_scoring for select to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_scoring.tournament_id and t.status in('published','active','completed','archived')));
CREATE OR REPLACE FUNCTION predict_private.manage_tournament(p_id uuid, p_action text, p_values jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=predict_private.ko_admin();t public.tournaments%rowtype;counts jsonb;reason text:=btrim(coalesce(p_values->>'reason',''));new_start timestamptz;new_end timestamptz;deadline_at timestamptz;choices text[];rule jsonb;old_champ predict_private.champion_settings%rowtype;
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
 elsif p_action='announce' then
  if t.status not in('draft','announced') then raise exception 'Alleen een concept kan vooraf worden aangekondigd';end if;
  if t.starts_at is null or t.ends_at is null or t.ends_at<t.starts_at then raise exception 'Vul eerst een geldige van- en tot-datum in';end if;
  update public.matches set predictions_enabled=false where tournament_id=p_id;
  update public.tournaments set status='announced' where id=p_id;
 elsif p_action='metadata' then
  if length(btrim(coalesce(p_values->>'name',''))) not between 1 and 120 then raise exception 'Vul een toernooinaam in';end if;
  new_start:=nullif(p_values->>'start','')::timestamptz;
  new_end:=case when p_values?'end' then nullif(p_values->>'end','')::timestamptz else t.ends_at end;
  if new_start is null and t.status<>'draft' then raise exception 'Vul de toernooistart in';end if;
  if new_end is not null and (new_start is null or new_end<new_start) then raise exception 'De einddatum moet op of na de startdatum liggen';end if;
  update public.tournaments set name=btrim(p_values->>'name'),starts_at=new_start,ends_at=new_end where id=p_id;
 elsif p_action in ('pause','resume','draft') then
  if p_action='draft' and ((counts->>'predictions')::bigint>0 or (counts->>'results')::bigint>0 or (counts->>'winner_predictions')::bigint>0 or exists(select 1 from public.matches where tournament_id=p_id and (actual_start is not null or status='live'))) then raise exception 'Terug naar concept kan alleen zonder voorspellingen of gestarte wedstrijden. Gebruik pauzeren om bestaande gegevens te behouden.';end if;
  if p_action='pause' and t.status in('draft','announced') then raise exception 'Een concept hoeft niet gepauzeerd te worden';end if;
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
end $function$
;
create or replace function predict_private.ko_publication_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare issues text[];
begin
 if new.status='announced' then
  if old.status not in('draft','announced') or new.starts_at is null or new.ends_at is null or new.ends_at<new.starts_at then raise exception 'Vooraankondiging vereist een concept met geldige van- en tot-datum';end if;
  if exists(select 1 from public.matches where tournament_id=new.id and (predictions_enabled or actual_start is not null or home_score is not null)) or exists(select 1 from public.tournament_entries where tournament_id=new.id) then raise exception 'Een vooraankondiging kan geen deelnemers of gestarte wedstrijden hebben';end if;
 elsif new.status in('published','active') then
  issues:=predict_private.ko_publication_issues(new.id,new.starts_at);
  if cardinality(issues)>0 then raise exception 'Publiceren kan nog niet: %',array_to_string(issues,'; ');end if;
 end if;
 return new;
end $$;
drop trigger knockout_publication_guard on public.tournaments;
create trigger knockout_publication_guard before update of status,starts_at,ends_at on public.tournaments for each row execute function predict_private.ko_publication_guard();
create or replace function predict_private.ko_partial_scoring_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.winner_points is null or new.exact_score_points is null then
  perform 1 from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=new.tournament_id and t.status in('draft','announced') for update of t;
  if not found then raise exception 'Onvolledige puntentelling kan alleen bij een ongepubliceerd knock-outspel';end if;
 end if;return new;
end $$;
CREATE OR REPLACE FUNCTION predict_private.ko_edit(p_tournament uuid, p_action text, p_match uuid, p_values jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=predict_private.ko_admin(); m public.matches%rowtype; n predict_private.knockout_nodes%rowtype; oldrow jsonb; start_at timestamptz; unit text; ft integer; sport text; winner integer; hs integer; aws integer; reason text; rule jsonb;
begin
  perform 1 from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=p_tournament for update of t;
  if not found then raise exception 'Handmatig knock-outtoernooi niet gevonden';end if;
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
    if cardinality(predict_private.ko_publication_issues(p_tournament,(select starts_at from public.tournaments where id=p_tournament)))>0 then raise exception 'Publiceren kan nog niet: %',array_to_string(predict_private.ko_publication_issues(p_tournament,(select starts_at from public.tournaments where id=p_tournament)),'; ');end if;
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
CREATE OR REPLACE FUNCTION predict_private.ko_schema(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare admin boolean; result jsonb;
begin
  admin:=exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin'));
  if auth.uid() is null or not exists(select 1 from public.tournaments where id=p_id and (admin or status in ('published','active','completed','archived'))) then raise exception 'Toernooi niet beschikbaar' using errcode='42501';end if;
  if not exists(select 1 from predict_private.knockout_tournaments where tournament_id=p_id) then return null;end if;
  select jsonb_build_object('tournament_id',t.id,'name',t.name,'status',t.status,'participant_kind',k.participant_kind,'roster',k.roster,'start',t.starts_at,'end',t.ends_at,'scoring_mode',(select scoring_mode from public.tournament_scoring where tournament_id=t.id),'sport',(select s.slug from public.competitions c join public.sports s on s.id=c.sport_id where c.id=t.competition_id),'publication_issues',predict_private.ko_publication_issues(t.id,t.starts_at),'server_now',clock_timestamp(),
    'rounds',(select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'order',r.round_order,'unit',(select score_unit from public.matches where round_id=r.id order by id limit 1),'first_to',(select first_to from public.matches where round_id=r.id order by id limit 1),'winner_points',(select winner_points from public.round_scoring where round_id=r.id),'exact_points',(select exact_score_points from public.round_scoring where round_id=r.id)) order by r.round_order) from public.tournament_rounds r where r.tournament_id=t.id),
    'matches',(select jsonb_agg(jsonb_build_object('id',m.id,'number',n.number,'round',n.round_no,'position',n.position,'home',m.home_name,'away',m.away_name,'home_slot',n.home_slot,'away_slot',n.away_slot,'winner_slot',n.winner_slot,'bye',n.is_bye,
      'start',m.scheduled_start,'actual_start',m.actual_start,'status',m.status,'home_score',m.home_score,'away_score',m.away_score,'unit',m.score_unit,'first_to',m.first_to,'enabled',m.predictions_enabled,'needs_review',m.needs_review) order by n.number)
      from predict_private.knockout_nodes n join public.matches m on m.id=n.match_id where n.tournament_id=t.id)) into result from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=p_id;
  return result;
end $function$
;
CREATE OR REPLACE FUNCTION predict_private.management_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'status',t.status,'start',t.starts_at,'end',t.ends_at,'knockout',k.tournament_id is not null,'counts',predict_private.tournament_counts(t.id),'roster',coalesce(k.roster,array(select distinct x from public.matches m cross join lateral unnest(array[m.home_name,m.away_name])x where m.tournament_id=t.id and x<>'Vrijgesteld' and x not like 'Winnaar wedstrijd %' order by x)),'champion',(select to_jsonb(cs) from predict_private.champion_settings cs where cs.tournament_id=t.id),'rules',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'winner_points',rs.winner_points,'exact_points',rs.exact_score_points) order by r.round_order),'[]') from public.tournament_rounds r left join public.round_scoring rs on rs.round_id=r.id and rs.tournament_id=t.id where r.tournament_id=t.id)) order by t.name),'[]') from public.tournaments t left join predict_private.knockout_tournaments k on k.tournament_id=t.id);
end $function$
;
CREATE OR REPLACE FUNCTION public.admin_publish_tournament(p_tournament_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_admin_id UUID := auth.uid();
    v_tournament public.tournaments%ROWTYPE;
    v_scoring public.tournament_scoring%ROWTYPE;
    v_round_count INTEGER;
    v_configured_count INTEGER;
    v_published_at TIMESTAMPTZ;
BEGIN
    -- Alleen systeembeheerders.
    IF v_admin_id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.user_roles
        WHERE user_id = v_admin_id
          AND role IN ('admin', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'Geen beheerdersrechten'
            USING ERRCODE = '42501';
    END IF;

    -- Vergrendel toernooi.
    SELECT *
    INTO v_tournament
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Toernooi niet gevonden';
    END IF;

    IF v_tournament.status not in ('draft','announced') THEN
        RAISE EXCEPTION
            'Alleen een concepttoernooi kan worden gepubliceerd';
    END IF;

    IF v_tournament.starts_at IS NULL THEN
        RAISE EXCEPTION
            'Officiële toernooistart ontbreekt';
    END IF;

    -- Vergrendel puntenconfiguratie.
    SELECT *
    INTO v_scoring
    FROM public.tournament_scoring
    WHERE tournament_id = p_tournament_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Toernooi heeft geen puntconfiguratie';
    END IF;

    IF v_scoring.scoring_mode NOT IN (
        'replacement', 'additive'
    ) THEN
        RAISE EXCEPTION
            'Ongeldige puntenmethode';
    END IF;

    SELECT COUNT(*)
    INTO v_round_count
    FROM public.tournament_rounds
    WHERE tournament_id = p_tournament_id;

    SELECT COUNT(*)
    INTO v_configured_count
    FROM public.tournament_rounds r
    JOIN public.round_scoring rs
      ON rs.round_id = r.id
     AND rs.tournament_id = r.tournament_id
    WHERE r.tournament_id = p_tournament_id
      AND rs.winner_points >= 0
      AND rs.exact_score_points >= 0;

    IF v_round_count = 0
       OR v_configured_count <> v_round_count
    THEN
        RAISE EXCEPTION
            'Niet alle toernooirondes hebben een geldige puntentelling';
    END IF;

    v_published_at := clock_timestamp();

    -- Vergrendel de puntentelling.
    UPDATE public.tournament_scoring
    SET is_locked = true
    WHERE tournament_id = p_tournament_id;

    -- Publiceer, zonder wedstrijden te openen.
    UPDATE public.tournaments
    SET status = 'published'
    WHERE id = p_tournament_id;

    -- Publicatie vastleggen.
    INSERT INTO public.scoring_audit_log (
        tournament_id,
        action,
        changed_by,
        old_values,
        new_values
    )
    VALUES (
        p_tournament_id,
        'tournament_published',
        v_admin_id,
        jsonb_build_object(
            'status', v_tournament.status,
            'scoring_locked', v_scoring.is_locked
        ),
        jsonb_build_object(
            'status', 'published',
            'scoring_locked', true,
            'scoring_mode', v_scoring.scoring_mode,
            'configured_rounds', v_configured_count,
            'published_at', v_published_at
        )
    );

    RETURN true;
END;
$function$
;

create function predict_private.create_knockout_game(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text,p_end timestamptz,p_status text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();tid uuid;
begin
 if p_status is null or p_status not in('draft','announced') then raise exception 'Kies concept of vooraankondiging';end if;
 if p_end is not null and (p_start is null or p_end<p_start) then raise exception 'De einddatum moet op of na de startdatum liggen';end if;
 if (select count(distinct x->>'unit') from jsonb_array_elements(p_rules)x)<>1 then raise exception 'Kies een spelvorm voor het hele toernooi';end if;
 tid:=predict_private.ko_create(p_name,p_sport,p_kind,p_roster,p_start,p_rules,p_mode);
 update public.tournaments set ends_at=p_end where id=tid;
 if p_status='announced' then perform predict_private.manage_tournament(tid,'announce','{"reason":"Vooraankondiging bij aanmaken"}');end if;
 return tid;
end $$;
create function public.create_knockout_game(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text,p_end timestamptz,p_status text) returns uuid language sql security invoker set search_path='' as $$select predict_private.create_knockout_game(p_name,p_sport,p_kind,p_roster,p_start,p_rules,p_mode,p_end,p_status)$$;
revoke all on function predict_private.create_knockout_game(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text),public.create_knockout_game(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text) from public,anon,authenticated;
grant execute on function predict_private.create_knockout_game(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text),public.create_knockout_game(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text) to authenticated;

-- Templates are independent JSON snapshots. Updating one never touches games.
create function predict_private.manage_knockout_template(p_id uuid,p_name text,p_sport uuid,p_kind text,p_count integer,p_rules jsonb,p_mode text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();validated uuid;
begin
 if (select count(distinct x->>'unit') from jsonb_array_elements(p_rules)x)<>1 then raise exception 'Kies een spelvorm voor het hele sjabloon';end if;
 if p_id is not null then perform 1 from predict_private.knockout_templates where id=p_id for update;if not found then raise exception 'Sjabloon niet gevonden';end if;end if;
 validated:=predict_private.ko_save_template(p_name,p_sport,p_kind,p_count,p_rules,p_mode);
 if p_id is null then return validated;end if;
 update predict_private.knockout_templates t set name=v.name,sport_id=v.sport_id,participant_kind=v.participant_kind,participant_count=v.participant_count,rules=v.rules,scoring_mode=v.scoring_mode from predict_private.knockout_templates v where t.id=p_id and v.id=validated;
 delete from predict_private.knockout_templates where id=validated;
 return p_id;
end $$;
create function public.manage_knockout_template(p_id uuid,p_name text,p_sport uuid,p_kind text,p_count integer,p_rules jsonb,p_mode text) returns uuid language sql security invoker set search_path='' as $$select predict_private.manage_knockout_template(p_id,p_name,p_sport,p_kind,p_count,p_rules,p_mode)$$;
revoke all on function predict_private.manage_knockout_template(uuid,text,uuid,text,integer,jsonb,text),public.manage_knockout_template(uuid,text,uuid,text,integer,jsonb,text) from public,anon,authenticated;
grant execute on function predict_private.manage_knockout_template(uuid,text,uuid,text,integer,jsonb,text),public.manage_knockout_template(uuid,text,uuid,text,integer,jsonb,text) to authenticated;

CREATE OR REPLACE FUNCTION predict_private.champion_info(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c predict_private.champion_settings%rowtype;t public.tournaments%rowtype;deadline_at timestamptz;mine text;won text;begin
 if auth.uid() is null then raise exception 'Login vereist' using errcode='42501';end if;
 select * into t from public.tournaments where id=p_id;
 if t.id is null or (t.status in('draft','announced') and not exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin'))) then raise exception 'Toernooi niet beschikbaar' using errcode='42501';end if;
 select * into c from predict_private.champion_settings where tournament_id=p_id;
 if not found then return jsonb_build_object('enabled',false);end if;
 select least(c.deadline,t.starts_at,min(m.scheduled_start)) into deadline_at from public.matches m left join predict_private.knockout_nodes n on n.match_id=m.id where m.tournament_id=p_id and not coalesce(n.is_bye,false);
 select choice into mine from predict_private.champion_predictions where tournament_id=p_id and user_id=auth.uid();
 won:=predict_private.champion_winner(p_id);
 return jsonb_build_object('enabled',c.enabled,'deadline',deadline_at,'server_now',clock_timestamp(),'points',c.points,'choices',c.choices,'mine',mine,'winner',won,'earned_points',case when mine=won then c.points else 0 end,'open',c.enabled and t.status in ('published','active') and clock_timestamp()<deadline_at and not exists(select 1 from public.matches m left join predict_private.knockout_nodes n on n.match_id=m.id where m.tournament_id=p_id and not coalesce(n.is_bye,false) and (m.actual_start is not null or m.home_score is not null or m.status='live')));
end $function$

;
