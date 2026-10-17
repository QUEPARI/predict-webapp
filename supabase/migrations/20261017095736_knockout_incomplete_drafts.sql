-- Incomplete settings belong only to unpublished knockout drafts.

create function predict_private.ko_publication_issues(p_id uuid,p_start timestamptz) returns text[]
language plpgsql stable security definer set search_path='' as $$
declare issues text[]:=array[]::text[];r record;missing integer;
begin
 if not exists(select 1 from predict_private.knockout_tournaments where tournament_id=p_id) then return issues;end if;
 if p_start is null then issues:=array_append(issues,'Toernooistart ontbreekt');end if;
 select count(*) into missing from predict_private.knockout_tournaments k,unnest(k.roster)x where k.tournament_id=p_id and btrim(x)='';
 if missing>0 then issues:=array_append(issues,missing||' deelnemersnamen ontbreken in het schema');end if;
 if not exists(select 1 from public.tournament_scoring where tournament_id=p_id and scoring_mode in('replacement','additive')) then issues:=array_append(issues,'Puntenmethode ontbreekt');end if;
 for r in select tr.id,tr.name,rs.winner_points,rs.exact_score_points from public.tournament_rounds tr left join public.round_scoring rs on rs.round_id=tr.id and rs.tournament_id=tr.tournament_id where tr.tournament_id=p_id order by tr.round_order loop
  if r.winner_points is null then issues:=array_append(issues,r.name||': punten juiste winnaar ontbreken');end if;
  if r.exact_score_points is null then issues:=array_append(issues,r.name||': punten exacte score ontbreken');end if;
  if exists(select 1 from public.matches where tournament_id=p_id and round_id=r.id and (score_unit is null or (score_unit in('sets','legs') and (first_to is null or first_to not between 1 and 99)))) then issues:=array_append(issues,r.name||': spelvorm / first-to ontbreekt');end if;
 end loop;
 return issues;
end $$;
revoke all on function predict_private.ko_publication_issues(uuid,timestamptz) from public,anon,authenticated;

-- Nullable scores represent genuinely unfinished draft settings; never implicit zero points.
alter table public.round_scoring alter column winner_points drop not null;
alter table public.round_scoring alter column exact_score_points drop not null;
create function predict_private.ko_partial_scoring_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.winner_points is null or new.exact_score_points is null then
  perform 1 from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=new.tournament_id and t.status='draft' for update of t;
  if not found then raise exception 'Onvolledige puntentelling kan alleen bij een knock-outconcept';end if;
 end if;
 return new;
end $$;
revoke all on function predict_private.ko_partial_scoring_guard() from public,anon,authenticated;
create trigger knockout_partial_scoring_guard before insert or update on public.round_scoring for each row execute function predict_private.ko_partial_scoring_guard();

create or replace function predict_private.ko_publication_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare issues text[];
begin
 if new.status in('published','active') then
  issues:=predict_private.ko_publication_issues(new.id,new.starts_at);
  if cardinality(issues)>0 then raise exception 'Publiceren kan nog niet: %',array_to_string(issues,'; ');end if;
 end if;
 return new;
end $$;

