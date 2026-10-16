-- Tournament lifecycle, permanent deletion with retained audit, champion predictions.
CREATE OR REPLACE FUNCTION public.guard_round_scoring_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_tournament_id UUID;
    v_starts_at TIMESTAMPTZ;
    v_is_locked BOOLEAN;
BEGIN
    IF predict_private.management_permitted(CASE WHEN TG_OP='DELETE' THEN OLD.tournament_id ELSE NEW.tournament_id END) THEN
      IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    v_tournament_id :=
        CASE
            WHEN TG_OP = 'DELETE'
            THEN OLD.tournament_id
            ELSE NEW.tournament_id
        END;

    SELECT t.starts_at, ts.is_locked
    INTO v_starts_at, v_is_locked
    FROM public.tournaments t
    JOIN public.tournament_scoring ts
      ON ts.tournament_id = t.id
    WHERE t.id = v_tournament_id
    FOR UPDATE OF t;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Toernooi of puntconfiguratie ontbreekt';
    END IF;

    IF COALESCE(v_is_locked, false)
       OR (
           v_starts_at IS NOT NULL
           AND clock_timestamp() >= v_starts_at
       )
    THEN
        RAISE EXCEPTION
            'Puntentelling is vergrendeld. Gebruik een afzonderlijke gelogde admincorrectie.';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE'
       AND NEW.tournament_id IS DISTINCT FROM
           OLD.tournament_id
    THEN
        RAISE EXCEPTION
            'Verplaatsen van puntenregels is niet toegestaan';
    END IF;

    RETURN NEW;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.guard_tournament_scoring_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_starts_at TIMESTAMPTZ;
BEGIN
    IF predict_private.management_permitted(CASE WHEN TG_OP='DELETE' THEN OLD.tournament_id ELSE NEW.tournament_id END) THEN
      IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;
    IF TG_OP = 'UPDATE'
       AND NEW.tournament_id IS DISTINCT FROM
           OLD.tournament_id
    THEN
        RAISE EXCEPTION
            'Verplaatsen van puntconfiguratie is verboden';
    END IF;

    SELECT starts_at
    INTO v_starts_at
    FROM public.tournaments
    WHERE id = CASE
        WHEN TG_OP = 'DELETE'
        THEN OLD.tournament_id
        ELSE NEW.tournament_id
    END
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Toernooi ontbreekt';
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD.is_locked
           OR (
               v_starts_at IS NOT NULL
               AND clock_timestamp() >= v_starts_at
           )
        THEN
            RAISE EXCEPTION
                'Vergrendelde puntenconfiguratie mag niet worden verwijderd';
        END IF;

        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF OLD.is_locked
           OR (
               v_starts_at IS NOT NULL
               AND clock_timestamp() >= v_starts_at
           )
        THEN
            -- Alleen alsnog vergrendelen is toegestaan.
            -- Andere instellingen moeten identiek blijven.
            IF NEW.is_locked IS DISTINCT FROM TRUE
               OR (
                   to_jsonb(NEW) - 'is_locked'
               ) IS DISTINCT FROM (
                   to_jsonb(OLD) - 'is_locked'
               )
            THEN
                RAISE EXCEPTION
                    'Puntenconfiguratie is vergrendeld';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$

;
create table predict_private.tournament_management_audit(id uuid primary key default gen_random_uuid(),tournament_id uuid not null,actor uuid not null,action text not null,reason text not null,details jsonb not null,created_at timestamptz not null default clock_timestamp());
create table predict_private.tournament_mutation_permits(tournament_id uuid primary key,transaction_id bigint not null,actor uuid not null);
create table predict_private.champion_settings(tournament_id uuid primary key references public.tournaments(id) on delete cascade,enabled boolean not null default true,deadline timestamptz not null,points integer not null check(points between 0 and 1000),choices text[] not null,actual_winner text);
create table predict_private.champion_predictions(tournament_id uuid not null references public.tournaments(id) on delete cascade,user_id uuid not null,choice text not null,updated_at timestamptz not null default clock_timestamp(),primary key(tournament_id,user_id));
alter table predict_private.tournament_management_audit enable row level security;
alter table predict_private.tournament_mutation_permits enable row level security;
alter table predict_private.champion_settings enable row level security;
alter table predict_private.champion_predictions enable row level security;
revoke all on predict_private.tournament_management_audit,predict_private.tournament_mutation_permits,predict_private.champion_settings,predict_private.champion_predictions from public,anon,authenticated;
create trigger protect_tournament_management_audit before update or delete on predict_private.tournament_management_audit for each row execute function public.prevent_scoring_audit_changes();
-- Historical audits retain original UUIDs after deletion; immutable audit triggers stay enabled.
do $$declare c record;begin
 for c in select conname,conrelid::regclass as tbl from pg_constraint where contype='f' and ((conrelid='public.match_audit_log'::regclass and confrelid='public.matches'::regclass) or (conrelid='public.scoring_audit_log'::regclass and confrelid='public.tournaments'::regclass)) loop
 execute format('alter table %s drop constraint %I',c.tbl,c.conname);end loop;
