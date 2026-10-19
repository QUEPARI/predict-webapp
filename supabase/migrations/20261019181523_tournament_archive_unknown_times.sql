-- NNB times are real null timestamps. Before the tournament starts they may be predicted.
create function predict_private.prediction_time_open(p_tournament uuid,p_start timestamptz,p_confirmed boolean) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(case when p_start is not null then p_confirmed and p_start>clock_timestamp() else exists(select 1 from predict_private.mastercaller_sources s join public.tournaments t on t.id=s.tournament_id where t.id=p_tournament and s.automatic_setup and t.starts_at>clock_timestamp()) end,false)
$$;
revoke all on function predict_private.prediction_time_open(uuid,timestamptz,boolean) from public,anon;
grant execute on function predict_private.prediction_time_open(uuid,timestamptz,boolean) to authenticated,service_role;
CREATE OR REPLACE FUNCTION public.guard_prediction_opening()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_opening BOOLEAN;
BEGIN
    -- Alleen de overgang van gesloten naar open
    -- vereist een volledige vrijgavecontrole.
    IF TG_OP = 'INSERT' THEN
        v_opening := NEW.predictions_enabled;
    ELSE
        v_opening :=
            NEW.predictions_enabled
            AND NOT OLD.predictions_enabled;
    END IF;

    IF v_opening THEN

        IF NEW.status <> 'scheduled'
           OR NEW.actual_start IS NOT NULL
           OR NEW.home_score IS NOT NULL
           OR NEW.away_score IS NOT NULL
        THEN
            RAISE EXCEPTION
                'Wedstrijd is niet beschikbaar voor voorspellingen.';
        END IF;

        IF NOT predict_private.prediction_time_open(NEW.tournament_id,NEW.scheduled_start,NEW.start_time_confirmed)
        THEN
            RAISE EXCEPTION
                'Een toekomstige, bevestigde individuele starttijd is vereist.';
        END IF;

        IF NEW.needs_review
           OR NEW.round_id IS NULL
        THEN
            RAISE EXCEPTION
                'Wedstrijd moet eerst worden goedgekeurd.';
        END IF;

        IF NEW.score_unit IN ('sets', 'legs')
           AND NEW.first_to IS NULL
        THEN
            RAISE EXCEPTION
                'Wedstrijdformaat is niet vastgesteld.';
        END IF;

    END IF;

    -- Voorkom dat een open wedstrijd buiten
    -- de gecontroleerde procedure een andere
    -- ronde, starttijd of deelnemers krijgt.
    IF TG_OP = 'UPDATE'
       AND OLD.predictions_enabled
       AND NEW.predictions_enabled
       AND (
           NEW.scheduled_start IS DISTINCT FROM OLD.scheduled_start
           OR NEW.round_id IS DISTINCT FROM OLD.round_id
           OR NEW.home_name IS DISTINCT FROM OLD.home_name
           OR NEW.away_name IS DISTINCT FROM OLD.away_name
           OR NEW.first_to IS DISTINCT FROM OLD.first_to
       )
    THEN
        RAISE EXCEPTION
            'Sluit voorspellingen en gebruik de gecontroleerde correctieprocedure.';
    END IF;

    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.guard_prediction_submission()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_match public.matches%ROWTYPE;
