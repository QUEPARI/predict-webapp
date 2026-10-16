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

        IF NEW.scheduled_start IS NULL
           OR NOT NEW.start_time_confirmed
           OR NEW.scheduled_start <= clock_timestamp()
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
       OR NOT v_match.start_time_confirmed
       OR v_match.round_id IS NULL
       OR v_match.status <> 'scheduled'
       OR v_match.actual_start IS NOT NULL
       OR v_match.scheduled_start IS NULL
       OR clock_timestamp() >= v_match.scheduled_start
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
AS $function$
BEGIN
    IF NEW.predictions_enabled
       AND (
           NEW.status <> 'scheduled'
           OR NEW.actual_start IS NOT NULL
           OR NEW.scheduled_start IS NULL
           OR NOT NEW.start_time_confirmed
           OR NEW.scheduled_start <= clock_timestamp()
       )
    THEN
        RAISE EXCEPTION
            'Voorspellingen moeten gesloten zijn zodra de wedstrijd begonnen is of de deadline verstreken is.';
    END IF;

    RETURN NEW;
END;
$function$
;
create trigger guard_prediction_opening_trigger before insert or update on public.matches for each row execute function public.guard_prediction_opening();
create trigger guard_started_match_predictions_trigger before insert or update on public.matches for each row execute function public.guard_started_match_predictions();
create trigger guard_prediction_submission_trigger before insert or update on public.match_predictions for each row execute function public.guard_prediction_submission();