end $$;
create function predict_private.management_permitted(p_id uuid) returns boolean language sql security definer set search_path='' as $$
 select exists(select 1 from predict_private.tournament_mutation_permits p join public.user_roles r on r.user_id=p.actor where p.tournament_id=p_id and p.transaction_id=txid_current() and p.actor=auth.uid() and r.role in ('admin','super_admin'))
$$;
revoke all on function predict_private.management_permitted(uuid) from public,anon;
grant execute on function predict_private.management_permitted(uuid) to authenticated;

create function predict_private.tournament_counts(p_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('matches',(select count(*) from public.matches where tournament_id=p_id),'predictions',(select count(*) from public.match_predictions p join public.matches m on m.id=p.match_id where m.tournament_id=p_id),'entries',(select count(*) from public.tournament_entries where tournament_id=p_id),'pools',(select count(*) from public.pools where tournament_id=p_id),'results',(select count(*) from public.matches where tournament_id=p_id and home_score is not null),'winner_predictions',(select count(*) from predict_private.champion_predictions where tournament_id=p_id))
$$;
revoke all on function predict_private.tournament_counts(uuid) from public,anon,authenticated;

create function predict_private.management_catalog() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'status',t.status,'start',t.starts_at,'knockout',k.tournament_id is not null,'counts',predict_private.tournament_counts(t.id),'roster',coalesce(k.roster,array(select distinct x from public.matches m cross join lateral unnest(array[m.home_name,m.away_name])x where m.tournament_id=t.id and x<>'Vrijgesteld' and x not like 'Winnaar wedstrijd %' order by x)),'champion',(select to_jsonb(cs) from predict_private.champion_settings cs where cs.tournament_id=t.id),'rules',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'winner_points',rs.winner_points,'exact_points',rs.exact_score_points) order by r.round_order),'[]') from public.tournament_rounds r left join public.round_scoring rs on rs.round_id=r.id and rs.tournament_id=t.id where r.tournament_id=t.id)) order by t.name),'[]') from public.tournaments t left join predict_private.knockout_tournaments k on k.tournament_id=t.id);
end $$;

create function predict_private.manage_tournament(p_id uuid,p_action text,p_values jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();t public.tournaments%rowtype;counts jsonb;reason text:=btrim(coalesce(p_values->>'reason',''));new_start timestamptz;deadline_at timestamptz;choices text[];rule jsonb;old_champ predict_private.champion_settings%rowtype;
begin
 select * into t from public.tournaments where id=p_id for update;
 if not found then raise exception 'Toernooi niet gevonden';end if;
 if length(reason)<3 then raise exception 'Geef een reden van minimaal 3 tekens';end if;
 -- Lock match rows as well, so concurrent match submissions finish before lifecycle changes.
 perform 1 from public.matches where tournament_id=p_id order by id for update;
 counts:=predict_private.tournament_counts(p_id);
 if p_action='delete' then
  if p_values->>'confirm_name' is distinct from t.name or p_values->'expected' is distinct from counts then raise exception 'Bevestiging of aantallen gewijzigd. Vernieuw en controleer opnieuw.';end if;
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

create function predict_private.champion_winner(p_id uuid) returns text language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from predict_private.knockout_tournaments where tournament_id=p_id) then
 (select k.roster[n.winner_slot] from predict_private.knockout_nodes n join public.matches m on m.id=n.match_id join predict_private.knockout_tournaments k on k.tournament_id=n.tournament_id where n.tournament_id=p_id and m.status='finished' and n.round_no=(select max(round_no) from predict_private.knockout_nodes where tournament_id=p_id) limit 1)
 else (select actual_winner from predict_private.champion_settings where tournament_id=p_id) end
