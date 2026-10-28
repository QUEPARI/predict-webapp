-- Ensure every new manual/source creation starts as a concept too.
alter function predict_private.create_knockout_game(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text) rename to create_knockout_game_before_concepts;
revoke all on function predict_private.create_knockout_game_before_concepts(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text) from public,anon,authenticated,service_role;
create function predict_private.create_knockout_game(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text,p_end timestamptz,p_status text)
returns uuid language plpgsql security definer set search_path='' as $$begin
 perform predict_private.ko_admin();return predict_private.create_knockout_game_before_concepts(p_name,p_sport,p_kind,p_roster,p_start,p_rules,p_mode,p_end,'draft');
end $$;
revoke all on function predict_private.create_knockout_game(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text) from public,anon,service_role;
grant execute on function predict_private.create_knockout_game(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text) to authenticated;
do $$declare definition text;begin
 select pg_get_functiondef('predict_private.create_mastercaller_game(jsonb,text,integer,integer,text)'::regprocedure) into definition;
 execute replace(definition,'update public.tournaments set status=''published'' where id=tid;','-- Publication is an explicit administrator choice; keep this concept private.');
 -- The last calendar day is inclusive both for midnight-exclusive legacy ends and 23:59 ends.
 select pg_get_functiondef('predict_private.finish_mastercaller_scores(uuid,uuid,jsonb,text)'::regprocedure) into definition;
 execute replace(definition,'((t.ends_at at time zone ''Europe/Amsterdam'')::date-1)','((t.ends_at-interval ''1 microsecond'') at time zone ''Europe/Amsterdam'')::date');
end $$;
