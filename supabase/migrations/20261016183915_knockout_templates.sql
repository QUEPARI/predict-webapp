-- Empty draft slots and reusable sport templates. Existing brackets are never rebuilt.
create or replace function predict_private.ko_create(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin(); tid uuid; cid uuid; sid text; n integer; size integer:=2; nr integer:=1;
  rd integer; pos integer; slots integer; byes integer; cursor_slot integer:=1; h integer; a integer; mid uuid; rid uuid; hf uuid; af uuid; rule jsonb; unit text; ft integer; title text;
begin
  n:=cardinality(p_roster);
  if p_name is null or length(btrim(p_name)) not between 1 and 120 or p_start is null or p_start<=clock_timestamp() or
    p_kind not in ('players','teams') or p_kind is null or n is null or n not between 2 and 128 or p_mode is null or p_mode not in ('replacement','additive') then raise exception 'Vul naam, toekomstige toernooistart en 2–128 deelnemers in';end if;
  if exists(select 1 from unnest(p_roster) x where x is null or length(btrim(x))>80 or x~'[[:cntrl:]]') or
    (select count(distinct lower(btrim(x))) from unnest(p_roster) x where btrim(x)<>'')<>(select count(*) from unnest(p_roster) x where btrim(x)<>'') then raise exception 'Ingevulde namen moeten uniek zijn en maximaal 80 tekens hebben';end if;
  select slug into sid from public.sports where id=p_sport;
  if sid is null or sid not in ('darts','football') then raise exception 'Kies darts of voetbal';end if;
  while size<n loop size:=size*2;end loop;
  rd:=log(2,size)::integer;
  if jsonb_typeof(p_rules)<>'array' or jsonb_array_length(p_rules)<>rd then raise exception 'Vul het formaat en de punten voor iedere ronde in';end if;
  insert into public.competitions(sport_id,name) values(p_sport,btrim(p_name)) returning id into cid;
  insert into public.tournaments(competition_id,name,starts_at) values(cid,btrim(p_name),p_start) returning id into tid;
  insert into predict_private.knockout_tournaments values(tid,p_kind,array(select btrim(x) from unnest(p_roster)x),size);
  insert into public.tournament_scoring(tournament_id,scoring_mode) values(tid,p_mode);
  for r in 1..rd loop
    rule:=p_rules->(r-1);unit:=rule->>'unit';ft:=nullif(rule->>'first_to','')::integer;
    if (sid='darts' and (unit is null or unit not in ('sets','legs') or ft is null or ft not between 1 and 99)) or
       (sid='football' and (unit is distinct from 'goals' or ft is not null)) or
       (rule->>'winner_points')::integer is null or (rule->>'exact_points')::integer is null or
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
  return tid;
end $$;
create or replace function predict_private.ko_edit(p_tournament uuid,p_action text,p_match uuid,p_values jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin(); m public.matches%rowtype; n predict_private.knockout_nodes%rowtype; oldrow jsonb; start_at timestamptz; unit text; ft integer; sport text; winner integer; hs integer; aws integer; reason text;
begin
  perform 1 from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=p_tournament for update of t;
  if not found then raise exception 'Handmatig knock-outtoernooi niet gevonden';end if;
  if p_action='roster' then
    if not exists(select 1 from public.tournaments where id=p_tournament and status='draft') or exists(select 1 from public.match_predictions mp join public.matches mat on mat.id=mp.match_id where mat.tournament_id=p_tournament) then raise exception 'Namen kunnen alleen in een concept zonder voorspellingen worden gewijzigd';end if;
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
    -- Saving a time never reopens a closed or postponed match. Publish/open are explicit actions.
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
end $$;
create or replace function predict_private.ko_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare n predict_private.knockout_nodes%rowtype;
begin
  select * into n from predict_private.knockout_nodes where match_id=new.id;
  if found and not exists(select 1 from public.tournament_rounds where id=new.round_id and tournament_id=n.tournament_id and round_order=n.round_no) then raise exception 'De ronde ligt vast in het knock-outschema';end if;
  if found and (new.predictions_enabled or new.home_score is not null) and (n.is_bye or n.home_slot is null or n.away_slot is null or exists(select 1 from predict_private.knockout_tournaments k where k.tournament_id=n.tournament_id and (nullif(k.roster[n.home_slot],'') is null or nullif(k.roster[n.away_slot],'') is null))) then
    raise exception 'Beide deelnemers moeten bekend zijn; vrijstellingen zijn niet voorspelbaar';
  end if;
  return new;
end $$;

create function predict_private.ko_publication_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status in ('published','active') and exists(select 1 from predict_private.knockout_tournaments k,unnest(k.roster)x where k.tournament_id=new.id and btrim(x)='') then raise exception 'Vul eerst alle deelnemers in het schema in';end if;
 return new;
end $$;
create trigger knockout_publication_guard before update of status on public.tournaments for each row execute function predict_private.ko_publication_guard();
revoke all on function predict_private.ko_publication_guard() from public,anon,authenticated;
create table predict_private.knockout_templates(
 id uuid primary key default gen_random_uuid(),sport_id uuid not null references public.sports(id),name text not null check(length(btrim(name)) between 1 and 80),
 participant_kind text not null check(participant_kind in ('players','teams')),participant_count integer not null check(participant_count between 2 and 128),
 rules jsonb not null,scoring_mode text not null check(scoring_mode in ('replacement','additive')),created_by uuid not null,created_at timestamptz not null default now()
);
alter table predict_private.knockout_templates enable row level security;
revoke all on predict_private.knockout_templates from public,anon,authenticated;
create index knockout_templates_sport on predict_private.knockout_templates(sport_id);
create function predict_private.ko_save_template(p_name text,p_sport uuid,p_kind text,p_count integer,p_rules jsonb,p_mode text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();tid uuid;probe uuid;begin
 if p_name is null or length(btrim(p_name)) not between 1 and 80 or p_count is null or p_count not between 2 and 128 then raise exception 'Vul sjabloonnaam en 2–128 deelnemers in';end if;
 -- A subtransaction reuses format validation, then rolls back all temporary rows.
 begin
  probe:=predict_private.ko_create(p_name,p_sport,p_kind,array_fill(''::text,array[p_count]),clock_timestamp()+interval '1 day',p_rules,p_mode);
  raise exception using errcode='ZK001',message='validation complete';
 exception when sqlstate 'ZK001' then null;end;
 insert into predict_private.knockout_templates(sport_id,name,participant_kind,participant_count,rules,scoring_mode,created_by)
 values(p_sport,btrim(p_name),p_kind,p_count,p_rules,p_mode,actor) returning id into tid;return tid;
end $$;
create function public.save_knockout_template(p_name text,p_sport uuid,p_kind text,p_count integer,p_rules jsonb,p_mode text) returns uuid language sql security invoker set search_path='' as $$select predict_private.ko_save_template(p_name,p_sport,p_kind,p_count,p_rules,p_mode)$$;
revoke all on function predict_private.ko_save_template(text,uuid,text,integer,jsonb,text),public.save_knockout_template(text,uuid,text,integer,jsonb,text) from public,anon,authenticated;
grant execute on function predict_private.ko_save_template(text,uuid,text,integer,jsonb,text),public.save_knockout_template(text,uuid,text,integer,jsonb,text) to authenticated;

create or replace function predict_private.ko_catalog() returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform predict_private.ko_admin();
  return jsonb_build_object('sports',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'slug',slug)) from public.sports where slug in ('darts','football')),
    'templates',(select coalesce(jsonb_agg(to_jsonb(v) order by v.name),'[]') from (select id,sport_id,name,participant_kind,participant_count,rules,scoring_mode from predict_private.knockout_templates)v),
    'tournaments',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'status',t.status)),'[]') from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id));
end $$;
