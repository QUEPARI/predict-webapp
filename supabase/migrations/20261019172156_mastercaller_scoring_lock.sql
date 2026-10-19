-- Lock source-owned scoring at automatic publication, just like manual publication.
create or replace function predict_private.create_mastercaller_game(p_snapshot jsonb,p_name text,p_winner integer,p_exact integer,p_mode text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();tid uuid;sport uuid;roster text[];rules jsonb;start_at timestamptz;end_at timestamptz;title text;
begin
 if p_winner is null or p_exact is null or p_winner not between 0 and 1000 or p_exact not between 0 and 1000 then raise exception 'Ongeldige puntentelling';end if;
 if jsonb_typeof(p_snapshot->'rounds') is distinct from 'array' or jsonb_typeof(p_snapshot->'roster') is distinct from 'array' then raise exception 'Bronschema ontbreekt';end if;
 if coalesce(p_snapshot->>'start_date','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' or coalesce(p_snapshot->>'end_date','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'Bronperiode ontbreekt';end if;
 title:=coalesce(nullif(trim(p_name),''),trim(p_snapshot->>'title')||' '||split_part(predict_private.mastercaller_url(p_snapshot->>'url'),'/',6));
 select array_agg(value order by ord) into roster from jsonb_array_elements_text(p_snapshot->'roster') with ordinality x(value,ord);
 if cardinality(roster) not in(2,4,8,16,32,64,128) then raise exception 'Onbekend knock-outformat';end if;
 select jsonb_agg(jsonb_build_object('name',x->>'name','unit',x->>'unit','first_to',(x->>'first_to')::integer,'winner_points',p_winner,'exact_points',p_exact) order by (x->>'order')::integer) into rules from jsonb_array_elements(p_snapshot->'rounds')x;
 start_at:=(p_snapshot->>'start_date')::date::timestamp at time zone 'Europe/Amsterdam';
 end_at:=((p_snapshot->>'end_date')::date+1)::timestamp at time zone 'Europe/Amsterdam';
 select id into sport from public.sports where slug='darts';
 tid:=predict_private.create_knockout_game(title,sport,'players',roster,start_at,rules,p_mode,end_at,'draft');
 perform predict_private.set_score_source(tid,'mastercaller_test',p_snapshot->>'url');
 update predict_private.mastercaller_sources set automatic_setup=true,last_attempt=now(),last_success=now(),report=jsonb_build_object('checked_at',now(),'applied',0,'received',jsonb_array_length(p_snapshot->'records')) where tournament_id=tid;
 -- Source-owned games can be published with TBA times. No prediction opens until
 -- an actual source timestamp exists; manual publication checks stay unchanged.
 update public.tournament_scoring set is_locked=true where tournament_id=tid;
 update public.tournaments set status='published' where id=tid;
 perform predict_private.sync_mastercaller_schema(tid,p_snapshot);
 return tid;
end $$;
