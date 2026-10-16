-- Manual knockout only. Existing tournaments and scoring rules are not converted.
create table predict_private.knockout_tournaments (
  tournament_id uuid primary key references public.tournaments(id),
  participant_kind text not null check(participant_kind in ('players','teams')),
  roster text[] not null, bracket_size integer not null check(bracket_size between 2 and 128)
);
create table predict_private.knockout_nodes (
  match_id uuid primary key references public.matches(id),
  tournament_id uuid not null references predict_private.knockout_tournaments(tournament_id),
  round_no integer not null, position integer not null, number integer not null,
  home_from uuid references predict_private.knockout_nodes(match_id),
  away_from uuid references predict_private.knockout_nodes(match_id),
  home_slot integer, away_slot integer, winner_slot integer, tie_winner integer,
  is_bye boolean not null default false,
  unique(tournament_id,round_no,position),unique(tournament_id,number)
);
alter table predict_private.knockout_tournaments enable row level security;
alter table predict_private.knockout_nodes enable row level security;
revoke all on predict_private.knockout_tournaments,predict_private.knockout_nodes from public,anon,authenticated;
create index knockout_nodes_tournament on predict_private.knockout_nodes(tournament_id);
create index knockout_nodes_home_from on predict_private.knockout_nodes(home_from) where home_from is not null;
create index knockout_nodes_away_from on predict_private.knockout_nodes(away_from) where away_from is not null;

create function predict_private.ko_admin() returns uuid language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin')) then
    raise exception 'Geen beheerdersrechten' using errcode='42501';
  end if;
  return auth.uid();
end $$;