$$;
create function predict_private.champion_info(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c predict_private.champion_settings%rowtype;t public.tournaments%rowtype;deadline_at timestamptz;mine text;won text;begin
 if auth.uid() is null then raise exception 'Login vereist' using errcode='42501';end if;
 select * into t from public.tournaments where id=p_id;
 if t.id is null or (t.status='draft' and not exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin'))) then raise exception 'Toernooi niet beschikbaar' using errcode='42501';end if;
 select * into c from predict_private.champion_settings where tournament_id=p_id;
 if not found then return jsonb_build_object('enabled',false);end if;
 select least(c.deadline,t.starts_at,min(m.scheduled_start)) into deadline_at from public.matches m left join predict_private.knockout_nodes n on n.match_id=m.id where m.tournament_id=p_id and not coalesce(n.is_bye,false);
 select choice into mine from predict_private.champion_predictions where tournament_id=p_id and user_id=auth.uid();
 won:=predict_private.champion_winner(p_id);
 return jsonb_build_object('enabled',c.enabled,'deadline',deadline_at,'server_now',clock_timestamp(),'points',c.points,'choices',c.choices,'mine',mine,'winner',won,'earned_points',case when mine=won then c.points else 0 end,'open',c.enabled and t.status in ('published','active') and clock_timestamp()<deadline_at and not exists(select 1 from public.matches m left join predict_private.knockout_nodes n on n.match_id=m.id where m.tournament_id=p_id and not coalesce(n.is_bye,false) and (m.actual_start is not null or m.home_score is not null or m.status='live')));
end $$;
create function predict_private.champion_submit(p_id uuid,p_choice text) returns boolean language plpgsql security definer set search_path='' as $$
declare info jsonb;begin
 if auth.uid() is null then raise exception 'Login vereist' using errcode='42501';end if;
 perform 1 from public.tournaments where id=p_id for update;
 perform 1 from public.matches where tournament_id=p_id order by id for update;
 perform 1 from predict_private.champion_settings where tournament_id=p_id for update;
 info:=predict_private.champion_info(p_id);
 if not coalesce((info->>'open')::boolean,false) or not exists(select 1 from public.tournament_entries where tournament_id=p_id and user_id=auth.uid()) then raise exception 'Winnaar voorspellen is gesloten of je neemt nog niet deel' using errcode='42501';end if;
 if p_choice is null or not exists(select 1 from jsonb_array_elements_text(info->'choices')x where x=p_choice) then raise exception 'Kies een deelnemer uit dit toernooi';end if;
 insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details) values(p_id,auth.uid(),'champion_prediction','Eigen winnaarsvoorspelling',jsonb_build_object('before',(select choice from predict_private.champion_predictions where tournament_id=p_id and user_id=auth.uid()),'choice',p_choice));
 insert into predict_private.champion_predictions(tournament_id,user_id,choice) values(p_id,auth.uid(),p_choice) on conflict(tournament_id,user_id) do update set choice=excluded.choice,updated_at=clock_timestamp();return true;
end $$;
create function predict_private.champion_roster_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.roster is distinct from old.roster and exists(select 1 from predict_private.champion_settings where tournament_id=old.tournament_id) then raise exception 'Deelnemers staan vast zolang de winnaarsvraag is ingesteld';end if;return new;end $$;
create trigger champion_roster_guard before update of roster on predict_private.knockout_tournaments for each row execute function predict_private.champion_roster_guard();

alter function public.get_tournament_leaderboard(uuid,uuid,uuid) set schema predict_private;
alter function predict_private.get_tournament_leaderboard(uuid,uuid,uuid) rename to match_leaderboard_base;
revoke all on function predict_private.match_leaderboard_base(uuid,uuid,uuid) from public,anon,authenticated;
create function predict_private.combined_leaderboard(p_tournament_id uuid,p_pool_id uuid,p_round_id uuid)
returns table(user_id uuid,display_name text,earned_points bigint,correct_winners bigint,exact_scores bigint,scored_predictions bigint,rank_position bigint) language sql stable security definer set search_path='' as $$
 with rows as(select b.*,case when p_round_id is null and cp.choice=predict_private.champion_winner(p_tournament_id) then coalesce(cs.points,0) else 0 end as bonus
 from predict_private.match_leaderboard_base(p_tournament_id,p_pool_id,p_round_id)b
 left join predict_private.champion_predictions cp on cp.tournament_id=p_tournament_id and cp.user_id=b.user_id
 left join predict_private.champion_settings cs on cs.tournament_id=p_tournament_id)
 select r.user_id,r.display_name,(r.earned_points+r.bonus)::bigint,r.correct_winners,r.exact_scores,r.scored_predictions,rank() over(order by r.earned_points+r.bonus desc,r.correct_winners desc)::bigint from rows r order by r.earned_points+r.bonus desc,r.correct_winners desc,r.display_name
$$;
create function public.get_tournament_leaderboard(p_tournament_id uuid,p_pool_id uuid default null,p_round_id uuid default null)
returns table(user_id uuid,display_name text,earned_points bigint,correct_winners bigint,exact_scores bigint,scored_predictions bigint,rank_position bigint) language sql stable security invoker set search_path='' as $$select * from predict_private.combined_leaderboard(p_tournament_id,p_pool_id,p_round_id)$$;
create function public.admin_tournament_catalog() returns jsonb language sql security invoker set search_path='' as $$select predict_private.management_catalog()$$;
create function public.manage_tournament(p_id uuid,p_action text,p_values jsonb default '{}') returns boolean language sql security invoker set search_path='' as $$select predict_private.manage_tournament(p_id,p_action,p_values)$$;
create function public.get_champion_prediction(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select predict_private.champion_info(p_id)$$;
create function public.submit_champion_prediction(p_id uuid,p_choice text) returns boolean language sql security invoker set search_path='' as $$select predict_private.champion_submit(p_id,p_choice)$$;
revoke all on function predict_private.management_catalog(),predict_private.manage_tournament(uuid,text,jsonb),predict_private.champion_winner(uuid),predict_private.champion_info(uuid),predict_private.champion_submit(uuid,text),predict_private.champion_roster_guard(),predict_private.combined_leaderboard(uuid,uuid,uuid),public.admin_tournament_catalog(),public.manage_tournament(uuid,text,jsonb),public.get_champion_prediction(uuid),public.submit_champion_prediction(uuid,text),public.get_tournament_leaderboard(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function predict_private.management_catalog(),predict_private.manage_tournament(uuid,text,jsonb),predict_private.champion_info(uuid),predict_private.champion_submit(uuid,text),predict_private.combined_leaderboard(uuid,uuid,uuid),public.admin_tournament_catalog(),public.manage_tournament(uuid,text,jsonb),public.get_champion_prediction(uuid),public.submit_champion_prediction(uuid,text),public.get_tournament_leaderboard(uuid,uuid,uuid) to authenticated;

create or replace function predict_private.ko_create(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin(); tid uuid; cid uuid; sid text; n integer; size integer:=2; nr integer:=1;
  rd integer; pos integer; slots integer; byes integer; cursor_slot integer:=1; h integer; a integer; mid uuid; rid uuid; hf uuid; af uuid; rule jsonb; unit text; ft integer; title text;
begin
  n:=cardinality(p_roster);
  if p_name is null or length(btrim(p_name)) not between 1 and 120 or p_start is null or
    p_kind not in ('players','teams') or p_kind is null or n is null or n not between 2 and 128 or p_mode is null or p_mode not in ('replacement','additive') then raise exception 'Vul naam, toernooistart en 2–128 deelnemers in';end if;
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

-- A deadline can close earlier, never reopen after a schedule correction or early start.
create function predict_private.champion_deadline_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='tournaments' then
  update predict_private.champion_settings set deadline=least(deadline,new.starts_at) where tournament_id=new.id;
 else
  if not exists(select 1 from predict_private.knockout_nodes where match_id=new.id and is_bye) then
   update predict_private.champion_settings set deadline=least(deadline,new.scheduled_start,new.actual_start,case when new.status in ('live','finished') then clock_timestamp() end) where tournament_id=new.tournament_id;
  end if;
 end if;return new;
end $$;
create trigger champion_match_deadline after update of scheduled_start,actual_start,status,home_score on public.matches for each row execute function predict_private.champion_deadline_guard();
create trigger champion_tournament_deadline after update of starts_at on public.tournaments for each row execute function predict_private.champion_deadline_guard();
revoke all on function predict_private.champion_deadline_guard() from public,anon,authenticated;

do $$begin
 if to_regclass('auth.users') is not null then
  alter table predict_private.champion_predictions add constraint champion_prediction_user foreign key(user_id) references auth.users(id) on delete cascade;
 end if;
end $$;