CREATE OR REPLACE FUNCTION predict_private.ko_create(p_name text, p_sport uuid, p_kind text, p_roster text[], p_start timestamp with time zone, p_rules jsonb, p_mode text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare actor uuid:=predict_private.ko_admin(); tid uuid; cid uuid; sid text; n integer; size integer:=2; nr integer:=1;

  rd integer; pos integer; slots integer; byes integer; cursor_slot integer:=1; h integer; a integer; mid uuid; rid uuid; hf uuid; af uuid; rule jsonb; unit text; ft integer; title text;

begin

  n:=cardinality(p_roster);

  if p_name is null or length(btrim(p_name)) not between 1 and 120 or

    p_kind not in ('players','teams') or p_kind is null or n is null or n not between 2 and 128 or p_mode is null or p_mode not in ('replacement','additive') then raise exception 'Vul naam, toernooistart en 2â€“128 deelnemers in';end if;

  if exists(select 1 from unnest(p_roster) x where x is null or length(btrim(x))>80 or x~'[[:cntrl:]]') or

    (select count(distinct lower(btrim(x))) from unnest(p_roster) x where btrim(x)<>'')<>(select count(*) from unnest(p_roster) x where btrim(x)<>'') then raise exception 'Ingevulde namen moeten uniek zijn en maximaal 80 tekens hebben';end if;

  select slug into sid from public.sports where id=p_sport;

  if sid is null or sid not in ('darts','football') then raise exception 'Kies darts of voetbal';end if;

  while size<n loop size:=size*2;end loop;

  rd:=log(2,size)::integer;

  if jsonb_typeof(p_rules) is distinct from 'array' or jsonb_array_length(p_rules)<>rd then raise exception 'Vul het formaat en de punten voor iedere ronde in';end if;

  insert into public.competitions(sport_id,name) values(p_sport,btrim(p_name)) returning id into cid;

  insert into public.tournaments(competition_id,name,starts_at) values(cid,btrim(p_name),p_start) returning id into tid;

  insert into predict_private.knockout_tournaments values(tid,p_kind,array(select btrim(x) from unnest(p_roster)x),size);

  insert into public.tournament_scoring(tournament_id,scoring_mode) values(tid,p_mode);

  insert into predict_private.tournament_mutation_permits values(tid,txid_current(),actor);
  for r in 1..rd loop

    rule:=p_rules->(r-1);unit:=rule->>'unit';ft:=nullif(rule->>'first_to','')::integer;

    if (sid='darts' and (unit is null or unit not in ('sets','legs') or (ft is not null and ft not between 1 and 99))) or

       (sid='football' and (unit is distinct from 'goals' or ft is not null)) or

       

       (rule->>'winner_points')::integer not between 0 and 1000 or (rule->>'exact_points')::integer not between 0 and 1000 then raise exception 'Ongeldig rondeformaat of puntenschema';end if;

    title:=case rd-r when 0 then 'Finale' when 1 then 'Halve finales' when 2 then 'Kwartfinales' when 3 then 'Achtste finales' else 'Ronde '||r end;

    insert into public.tournament_rounds(tournament_id,name,round_order) values(tid,title,r) returning id into rid;

    insert into public.round_scoring(tournament_id,round_id,winner_points,exact_score_points) values(tid,rid,(rule->>'winner_points')::integer,(rule->>'exact_points')::integer);

    slots:=size/(2^r)::integer;byes:=size-n;

    for pos in 1..slots loop

      h:=null;a:=null;hf:=null;af:=null;

      if r=1 then

        h:=cursor_slot;cursor_slot:=cursor_slot+1;

        if byes=0 or ((pos-1)*byes)%slots>=byes then a:=cursor_slot;cursor_slot:=cursor_slot+1;end if;

      else

        select match_id,winner_slot into hf,h from predict_private.knockout_nodes where tournament_id=tid and round_no=r-1 and position=pos*2-1;

        select match_id,winner_slot into af,a from predict_private.knockout_nodes where tournament_id=tid and round_no=r-1 and position=pos*2;

      end if;

      insert into public.matches(tournament_id,round_id,home_name,away_name,score_unit,first_to,data_source,status)

        values(tid,rid,coalesce(nullif(p_roster[h],''),case when h is not null then 'Deelnemer '||h end,'Winnaar wedstrijd '||(select number from predict_private.knockout_nodes where match_id=hf)),

        case when r=1 and a is null then 'Vrijgesteld' else coalesce(nullif(p_roster[a],''),case when a is not null then 'Deelnemer '||a end,'Winnaar wedstrijd '||(select number from predict_private.knockout_nodes where match_id=af)) end,

        unit,ft,'manual_knockout',case when r=1 and a is null then 'cancelled' else 'scheduled' end) returning id into mid;

      insert into predict_private.knockout_nodes values(mid,tid,r,pos,nr,hf,af,h,a,case when r=1 and a is null then h end,null,r=1 and a is null);

      nr:=nr+1;

    end loop;

  end loop;

  delete from predict_private.tournament_mutation_permits where tournament_id=tid;
  return tid;

end $function$
;
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
    if not exists(select 1 from public.tournaments where id=p_tournament and status='draft') or
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
    update public.tournaments set starts_at=nullif(p_values->>'start','')::timestamptz where id=p_tournament;
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
    if (sport='darts' and (unit is null or unit not in ('legs','sets') or (ft is null and not exists(select 1 from public.tournaments where id=p_tournament and status='draft')) or (ft is not null and ft not between 1 and 99))) or (sport='football' and (unit is distinct from 'goals' or ft is not null)) then raise exception 'Ongeldig wedstrijdformaat';end if;
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
  select jsonb_build_object('tournament_id',t.id,'name',t.name,'status',t.status,'participant_kind',k.participant_kind,'roster',k.roster,'start',t.starts_at,'scoring_mode',(select scoring_mode from public.tournament_scoring where tournament_id=t.id),'sport',(select s.slug from public.competitions c join public.sports s on s.id=c.sport_id where c.id=t.competition_id),'publication_issues',predict_private.ko_publication_issues(t.id,t.starts_at),'server_now',clock_timestamp(),
    'rounds',(select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'order',r.round_order,'unit',(select score_unit from public.matches where round_id=r.id order by id limit 1),'first_to',(select first_to from public.matches where round_id=r.id order by id limit 1),'winner_points',(select winner_points from public.round_scoring where round_id=r.id),'exact_points',(select exact_score_points from public.round_scoring where round_id=r.id)) order by r.round_order) from public.tournament_rounds r where r.tournament_id=t.id),
    'matches',(select jsonb_agg(jsonb_build_object('id',m.id,'number',n.number,'round',n.round_no,'position',n.position,'home',m.home_name,'away',m.away_name,'home_slot',n.home_slot,'away_slot',n.away_slot,'winner_slot',n.winner_slot,'bye',n.is_bye,
      'start',m.scheduled_start,'actual_start',m.actual_start,'status',m.status,'home_score',m.home_score,'away_score',m.away_score,'unit',m.score_unit,'first_to',m.first_to,'enabled',m.predictions_enabled,'needs_review',m.needs_review) order by n.number)
      from predict_private.knockout_nodes n join public.matches m on m.id=n.match_id where n.tournament_id=t.id)) into result from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=p_id;
  return result;
