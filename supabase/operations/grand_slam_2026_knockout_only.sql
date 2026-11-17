begin;
-- User-requested correction for the 2026 Grand Slam; preserve a restorable audit copy.
do $$
declare tid uuid:='7c321607-2ef6-4f88-b248-dc6703fe4512';rid uuid;cutoff timestamptz;actor uuid;before_ids uuid[];after_ids uuid[];backup jsonb;previous_actor text:=current_setting('request.jwt.claim.sub',true);
begin
 perform 1 from public.tournaments where id=tid and results_archived_at is null and status in('published','active') for update;
 if not found then raise exception 'Grand Slam is unavailable for this correction';end if;
 perform 1 from predict_private.mastercaller_sources where tournament_id=tid and source_layout='generic' and not setup_pending and lease is null for update;
 if not found then raise exception 'A source check is active or the source configuration changed';end if;
 select id into rid from public.tournament_rounds where tournament_id=tid and round_order=1 and name='Groepsfase';
 if rid is null then raise exception 'Expected group round not found';end if;
 perform 1 from public.matches where tournament_id=tid order by id for update;
 if (select count(*) from public.matches where round_id=rid)<>48 or exists(select 1 from public.matches m left join predict_private.mastercaller_match_map map on map.match_id=m.id where m.round_id=rid and map.group_name is null) then raise exception 'Unexpected group fixture set';end if;
 if exists(select 1 from public.match_predictions p join public.matches m on m.id=p.match_id where m.round_id=rid) then raise exception 'Group matches have predictions; correction aborted';end if;
 if exists(select 1 from predict_private.champion_predictions where tournament_id=tid) then raise exception 'Winner predictions already exist; correction aborted';end if;
 if exists(select 1 from public.matches where tournament_id=tid and round_id<>rid and (actual_start is not null or home_score is not null or status in('live','finished'))) then raise exception 'Knockout stage already started';end if;
 select min(scheduled_start),array_agg(id order by id) into cutoff,before_ids from public.matches where tournament_id=tid and round_id<>rid;
 if cutoff is null or cutoff<=clock_timestamp() or cardinality(before_ids)<>15 then raise exception 'No safe future knockout deadline';end if;
 select a.actor into actor from predict_private.tournament_management_audit a join public.user_roles r on r.user_id=a.actor where a.tournament_id=tid and a.action='source_publish' and r.role in('admin','super_admin') order by a.created_at desc limit 1;
 if actor is null then raise exception 'Publishing administrator unavailable';end if;
 select jsonb_build_object('matches',(select jsonb_agg(to_jsonb(m)) from public.matches m where round_id=rid),'mapping',(select jsonb_agg(to_jsonb(m)) from predict_private.mastercaller_match_map m join public.matches x on x.id=m.match_id where x.round_id=rid),'round',(select to_jsonb(r) from public.tournament_rounds r where id=rid),'scoring',(select jsonb_agg(to_jsonb(r)) from public.round_scoring r where round_id=rid),'old_start',(select starts_at from public.tournaments where id=tid),'old_champion',(select to_jsonb(c) from predict_private.champion_settings c where tournament_id=tid)) into backup;
 insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details) values(tid,actor,'exclude_group_stage','Op verzoek van eigenaar: onvoorspelde groepsfase verwijderen; winnaar voorspellen tot eerste knock-outwedstrijd',backup||jsonb_build_object('deadline',cutoff));
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform predict_private.mc_enter(tid);
 insert into predict_private.tournament_mutation_permits(tournament_id,transaction_id,actor) values(tid,txid_current(),actor);
 update predict_private.mastercaller_sources set setup_snapshot=jsonb_set(setup_snapshot,'{excluded_rounds}','[1]'::jsonb),report=jsonb_build_object('checked_at',last_success,'reason','Groepsfase uitgesloten van dit voorspeltoernooi; knock-outwedstrijden blijven gekoppeld aan Mastercaller.') where tournament_id=tid;
 delete from public.matches where round_id=rid;
 delete from public.round_scoring where round_id=rid;
 delete from public.tournament_rounds where id=rid;
 update public.tournaments set starts_at=cutoff where id=tid;
 update predict_private.champion_settings set enabled=true,deadline=cutoff where tournament_id=tid;
 if not found then raise exception 'Winner settings missing';end if;
 delete from predict_private.tournament_mutation_permits where tournament_id=tid and transaction_id=txid_current();
 perform predict_private.mc_exit(tid);
 perform set_config('request.jwt.claim.sub',coalesce(previous_actor,''),true);
 select array_agg(id order by id) into after_ids from public.matches where tournament_id=tid;
 if before_ids is distinct from after_ids then raise exception 'Knockout fixture IDs changed';end if;
end $$;

commit;