create function predict_private.ko_create(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin(); tid uuid; cid uuid; sid text; n integer; size integer:=2; nr integer:=1;
  rd integer; pos integer; slots integer; byes integer; cursor_slot integer:=1; h integer; a integer; mid uuid; rid uuid; hf uuid; af uuid; rule jsonb; unit text; ft integer; title text;
begin
  n:=cardinality(p_roster);
  if p_name is null or length(btrim(p_name)) not between 1 and 120 or p_start is null or p_start<=clock_timestamp() or
    p_kind not in ('players','teams') or p_kind is null or n is null or n not between 2 and 128 or p_mode is null or p_mode not in ('replacement','additive') then raise exception 'Vul naam, toekomstige toernooistart en 2–128 deelnemers in';end if;
  if exists(select 1 from unnest(p_roster) x where x is null or length(btrim(x)) not between 1 and 80 or x~'[[:cntrl:]]') or
    (select count(distinct lower(btrim(x))) from unnest(p_roster) x)<>n then raise exception 'Deelnemersnamen moeten uniek en niet leeg zijn';end if;
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
        if pos>byes then a:=cursor_slot;cursor_slot:=cursor_slot+1;end if;
      else
        select match_id,winner_slot into hf,h from predict_private.knockout_nodes where tournament_id=tid and round_no=r-1 and position=pos*2-1;
        select match_id,winner_slot into af,a from predict_private.knockout_nodes where tournament_id=tid and round_no=r-1 and position=pos*2;
      end if;
      insert into public.matches(tournament_id,round_id,home_name,away_name,score_unit,first_to,data_source,status)
        values(tid,rid,coalesce(p_roster[h],'Winnaar wedstrijd '||(select number from predict_private.knockout_nodes where match_id=hf)),
        case when r=1 and a is null then 'Vrijgesteld' else coalesce(p_roster[a],'Winnaar wedstrijd '||(select number from predict_private.knockout_nodes where match_id=af)) end,
        unit,ft,'manual_knockout',case when r=1 and a is null then 'cancelled' else 'scheduled' end) returning id into mid;
      insert into predict_private.knockout_nodes values(mid,tid,r,pos,nr,hf,af,h,a,case when r=1 and a is null then h end,null,r=1 and a is null);
      nr:=nr+1;
    end loop;
  end loop;
  return tid;
end $$;

-- Applied to any result route, including existing admin procedures.
create function predict_private.ko_propagate() returns trigger language plpgsql security definer set search_path='' as $$
declare node predict_private.knockout_nodes%rowtype; child predict_private.knockout_nodes%rowtype; cm public.matches%rowtype; winner integer; roster text[]; h integer; a integer;
begin
  select * into node from predict_private.knockout_nodes where match_id=new.id;
  if not found then return new;end if;
  if new.status='finished' then
    if node.is_bye or node.home_slot is null or node.away_slot is null then raise exception 'Vrijstelling of onbekende deelnemers kan geen uitslag krijgen';end if;
    winner:=case when new.home_score>new.away_score then node.home_slot when new.away_score>new.home_score then node.away_slot else node.tie_winner end;
    if winner is null or winner not in(node.home_slot,node.away_slot) then raise exception 'Kies bij gelijkspel de winnaar na verlenging of strafschoppen';end if;
  elsif node.is_bye then winner:=node.home_slot;
  end if;
  if winner is not distinct from node.winner_slot then return new;end if;
  update predict_private.knockout_nodes set winner_slot=winner where match_id=new.id;
  select * into child from predict_private.knockout_nodes where home_from=new.id or away_from=new.id for update;
  if found then
    select * into cm from public.matches where id=child.match_id for update;
    if cm.home_score is not null or cm.actual_start is not null or cm.status in ('live','finished') or
      exists(select 1 from public.match_predictions where match_id=cm.id) then raise exception 'Winnaar wijzigen geblokkeerd: volgende wedstrijd heeft voorspellingen of is gestart';end if;
    h:=case when child.home_from=new.id then winner else child.home_slot end;
    a:=case when child.away_from=new.id then winner else child.away_slot end;
    select k.roster into roster from predict_private.knockout_tournaments k where k.tournament_id=node.tournament_id;
    update predict_private.knockout_nodes set home_slot=h,away_slot=a where match_id=cm.id;
    update public.matches set predictions_enabled=false,updated_at=now() where id=cm.id;
    update public.matches set home_name=coalesce(roster[h],'Winnaar wedstrijd '||(select number from predict_private.knockout_nodes where match_id=child.home_from)),
      away_name=coalesce(roster[a],'Winnaar wedstrijd '||(select number from predict_private.knockout_nodes where match_id=child.away_from)) where id=cm.id;
    if h is not null and a is not null and cm.scheduled_start>clock_timestamp() and cm.start_time_confirmed and not cm.needs_review and cm.status='scheduled' and
      exists(select 1 from public.tournaments where id=cm.tournament_id and status in ('published','active')) then
      update public.matches set predictions_enabled=true where id=cm.id;
    end if;
    insert into public.match_audit_log(match_id,changed_by,action,old_values,new_values) values(cm.id,auth.uid(),'knockout_advancement',jsonb_build_object('home',cm.home_name,'away',cm.away_name),jsonb_build_object('source_match',new.id,'winner_slot',winner));
  end if;
  return new;
end $$;
create trigger knockout_result_advancement after update of home_score,away_score,status on public.matches for each row
  execute function predict_private.ko_propagate();

create function predict_private.ko_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare n predict_private.knockout_nodes%rowtype;
begin
  select * into n from predict_private.knockout_nodes where match_id=new.id;
  if found and not exists(select 1 from public.tournament_rounds where id=new.round_id and tournament_id=n.tournament_id and round_order=n.round_no) then raise exception 'De ronde ligt vast in het knock-outschema';end if;
  if found and (new.predictions_enabled or new.home_score is not null) and (n.is_bye or n.home_slot is null or n.away_slot is null) then
    raise exception 'Beide deelnemers moeten bekend zijn; vrijstellingen zijn niet voorspelbaar';
  end if;
  return new;
end $$;
create trigger knockout_participant_guard before update on public.matches for each row execute function predict_private.ko_guard();

create function predict_private.ko_catalog() returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform predict_private.ko_admin();
  return jsonb_build_object('sports',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'slug',slug)) from public.sports where slug in ('darts','football')),
    'tournaments',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'status',t.status)),'[]') from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id));
end $$;
create function predict_private.ko_schema(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean; result jsonb;
begin
  admin:=exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin'));
  if auth.uid() is null or not exists(select 1 from public.tournaments where id=p_id and (admin or status in ('published','active','completed','archived'))) then raise exception 'Toernooi niet beschikbaar' using errcode='42501';end if;
  if not exists(select 1 from predict_private.knockout_tournaments where tournament_id=p_id) then return null;end if;
  select jsonb_build_object('tournament_id',t.id,'name',t.name,'status',t.status,'participant_kind',k.participant_kind,'roster',k.roster,'server_now',clock_timestamp(),
    'rounds',(select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'order',r.round_order) order by r.round_order) from public.tournament_rounds r where r.tournament_id=t.id),
    'matches',(select jsonb_agg(jsonb_build_object('id',m.id,'number',n.number,'round',n.round_no,'position',n.position,'home',m.home_name,'away',m.away_name,'home_slot',n.home_slot,'away_slot',n.away_slot,'winner_slot',n.winner_slot,'bye',n.is_bye,
      'start',m.scheduled_start,'actual_start',m.actual_start,'status',m.status,'home_score',m.home_score,'away_score',m.away_score,'unit',m.score_unit,'first_to',m.first_to,'enabled',m.predictions_enabled,'needs_review',m.needs_review) order by n.number)
      from predict_private.knockout_nodes n join public.matches m on m.id=n.match_id where n.tournament_id=t.id)) into result from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=p_id;
  return result;