end $function$
;
create or replace function predict_private.ko_save_template(p_name text,p_sport uuid,p_kind text,p_count integer,p_rules jsonb,p_mode text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();tid uuid;probe uuid;begin
 if p_name is null or length(btrim(p_name)) not between 1 and 80 or p_count is null or p_count not between 2 and 128 then raise exception 'Vul sjabloonnaam en 2–128 deelnemers in';end if;
 if jsonb_typeof(p_rules) is distinct from 'array' or exists(select 1 from jsonb_array_elements(p_rules)x where x->>'winner_points' is null or x->>'exact_points' is null or (x->>'unit' in('legs','sets') and x->>'first_to' is null)) then raise exception 'Vul het volledige formaat en de punten in om een sjabloon te bewaren';end if;
 -- A subtransaction reuses format validation, then rolls back all temporary rows.
 begin
  probe:=predict_private.ko_create(p_name,p_sport,p_kind,array_fill(''::text,array[p_count]),clock_timestamp()+interval '1 day',p_rules,p_mode);
  raise exception using errcode='ZK001',message='validation complete';
 exception when sqlstate 'ZK001' then null;end;
 insert into predict_private.knockout_templates(sport_id,name,participant_kind,participant_count,rules,scoring_mode,created_by)
 values(p_sport,btrim(p_name),p_kind,p_count,p_rules,p_mode,actor) returning id into tid;return tid;
end $$;
