-- Admin-only, audited points correction, including started/source-owned games.
-- Leaderboards calculate from round_scoring live; frozen standings use point deltas
-- so archived membership, names, bonus points and archival dates stay intact.
create function predict_private.reprice_standings(p_rows jsonb,p_before jsonb,p_after jsonb)
returns jsonb language sql set search_path='' as $$
 with adjusted as (
  select r, (r->>'earned_points')::bigint
   - coalesce((select (x->>'earned_points')::bigint from jsonb_array_elements(p_before)x where x->>'user_id'=r->>'user_id'),0)
   + coalesce((select (x->>'earned_points')::bigint from jsonb_array_elements(p_after)x where x->>'user_id'=r->>'user_id'),0) points
  from jsonb_array_elements(p_rows)r
 ), ranked as (
  select r||jsonb_build_object('earned_points',points,'rank_position',rank() over(order by points desc,(r->>'correct_winners')::bigint desc)) row
  from adjusted
 ) select coalesce(jsonb_agg(row order by (row->>'rank_position')::bigint,row->>'display_name',row->>'user_id'),'[]') from ranked
$$;
revoke all on function predict_private.reprice_standings(jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;

create function predict_private.save_round_scoring(p_tournament uuid,p_rules jsonb,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();before_rules jsonb;after_rules jsonb;before_points jsonb;after_points jsonb;item jsonb;n integer;
begin
 perform 1 from public.tournaments where id=p_tournament for update;
 if not found then raise exception 'Toernooi niet gevonden';end if;
 -- Match writers and automatic finalization use the same tournament/match locks.
 perform 1 from public.matches where tournament_id=p_tournament order by id for update;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'winner_points',s.winner_points,'exact_points',s.exact_score_points) order by r.round_order),'[]')
 into before_rules from public.tournament_rounds r left join public.round_scoring s on s.round_id=r.id and s.tournament_id=r.tournament_id where r.tournament_id=p_tournament;
 if p_expected is distinct from before_rules then raise exception 'De punten zijn intussen gewijzigd. Heropen het toernooi en probeer opnieuw.';end if;
 if jsonb_typeof(p_rules) is distinct from 'array' then raise exception 'Ongeldige rondepunten';end if;
 if jsonb_array_length(p_rules)=0 or jsonb_array_length(p_rules)<>jsonb_array_length(before_rules) then raise exception 'Vul de punten voor alle rondes in';end if;
 if exists(select 1 from jsonb_array_elements(p_rules)x where jsonb_typeof(x) is distinct from 'object'
   or coalesce(x->>'winner_points','')!~'^[0-9]{1,4}$' or coalesce(x->>'exact_points','')!~'^[0-9]{1,4}$'
   or not exists(select 1 from public.tournament_rounds r where r.tournament_id=p_tournament and r.id::text=x->>'id'))
 then raise exception 'Vul per ronde hele punten tussen 0 en 1000 in';end if;
 if exists(select 1 from jsonb_array_elements(p_rules)x where (x->>'winner_points')::int>1000 or (x->>'exact_points')::int>1000)
 or (select count(distinct x->>'id') from jsonb_array_elements(p_rules)x)<>jsonb_array_length(p_rules)
 then raise exception 'Ongeldige of dubbele rondepunten';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into before_points from predict_private.snapshot_match_rows(p_tournament,null,null)x;
 insert into predict_private.tournament_mutation_permits values(p_tournament,txid_current(),actor);
 perform predict_private.mc_enter(p_tournament);
 for item in select * from jsonb_array_elements(p_rules) loop
  insert into public.round_scoring(tournament_id,round_id,winner_points,exact_score_points)
  values(p_tournament,(item->>'id')::uuid,(item->>'winner_points')::integer,(item->>'exact_points')::integer)
  on conflict(round_id) do update set winner_points=excluded.winner_points,exact_score_points=excluded.exact_score_points;
 end loop;
 perform predict_private.mc_exit(p_tournament);
 delete from predict_private.tournament_mutation_permits where tournament_id=p_tournament and transaction_id=txid_current();
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into after_points from predict_private.snapshot_match_rows(p_tournament,null,null)x;
 update predict_private.tournament_final_snapshots set standings=predict_private.reprice_standings(standings,before_points,after_points) where tournament_id=p_tournament;
 update predict_private.pool_final_snapshots set standings=predict_private.reprice_standings(standings,before_points,after_points) where tournament_id=p_tournament;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'winner_points',s.winner_points,'exact_points',s.exact_score_points) order by r.round_order),'[]') into after_rules
 from public.tournament_rounds r join public.round_scoring s on s.round_id=r.id and s.tournament_id=r.tournament_id where r.tournament_id=p_tournament;
 select count(*) into n from public.match_predictions mp join public.matches m on m.id=mp.match_id where m.tournament_id=p_tournament and m.status='finished';
 insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details)
 values(p_tournament,actor,'round_scoring_recalculated','Punten per ronde aangepast en herberekend',jsonb_build_object('before',before_rules,'after',after_rules,'scored_predictions',n));
 return jsonb_build_object('rules',after_rules,'scored_predictions',n);
end $$;
revoke all on function predict_private.save_round_scoring(uuid,jsonb,jsonb) from public,anon,service_role;
grant execute on function predict_private.save_round_scoring(uuid,jsonb,jsonb) to authenticated;
create function public.admin_save_round_scoring(p_tournament uuid,p_rules jsonb,p_expected jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select predict_private.save_round_scoring(p_tournament,p_rules,p_expected)
$$;
revoke all on function public.admin_save_round_scoring(uuid,jsonb,jsonb) from public,anon,service_role;
grant execute on function public.admin_save_round_scoring(uuid,jsonb,jsonb) to authenticated;