BEGIN
    SELECT *
    INTO v_match
    FROM public.matches
    WHERE id = NEW.match_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Wedstrijd niet gevonden.';
    END IF;

    IF NOT v_match.predictions_enabled
       OR v_match.needs_review
       OR v_match.round_id IS NULL
       OR v_match.status <> 'scheduled'
       OR v_match.actual_start IS NOT NULL
       OR NOT predict_private.prediction_time_open(v_match.tournament_id,v_match.scheduled_start,v_match.start_time_confirmed)
    THEN
        RAISE EXCEPTION
            'Voorspellen is niet toegestaan voor deze wedstrijd.';
    END IF;

    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.guard_started_match_predictions()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$begin
 -- A permitted label correction changes no deadline, status or prediction flag.
 if TG_OP='UPDATE' and predict_private.management_permitted(new.tournament_id)
   and (to_jsonb(new)-'home_name'-'away_name')=(to_jsonb(old)-'home_name'-'away_name') then return new;end if;
 if new.predictions_enabled and (new.status<>'scheduled' or new.actual_start is not null or not predict_private.prediction_time_open(new.tournament_id,new.scheduled_start,new.start_time_confirmed))
 then raise exception 'Voorspellingen moeten gesloten zijn zodra de wedstrijd begonnen is of de deadline verstreken is.';end if;return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.submit_match_prediction(p_match_id uuid, p_home_score integer, p_away_score integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_match public.matches%ROWTYPE;
    v_tournament_status TEXT;
    v_prediction_id UUID;
    v_checked_at TIMESTAMPTZ;
BEGIN
    -- 1. Inloggen verplicht.
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Je moet ingelogd zijn.'
            USING ERRCODE = '42501';
    END IF;

    IF p_match_id IS NULL THEN
        RAISE EXCEPTION 'Wedstrijd ontbreekt.';
    END IF;

    -- 2. Voorspelde scores controleren.
    IF p_home_score IS NULL
       OR p_away_score IS NULL
       OR p_home_score NOT BETWEEN 0 AND 99
       OR p_away_score NOT BETWEEN 0 AND 99
    THEN
        RAISE EXCEPTION 'Ongeldige voorspelling.';
    END IF;

    -- 3. Wedstrijd vergrendelen.
    -- Hierdoor kan een gelijktijdige startregistratie
    -- of uitslagwijziging niet ongemerkt tussendoor
    -- worden uitgevoerd.
    SELECT *
    INTO v_match
    FROM public.matches
    WHERE id = p_match_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Wedstrijd niet gevonden.';
    END IF;

    -- Neem het huidige tijdstip na de vergrendeling.
    v_checked_at := clock_timestamp();

    -- 4. Wedstrijd moet goedgekeurd en open zijn.
    IF v_match.predictions_enabled IS DISTINCT FROM TRUE
       OR v_match.needs_review IS DISTINCT FROM FALSE
       OR v_match.round_id IS NULL
    THEN
        RAISE EXCEPTION
            'Deze wedstrijd is niet vrijgegeven voor voorspellingen.';
    END IF;

    -- 5. Alleen geplande, nog niet gestarte wedstrijden.
    IF v_match.status IS DISTINCT FROM 'scheduled'
       OR v_match.actual_start IS NOT NULL
       OR v_match.home_score IS NOT NULL
       OR v_match.away_score IS NOT NULL
    THEN
        RAISE EXCEPTION
            'Deze wedstrijd is al begonnen of niet beschikbaar.';
    END IF;

    -- 6. Individuele wedstrijddeadline.
    IF NOT predict_private.prediction_time_open(v_match.tournament_id,v_match.scheduled_start,v_match.start_time_confirmed)
    THEN
        RAISE EXCEPTION
            'De individuele voorspeldeadline is verstreken of onbekend.';
    END IF;

    -- 7. Toernooistatus.
    SELECT t.status
    INTO v_tournament_status
    FROM public.tournaments t
    WHERE t.id = v_match.tournament_id;

    IF v_tournament_status IS NULL
       OR v_tournament_status NOT IN (
           'published', 'active'
       )
    THEN
        RAISE EXCEPTION 'Toernooi niet beschikbaar.';
    END IF;

    -- 8. Gebruiker moet deelnemen aan dit toernooi.
    IF NOT EXISTS (
        SELECT 1
        FROM public.tournament_entries te
        WHERE te.tournament_id = v_match.tournament_id
          AND te.user_id = v_user_id
    ) THEN
        RAISE EXCEPTION
            'Je neemt nog niet deel aan dit toernooi.';
    END IF;

    -- 9. Wedstrijdformaat en score controleren.
    IF v_match.score_unit IN ('sets', 'legs') THEN

        IF v_match.first_to IS NULL
           OR v_match.first_to NOT BETWEEN 1 AND 99
        THEN
            RAISE EXCEPTION
                'Het wedstrijdformaat is niet vastgesteld.';
        END IF;

        -- Precies één speler bereikt het vereiste
        -- aantal sets of legs.
        IF NOT (
            (
                p_home_score = v_match.first_to
                AND p_away_score < v_match.first_to
            )
            OR
            (
                p_away_score = v_match.first_to
                AND p_home_score < v_match.first_to
            )
        ) THEN
            RAISE EXCEPTION
                'Ongeldige voorspelde set- of legstand.';
        END IF;

    ELSIF v_match.score_unit = 'goals' THEN

        IF v_match.first_to IS NOT NULL THEN
            RAISE EXCEPTION
                'Ongeldig wedstrijdformaat voor voetbal.';
        END IF;

        -- Gelijke standen zijn toegestaan.
        -- Strafschoppen worden niet meegeteld.

    ELSE
        RAISE EXCEPTION
            'Onbekend wedstrijdformaat.';
    END IF;

    -- 10. Voorspelling opslaan of wijzigen.
    -- Eén voorspelling per gebruiker per wedstrijd.
    INSERT INTO public.match_predictions (
        match_id,
        user_id,
        home_score,
        away_score
    )
    VALUES (
        p_match_id,
        v_user_id,
        p_home_score,
        p_away_score
    )
    ON CONFLICT (match_id, user_id)
    DO UPDATE SET
        home_score = EXCLUDED.home_score,
        away_score = EXCLUDED.away_score,
        updated_at = now()
    RETURNING id INTO v_prediction_id;

    RETURN v_prediction_id;
END;
$function$
;

-- Explicit source marker preserves the database check for every manual match.
alter table public.matches add column source_time_pending boolean not null default false;
alter table public.matches drop constraint predictions_require_start;
alter table public.matches add constraint predictions_require_start check (not predictions_enabled or scheduled_start is not null or source_time_pending);
alter table public.matches add column prediction_window_closed boolean not null default false;
alter table public.tournaments add column admin_archived boolean not null default false;
create or replace function predict_private.sync_mastercaller_schema_internal(p_tournament uuid,p_snapshot jsonb) returns void language plpgsql security definer set search_path='' as $$
declare cfg predict_private.mastercaller_sources%rowtype;k predict_private.knockout_tournaments%rowtype;f jsonb;m public.matches%rowtype;n predict_private.knockout_nodes%rowtype;rule jsonb;start_at timestamptz;nr integer;roster text[];
begin
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_tournament;
 if not cfg.automatic_setup then return;end if;
 if p_snapshot is null or predict_private.mastercaller_url(p_snapshot->>'url') is distinct from cfg.url or jsonb_typeof(p_snapshot->'bracket') is distinct from 'array' then raise exception 'Ongeldig bronschema';end if;
 perform 1 from public.tournaments where id=p_tournament for update;
 select * into k from predict_private.knockout_tournaments where tournament_id=p_tournament;
 select array_agg(value order by ord) into roster from jsonb_array_elements_text(p_snapshot->'roster') with ordinality x(value,ord);
 if cardinality(roster) is distinct from cardinality(k.roster) or exists(select 1 from unnest(roster,k.roster) x(a,b) where predict_private.score_name(a) is distinct from predict_private.score_name(b)) then raise exception 'De loting is gewijzigd; automatische verwerking gepauzeerd';end if;
 select count(*) into nr from public.tournament_rounds where tournament_id=p_tournament;
 if jsonb_array_length(p_snapshot->'rounds')<>nr or jsonb_array_length(p_snapshot->'bracket')<>cardinality(roster)-1 then raise exception 'Onvolledig bronschema';end if;
 for f in select value from jsonb_array_elements(p_snapshot->'bracket') loop
  select * into n from predict_private.knockout_nodes where tournament_id=p_tournament and round_no=(f->>'order')::integer and position=(f->>'position')::integer;
  if not found then raise exception 'Schemapositie ontbreekt';end if;
  select * into m from public.matches where id=n.match_id for update;
  if m.status<>'scheduled' or m.actual_start is not null or m.home_score is not null then continue;end if;
  select value into rule from jsonb_array_elements(p_snapshot->'rounds') where (value->>'order')::integer=n.round_no;
  if rule->>'unit' is distinct from m.score_unit or (rule->>'first_to')::integer is distinct from m.first_to then raise exception 'Het wedstrijdformat in de bron is gewijzigd';end if;
  if (nullif(f->>'home_name','') is not null and n.home_slot is not null and predict_private.score_name(f->>'home_name')<>predict_private.score_name(m.home_name))
   or (nullif(f->>'away_name','') is not null and n.away_slot is not null and predict_private.score_name(f->>'away_name')<>predict_private.score_name(m.away_name)) then raise exception 'Deelnemers wijken af van het bronschema';end if;
  start_at:=nullif(f->>'start','')::timestamptz;
  -- A known elapsed deadline stays closed even when the source removes its time.
  update public.matches set predictions_enabled=false where id=m.id;
  -- A source delay must not reopen an already expired prediction window.
  update public.matches set scheduled_start=start_at,start_time_confirmed=start_at is not null,source_time_pending=start_at is null,needs_review=false,
   prediction_window_closed=m.prediction_window_closed or coalesce(m.scheduled_start<=clock_timestamp(),false),
   predictions_enabled=not m.prediction_window_closed and (m.scheduled_start is null or m.scheduled_start>clock_timestamp())
    and predict_private.prediction_time_open(p_tournament,start_at,start_at is not null)
    and n.home_slot is not null and n.away_slot is not null
    and exists(select 1 from public.tournaments where id=p_tournament and status in('published','active')),
   updated_at=now() where id=m.id;
 end loop;
 update predict_private.mastercaller_sources set snapshot=p_snapshot-'records' where tournament_id=p_tournament;
end $$;

-- Apply the new opening rules to already imported tournaments, using the same protected sync path.
do $$declare s record;begin
 for s in select tournament_id,snapshot from predict_private.mastercaller_sources where automatic_setup and snapshot is not null loop
  perform predict_private.sync_mastercaller_schema(s.tournament_id,s.snapshot);
 end loop;
end $$;

create function predict_private.tournament_finished(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tournaments t where t.id=p_id and t.ends_at<=clock_timestamp())
 and exists(select 1 from public.matches m where m.tournament_id=p_id and not exists(select 1 from predict_private.knockout_nodes n where n.match_id=m.id and n.is_bye))
 and not exists(select 1 from public.matches m where m.tournament_id=p_id and not exists(select 1 from predict_private.knockout_nodes n where n.match_id=m.id and n.is_bye) and (m.status<>'finished' or m.home_score is null or m.away_score is null))
$$;
revoke all on function predict_private.tournament_finished(uuid) from public,anon,authenticated,service_role;
-- Management archiving does not change the public status or the existing seven-day expiry.
alter function predict_private.manage_tournament(uuid,text,jsonb) rename to manage_tournament_before_archive;
revoke all on function predict_private.manage_tournament_before_archive(uuid,text,jsonb) from public,anon,authenticated,service_role;
create function predict_private.manage_tournament(p_id uuid,p_action text,p_values jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();t public.tournaments%rowtype;
begin
 if p_action not in('archive','unarchive') then return predict_private.manage_tournament_before_archive(p_id,p_action,p_values);end if;
 select * into t from public.tournaments where id=p_id for update;
 if not found then raise exception 'Toernooi niet gevonden';end if;
 perform 1 from public.matches where tournament_id=p_id order by id for update;
 if p_action='archive' and not predict_private.tournament_finished(p_id) then raise exception 'Archiveren kan zodra het toernooi is afgelopen en alle uitslagen bekend zijn';end if;
 update public.tournaments set admin_archived=(p_action='archive') where id=p_id;
 insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details) values(p_id,actor,p_action,'Toernooibeheer: '||p_action,jsonb_build_object('previous_admin_archived',t.admin_archived,'player_visible_until',t.ends_at+interval '168 hours'));
 return true;
end $$;
revoke all on function predict_private.manage_tournament(uuid,text,jsonb) from public,anon;
grant execute on function predict_private.manage_tournament(uuid,text,jsonb) to authenticated;
alter function predict_private.management_catalog() rename to management_catalog_before_archive;
revoke all on function predict_private.management_catalog_before_archive() from public,anon,authenticated,service_role;
create function predict_private.management_catalog() returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(x||jsonb_build_object('admin_archived',t.admin_archived,'finished',predict_private.tournament_finished(t.id))),'[]') from jsonb_array_elements(predict_private.management_catalog_before_archive())x join public.tournaments t on t.id=(x->>'id')::uuid);
end $$;
revoke all on function predict_private.management_catalog() from public,anon;
grant execute on function predict_private.management_catalog() to authenticated;
create or replace function predict_private.tournament_prediction_counts() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Login vereist' using errcode='42501';end if;
 with eligible as(
 select m.id,m.tournament_id,coalesce(m.scheduled_start,(select starts_at from public.tournaments where id=m.tournament_id)) as scheduled_start,mp.id as prediction_id
 from public.matches m join public.tournaments t on t.id=m.tournament_id
 left join public.match_predictions mp on mp.match_id=m.id and mp.user_id=auth.uid()
 where t.status in ('published','active') and m.predictions_enabled and m.status='scheduled' and m.actual_start is null and m.home_score is null and m.away_score is null and not m.needs_review and m.round_id is not null and predict_private.prediction_time_open(m.tournament_id,m.scheduled_start,m.start_time_confirmed)
 and (m.score_unit='goals' and m.first_to is null or m.score_unit in ('legs','sets') and m.first_to between 1 and 99)
 and not exists(select 1 from predict_private.knockout_nodes n join predict_private.knockout_tournaments k on k.tournament_id=n.tournament_id where n.match_id=m.id and (n.is_bye or n.home_slot is null or n.away_slot is null or nullif(k.roster[n.home_slot],'') is null or nullif(k.roster[n.away_slot],'') is null))
 ),counts as(select tournament_id,count(*) as open_count,count(*) filter(where prediction_id is null) as remaining_count from eligible group by tournament_id)
 select jsonb_build_object('server_now',clock_timestamp(),'next_deadline',(select min(scheduled_start) from eligible),'tournaments',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'open_count',coalesce(c.open_count,0),'remaining_count',coalesce(c.remaining_count,0),'completed',predict_private.tournament_finished(t.id))),'[]') from public.tournaments t left join counts c on c.tournament_id=t.id where t.status in ('published','active','completed','archived'))) into result;
 return result;
end $$;