end $$;

-- A single serialized mutation API for new manual tournaments.
create function predict_private.ko_edit(p_tournament uuid,p_action text,p_match uuid,p_values jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin(); m public.matches%rowtype; n predict_private.knockout_nodes%rowtype; oldrow jsonb; start_at timestamptz; unit text; ft integer; sport text; winner integer; hs integer; aws integer; reason text;
begin
  perform 1 from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.id=p_tournament for update of t;
  if not found then raise exception 'Handmatig knock-outtoernooi niet gevonden';end if;
  if p_action='roster' then
    if not exists(select 1 from public.tournaments where id=p_tournament and status='draft') or exists(select 1 from public.match_predictions mp join public.matches mat on mat.id=mp.match_id where mat.tournament_id=p_tournament) then raise exception 'Namen kunnen alleen in een concept zonder voorspellingen worden gewijzigd';end if;
    if jsonb_typeof(p_values->'names') is distinct from 'array' or jsonb_array_length(p_values->'names')<>(select cardinality(roster) from predict_private.knockout_tournaments where tournament_id=p_tournament) or
      exists(select 1 from jsonb_array_elements(p_values->'names')x where jsonb_typeof(x)<>'string' or length(btrim(x#>>'{}')) not between 1 and 80 or (x#>>'{}')~'[[:cntrl:]]') or
      (select count(distinct lower(btrim(x))) from jsonb_array_elements_text(p_values->'names')x)<>jsonb_array_length(p_values->'names') then raise exception 'Vul hetzelfde aantal unieke namen in';end if;
    update predict_private.knockout_tournaments set roster=array(select btrim(x) from jsonb_array_elements_text(p_values->'names')x) where tournament_id=p_tournament;
    update public.matches mat set predictions_enabled=false where mat.tournament_id=p_tournament;
    update public.matches mat set home_name=coalesce(k.roster[nod.home_slot],mat.home_name),away_name=coalesce(k.roster[nod.away_slot],mat.away_name) from predict_private.knockout_nodes nod join predict_private.knockout_tournaments k on k.tournament_id=nod.tournament_id where mat.id=nod.match_id and nod.tournament_id=p_tournament;
    insert into public.scoring_audit_log(tournament_id,changed_by,action,old_values,new_values) values(p_tournament,actor,'knockout_roster_edit','{}',p_values);
    return true;
  end if;
  if p_action='publish' then
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

create function public.create_knockout_tournament(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text default 'replacement') returns uuid language sql security invoker set search_path='' as $$select predict_private.ko_create(p_name,p_sport,p_kind,p_roster,p_start,p_rules,p_mode)$$;
create function public.knockout_catalog() returns jsonb language sql security invoker set search_path='' as $$select predict_private.ko_catalog()$$;
create function public.get_knockout_schema(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select predict_private.ko_schema(p_id)$$;
create function public.edit_knockout(p_tournament uuid,p_action text,p_match uuid default null,p_values jsonb default '{}') returns boolean language sql security invoker set search_path='' as $$select predict_private.ko_edit(p_tournament,p_action,p_match,p_values)$$;
revoke all on function predict_private.ko_admin(),predict_private.ko_create(text,uuid,text,text[],timestamptz,jsonb,text),predict_private.ko_catalog(),predict_private.ko_schema(uuid),predict_private.ko_edit(uuid,text,uuid,jsonb),predict_private.ko_propagate(),predict_private.ko_guard() from public,anon,authenticated;
grant execute on function predict_private.ko_create(text,uuid,text,text[],timestamptz,jsonb,text),predict_private.ko_catalog(),predict_private.ko_schema(uuid),predict_private.ko_edit(uuid,text,uuid,jsonb) to authenticated;
revoke all on function public.create_knockout_tournament(text,uuid,text,text[],timestamptz,jsonb,text),public.knockout_catalog(),public.get_knockout_schema(uuid),public.edit_knockout(uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.create_knockout_tournament(text,uuid,text,text[],timestamptz,jsonb,text),public.knockout_catalog(),public.get_knockout_schema(uuid),public.edit_knockout(uuid,text,uuid,jsonb) to authenticated;
-- Retain historical records but remove every entry point to reviewed sports automation.
do $$declare f record;begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','predict_private') and p.proname in ('begin_darts_import','finish_darts_import','review_darts_import','list_darts_imports') loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  end loop;
end $$;
