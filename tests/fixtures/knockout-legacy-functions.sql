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

    IF v_tournament.status <> 'draft' THEN
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
$function$;

CREATE OR REPLACE FUNCTION public.admin_record_match_result(p_match_id uuid, p_home_score integer, p_away_score integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_admin_id UUID := auth.uid();
    v_match public.matches%ROWTYPE;
    v_recorded_at TIMESTAMPTZ;
BEGIN
    IF v_admin_id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.user_roles
        WHERE user_id = v_admin_id
          AND role IN ('admin', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'Geen beheerdersrechten'
            USING ERRCODE = '42501';
    END IF;

    SELECT *
    INTO v_match
    FROM public.matches
    WHERE id = p_match_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Wedstrijd niet gevonden';
    END IF;

    v_recorded_at := clock_timestamp();

    IF p_home_score IS NULL
       OR p_away_score IS NULL
       OR p_home_score NOT BETWEEN 0 AND 99
       OR p_away_score NOT BETWEEN 0 AND 99
    THEN
        RAISE EXCEPTION 'Ongeldige uitslag';
    END IF;

    IF v_match.status NOT IN ('scheduled', 'live')
       OR v_match.home_score IS NOT NULL
       OR v_match.away_score IS NOT NULL
    THEN
        RAISE EXCEPTION
            'Wedstrijd is niet beschikbaar voor eerste uitslagregistratie';
    END IF;

    -- Een wedstrijd kan eerder dan gepland begonnen zijn.
    -- In dat geval is de geregistreerde werkelijke
    -- start voldoende om uitslagregistratie toe te staan.
    IF NOT (
        (
            v_match.status = 'live'
            AND v_match.actual_start IS NOT NULL
            AND v_match.actual_start <= v_recorded_at
        )
        OR (
            v_match.scheduled_start IS NOT NULL
            AND v_match.scheduled_start <= v_recorded_at
        )
    ) THEN
        RAISE EXCEPTION
            'De wedstrijdstart is nog niet vastgesteld of ligt in de toekomst';
    END IF;

    IF v_match.round_id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.tournament_rounds r
        WHERE r.id = v_match.round_id
          AND r.tournament_id = v_match.tournament_id
    ) THEN
        RAISE EXCEPTION 'Geldige wedstrijdronde ontbreekt';
    END IF;

    IF v_match.score_unit IN ('legs', 'sets') THEN
        IF v_match.first_to IS NULL
           OR v_match.first_to NOT BETWEEN 1 AND 99
        THEN
            RAISE EXCEPTION 'Wedstrijdformaat ontbreekt';
        END IF;

        IF NOT (
            (
                p_home_score = v_match.first_to
                AND p_away_score < v_match.first_to
            )
            OR (
                p_away_score = v_match.first_to
                AND p_home_score < v_match.first_to
            )
        ) THEN
            RAISE EXCEPTION
                'Uitslag past niet bij het wedstrijdformaat';
        END IF;

    ELSIF v_match.score_unit = 'goals' THEN
        IF v_match.first_to IS NOT NULL THEN
            RAISE EXCEPTION 'Ongeldig voetbalformaat';
        END IF;
    ELSE
        RAISE EXCEPTION 'Onbekend wedstrijdformaat';
    END IF;

    UPDATE public.matches
    SET home_score = p_home_score,
        away_score = p_away_score,
        status = 'finished',
        predictions_enabled = false,
        updated_at = now()
    WHERE id = p_match_id;

    INSERT INTO public.match_audit_log (
        match_id,
        changed_by,
        action,
        old_values,
        new_values
    )
    VALUES (
        p_match_id,
        v_admin_id,
        'manual_result_entry',
        jsonb_build_object(
            'status', v_match.status,
            'home_score', v_match.home_score,
            'away_score', v_match.away_score,
            'actual_start', v_match.actual_start,
            'predictions_enabled',
                v_match.predictions_enabled
        ),
        jsonb_build_object(
            'status', 'finished',
            'home_score', p_home_score,
            'away_score', p_away_score,
            'result_source', 'manual_admin',
            'recorded_at', v_recorded_at,
            'predictions_enabled', false
        )
    );

    RETURN true;
END;
$function$;

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
       OR v_match.start_time_confirmed IS DISTINCT FROM TRUE
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
    IF v_match.scheduled_start IS NULL
       OR v_checked_at >= v_match.scheduled_start
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