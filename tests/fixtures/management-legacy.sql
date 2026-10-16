CREATE OR REPLACE FUNCTION public.get_tournament_leaderboard(p_tournament_id uuid, p_pool_id uuid DEFAULT NULL::uuid, p_round_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(user_id uuid, display_name text, earned_points bigint, correct_winners bigint, exact_scores bigint, scored_predictions bigint, rank_position bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_caller uuid := auth.uid();
BEGIN
 IF v_caller IS NULL THEN
   RAISE EXCEPTION 'Login vereist' USING ERRCODE = '42501';
 END IF;
 IF p_tournament_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.tournaments t WHERE t.id = p_tournament_id
 ) THEN
   RAISE EXCEPTION 'Toernooi niet gevonden';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.tournament_entries e
   WHERE e.tournament_id = p_tournament_id AND e.user_id = v_caller
 ) AND NOT EXISTS (
   SELECT 1 FROM public.user_roles u
   WHERE u.user_id = v_caller AND u.role IN ('admin','super_admin')
 ) THEN
   RAISE EXCEPTION 'Geen toegang tot dit toernooiklassement'
     USING ERRCODE = '42501';
 END IF;
 IF p_pool_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.pools p
   WHERE p.id=p_pool_id AND p.tournament_id=p_tournament_id
 ) THEN
   RAISE EXCEPTION 'Poule hoort niet bij toernooi';
 END IF;
 IF p_pool_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.pool_members pm
   WHERE pm.pool_id=p_pool_id AND pm.user_id=v_caller
 ) AND NOT EXISTS (
   SELECT 1 FROM public.user_roles u
   WHERE u.user_id=v_caller AND u.role IN ('admin','super_admin')
 ) THEN
   RAISE EXCEPTION 'Geen toegang tot dit pouleklassement'
     USING ERRCODE = '42501';
 END IF;
 IF p_round_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.tournament_rounds tr
   WHERE tr.id=p_round_id AND tr.tournament_id=p_tournament_id
 ) THEN
   RAISE EXCEPTION 'Ronde hoort niet bij toernooi';
 END IF;
 RETURN QUERY
 WITH eligible AS (
   SELECT e.user_id
   FROM public.tournament_entries e
   WHERE e.tournament_id=p_tournament_id
     AND (p_pool_id IS NULL OR EXISTS(
       SELECT 1 FROM public.pool_members pm
       WHERE pm.pool_id=p_pool_id AND pm.user_id=e.user_id
     ))
 ),
 scores AS (
   SELECT e.user_id,
     COALESCE(SUM(
       CASE WHEN m.id IS NULL THEN 0
         WHEN ts.scoring_mode='replacement' THEN
           CASE
             WHEN mp.home_score=m.home_score AND mp.away_score=m.away_score
               THEN rs.exact_score_points
             WHEN sign(mp.home_score-mp.away_score)=sign(m.home_score-m.away_score)
               THEN rs.winner_points
             ELSE 0 END
         WHEN ts.scoring_mode='additive' THEN
           (CASE WHEN sign(mp.home_score-mp.away_score)=sign(m.home_score-m.away_score)
              THEN rs.winner_points ELSE 0 END)
           + (CASE WHEN mp.home_score=m.home_score AND mp.away_score=m.away_score
              THEN rs.exact_score_points ELSE 0 END)
         ELSE 0 END
     ),0)::bigint AS pts,
     COUNT(m.id) FILTER(
       WHERE sign(mp.home_score-mp.away_score)=sign(m.home_score-m.away_score)
     )::bigint AS winners,
     COUNT(m.id) FILTER(
       WHERE mp.home_score=m.home_score AND mp.away_score=m.away_score
     )::bigint AS exacts,
     COUNT(m.id)::bigint AS counted
   FROM eligible e
   LEFT JOIN public.match_predictions mp ON mp.user_id=e.user_id
     AND EXISTS (
       SELECT 1 FROM public.matches mx
       WHERE mx.id=mp.match_id AND mx.tournament_id=p_tournament_id
       AND (p_round_id IS NULL OR mx.round_id=p_round_id)
     )
   LEFT JOIN public.matches m ON m.id=mp.match_id
     AND m.tournament_id=p_tournament_id
     AND m.status='finished' AND m.home_score IS NOT NULL
     AND m.away_score IS NOT NULL
     AND (p_round_id IS NULL OR m.round_id=p_round_id)
   LEFT JOIN public.round_scoring rs ON rs.round_id=m.round_id
     AND rs.tournament_id=p_tournament_id
   LEFT JOIN public.tournament_scoring ts ON ts.tournament_id=p_tournament_id
   GROUP BY e.user_id
 )
 SELECT s.user_id,
   COALESCE(NULLIF(btrim(p.display_name),''), NULLIF(btrim(p.username),''),'Gebruiker')::text,
   s.pts,s.winners,s.exacts,s.counted,
   RANK() OVER (ORDER BY s.pts DESC,s.winners DESC)::bigint
 FROM scores s LEFT JOIN public.profiles p ON p.id=s.user_id
 ORDER BY s.pts DESC,s.winners DESC, COALESCE(NULLIF(btrim(p.display_name),''), NULLIF(btrim(p.username),''),'Gebruiker') ASC;
END;
$function$

;
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
CREATE OR REPLACE FUNCTION public.log_match_prediction_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_changed_at TIMESTAMPTZ := clock_timestamp();
BEGIN
    IF TG_OP = 'INSERT' THEN

        INSERT INTO public.prediction_audit_log (
            prediction_id,
            match_id,
            user_id,
            action,
            new_home_score,
            new_away_score,
            changed_at,
            database_actor
        )
        VALUES (
            NEW.id,
            NEW.match_id,
            NEW.user_id,
            'insert',
            NEW.home_score,
            NEW.away_score,
            v_changed_at,
            current_user
        );

        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN

        -- Alleen inhoudelijke scorewijzigingen loggen.
        IF NEW.home_score IS DISTINCT FROM OLD.home_score
           OR NEW.away_score IS DISTINCT FROM OLD.away_score
        THEN
            INSERT INTO public.prediction_audit_log (
                prediction_id,
                match_id,
                user_id,
                action,
                old_home_score,
                old_away_score,
                new_home_score,
                new_away_score,
                changed_at,
                database_actor
            )
            VALUES (
                NEW.id,
                NEW.match_id,
                NEW.user_id,
                'update',
                OLD.home_score,
                OLD.away_score,
                NEW.home_score,
                NEW.away_score,
                v_changed_at,
                current_user
            );
        END IF;

        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN

        INSERT INTO public.prediction_audit_log (
            prediction_id,
            match_id,
            user_id,
            action,
            old_home_score,
            old_away_score,
            changed_at,
            database_actor
        )
        VALUES (
            OLD.id,
            OLD.match_id,
            OLD.user_id,
            'delete',
            OLD.home_score,
            OLD.away_score,
            v_changed_at,
            current_user
        );

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.prevent_match_audit_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    RAISE EXCEPTION
        'Auditregistraties mogen niet worden gewijzigd.';
END;
$function$

;
CREATE OR REPLACE FUNCTION public.prevent_scoring_audit_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    RAISE EXCEPTION
        'Puntenaudit mag niet worden gewijzigd of verwijderd.';
END;
$function$

;
