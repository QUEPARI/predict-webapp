alter table public.tournaments add column results_archived_at timestamptz;
create index tournaments_unfinalized_end_idx on public.tournaments(ends_at) where results_archived_at is null;
create index matches_missing_result_idx on public.matches(tournament_id,scheduled_start) where status in('scheduled','live') and home_score is null and away_score is null;
create table predict_private.tournament_final_snapshots(
 tournament_id uuid primary key references public.tournaments(id),name text not null,starts_at timestamptz,ends_at timestamptz,
 archived_at timestamptz not null,members uuid[] not null,standings jsonb not null
);
create table predict_private.pool_final_snapshots(
 pool_id uuid primary key,tournament_id uuid not null references predict_private.tournament_final_snapshots(tournament_id),
 name text not null,members uuid[] not null,standings jsonb not null
);
create index pool_final_tournament_idx on predict_private.pool_final_snapshots(tournament_id);
alter table predict_private.tournament_final_snapshots enable row level security;
alter table predict_private.pool_final_snapshots enable row level security;
revoke all on predict_private.tournament_final_snapshots,predict_private.pool_final_snapshots from public,anon,authenticated,service_role;

create function predict_private.final_snapshot_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare tid uuid;
begin
 if TG_TABLE_NAME='tournaments' then tid:=old.id;else tid:=case when TG_OP='DELETE' then old.tournament_id else new.tournament_id end;end if;
 if exists(select 1 from predict_private.tournament_final_snapshots where tournament_id=tid) then
  raise exception 'Dit toernooi heeft een definitief eindklassement en kan niet meer worden gewijzigd' using errcode='42501';
 end if;
 if TG_OP='DELETE' then return old;else return new;end if;
end $$;
revoke all on function predict_private.final_snapshot_guard() from public,anon,authenticated,service_role;
create trigger final_snapshot_guard before update or delete on public.tournaments for each row execute function predict_private.final_snapshot_guard();
create trigger final_snapshot_guard before insert or update or delete on public.matches for each row execute function predict_private.final_snapshot_guard();

CREATE OR REPLACE FUNCTION predict_private.snapshot_match_rows(p_tournament_id uuid, p_pool_id uuid DEFAULT NULL::uuid, p_round_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(user_id uuid, display_name text, earned_points bigint, correct_winners bigint, exact_scores bigint, scored_predictions bigint, rank_position bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
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
$function$;
revoke all on function predict_private.snapshot_match_rows(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create or replace function predict_private.final_rows(p_tournament uuid,p_pool uuid) returns jsonb
language sql security definer set search_path='' as $$
 with rows as(
 select b.*,case when cp.choice=predict_private.champion_winner(p_tournament) then coalesce(cs.points,0) else 0 end as bonus
 from predict_private.snapshot_match_rows(p_tournament,p_pool,null)b
 left join predict_private.champion_predictions cp on cp.tournament_id=p_tournament and cp.user_id=b.user_id
 left join predict_private.champion_settings cs on cs.tournament_id=p_tournament),
 ranked as(select user_id,display_name,(earned_points+bonus)::bigint earned_points,correct_winners,exact_scores,scored_predictions,
 rank() over(order by earned_points+bonus desc,correct_winners desc)::bigint rank_position from rows)
 select coalesce(jsonb_agg(to_jsonb(r) order by rank_position,display_name,user_id),'[]') from ranked r
$$;
revoke all on function predict_private.final_rows(uuid,uuid) from public,anon,authenticated,service_role;

create function predict_private.finalization_ready(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tournaments where id=p_id and ends_at<=clock_timestamp())
 and exists(select 1 from public.matches m where m.tournament_id=p_id and not exists(select 1 from predict_private.knockout_nodes n where n.match_id=m.id and n.is_bye))
 and not exists(select 1 from public.matches m where m.tournament_id=p_id and not exists(select 1 from predict_private.knockout_nodes n where n.match_id=m.id and n.is_bye)
 and (m.status not in('finished','cancelled') or m.status='finished' and (m.home_score is null or m.away_score is null)))
 and not exists(select 1 from predict_private.champion_settings cs where cs.tournament_id=p_id and cs.points>0 and predict_private.champion_winner(p_id) is null)
$$;
revoke all on function predict_private.finalization_ready(uuid) from public,anon,authenticated,service_role;

create function predict_private.freeze_tournament(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare t public.tournaments%rowtype;at_time timestamptz:=clock_timestamp();global_rows jsonb;pool record;
begin
 select * into t from public.tournaments where id=p_id for update;
 if not found or t.results_archived_at is not null then return false;end if;
 if t.status='draft' or t.ends_at is null or t.ends_at>at_time-interval '72 hours' then return false;end if;
 perform 1 from public.matches where tournament_id=p_id order by id for update;
 perform 1 from public.pools where tournament_id=p_id order by id for update;
 if not predict_private.finalization_ready(p_id) then return false;end if;
 global_rows:=predict_private.final_rows(p_id,null);
 update public.tournaments set status='archived',admin_archived=true,results_archived_at=at_time where id=p_id;
 insert into predict_private.tournament_final_snapshots values(p_id,t.name,t.starts_at,t.ends_at,at_time,
  coalesce((select array_agg(user_id order by user_id) from public.tournament_entries where tournament_id=p_id),'{}'),global_rows);
 for pool in select * from public.pools where tournament_id=p_id order by id loop
  insert into predict_private.pool_final_snapshots values(pool.id,p_id,pool.name,
   coalesce((select array_agg(user_id order by user_id) from public.pool_members where pool_id=pool.id),'{}'),predict_private.final_rows(p_id,pool.id));
 end loop;
 return true;
end $$;
revoke all on function predict_private.freeze_tournament(uuid) from public,anon,authenticated,service_role;
create or replace function predict_private.archive_expired_games() returns integer language plpgsql security definer set search_path='' as $$
declare t record;n integer:=0;
begin
 for t in select id from public.tournaments where results_archived_at is null and status<>'draft' and ends_at<=clock_timestamp()-interval '72 hours' order by id loop
  if predict_private.freeze_tournament(t.id) then n:=n+1;end if;
 end loop;
 return n;
end $$;
revoke all on function predict_private.archive_expired_games() from public,anon,authenticated,service_role;

create function predict_private.active_catalog() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Login vereist' using errcode='42501';end if;
 return jsonb_build_object('tournaments',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'status',t.status,'starts_at',t.starts_at,'ends_at',t.ends_at,
  'joined',exists(select 1 from public.tournament_entries e where e.tournament_id=t.id and e.user_id=auth.uid()))),'[]')
  from public.tournaments t where t.status<>'draft' and t.results_archived_at is null),
  'archive_count',(select count(*) from predict_private.tournament_final_snapshots where auth.uid()=any(members)));
end $$;
create function predict_private.archive_catalog(p_admin boolean) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Login vereist' using errcode='42501';end if;
 if p_admin then perform predict_private.ko_admin();end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',tournament_id,'name',name,'starts_at',starts_at,'ends_at',ends_at,'archived_at',archived_at) order by ends_at desc),'[]')
  from predict_private.tournament_final_snapshots where p_admin or auth.uid()=any(members));
end $$;
create function predict_private.archive_detail(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare snap predict_private.tournament_final_snapshots%rowtype;admin boolean;
begin
 if auth.uid() is null then raise exception 'Login vereist' using errcode='42501';end if;
 select * into snap from predict_private.tournament_final_snapshots where tournament_id=p_id;
 if not found then
  if not exists(select 1 from public.tournaments where id=p_id and (status<>'draft' or exists(select 1 from public.user_roles where user_id=auth.uid() and role in('admin','super_admin')))) then raise exception 'Toernooi niet beschikbaar' using errcode='42501';end if;
  return jsonb_build_object('archived',false);
 end if;
 admin:=exists(select 1 from public.user_roles where user_id=auth.uid() and role in('admin','super_admin'));
 if not admin and not auth.uid()=any(snap.members) then raise exception 'Geen toegang tot het eindklassement' using errcode='42501';end if;
 return jsonb_build_object('archived',true,'id',p_id,'name',snap.name,'archived_at',snap.archived_at,'standings',snap.standings,
  'pools',(select coalesce(jsonb_agg(jsonb_build_object('id',pool_id,'name',name,'standings',standings) order by name),'[]')
   from predict_private.pool_final_snapshots where tournament_id=p_id and (admin or auth.uid()=any(members))));
end $$;
revoke all on function predict_private.active_catalog(),predict_private.archive_catalog(boolean),predict_private.archive_detail(uuid) from public,anon,service_role;
grant execute on function predict_private.active_catalog(),predict_private.archive_catalog(boolean),predict_private.archive_detail(uuid) to authenticated;
create function public.get_active_tournament_catalog() returns jsonb language sql security invoker set search_path='' as $$select predict_private.active_catalog()$$;
create function public.get_tournament_archive_catalog(p_admin boolean default false) returns jsonb language sql security invoker set search_path='' as $$select predict_private.archive_catalog(p_admin)$$;
create function public.get_tournament_archive(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select predict_private.archive_detail(p_id)$$;
revoke all on function public.get_active_tournament_catalog(),public.get_tournament_archive_catalog(boolean),public.get_tournament_archive(uuid) from public,anon;
grant execute on function public.get_active_tournament_catalog(),public.get_tournament_archive_catalog(boolean),public.get_tournament_archive(uuid) to authenticated;

create function predict_private.pending_result(m public.matches) returns boolean language sql stable set search_path='' as $$
 select m.status in('scheduled','live') and m.home_score is null and m.away_score is null and coalesce(m.actual_start,m.scheduled_start)<=clock_timestamp()
  and not exists(select 1 from predict_private.knockout_nodes n where n.match_id=m.id and (n.is_bye or n.home_slot is null or n.away_slot is null))
$$;
revoke all on function predict_private.pending_result(public.matches) from public,anon,authenticated,service_role;
create function predict_private.result_alert() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform predict_private.ko_admin();
 return jsonb_build_object('count',(select count(*) from public.matches m join public.tournaments t on t.id=m.tournament_id
  where t.results_archived_at is null and t.status in('published','active','completed') and m.status in('scheduled','live') and m.home_score is null and m.away_score is null and predict_private.pending_result(m)),
  'next_start',(select min(coalesce(m.actual_start,m.scheduled_start)) from public.matches m join public.tournaments t on t.id=m.tournament_id
   where t.results_archived_at is null and t.status in('published','active','completed') and m.status in('scheduled','live') and m.home_score is null and m.away_score is null and coalesce(m.actual_start,m.scheduled_start)>clock_timestamp()),
  'blocked_archives',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name)),'[]') from public.tournaments t
   where results_archived_at is null and status<>'draft' and ends_at<=clock_timestamp()-interval '72 hours' and not predict_private.finalization_ready(t.id)),
  'server_now',clock_timestamp());
end $$;
create function predict_private.admin_match_rows(p_tournament uuid,p_pending boolean) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(jsonb_build_object('match_id',m.id,'tournament_id',t.id,'tournament_name',t.name,'round_id',r.id,'round_name',r.name,
  'home_name',m.home_name,'away_name',m.away_name,'scheduled_start',m.scheduled_start,'actual_start',m.actual_start,'match_status',m.status,
  'score_unit',m.score_unit,'first_to',m.first_to,'start_time_confirmed',m.start_time_confirmed,'predictions_enabled',m.predictions_enabled,
  'needs_review',m.needs_review,'review_reason',m.review_reason,'home_score',m.home_score,'away_score',m.away_score,
  'source_locked',exists(select 1 from predict_private.mastercaller_sources s where s.tournament_id=t.id),'source_start',t.starts_at,'tournament_status',t.status,'round_order',r.round_order,'home_slot',n.home_slot,'away_slot',n.away_slot)
  order by coalesce(m.actual_start,m.scheduled_start),m.id),'[]') from public.matches m join public.tournaments t on t.id=m.tournament_id
  left join public.tournament_rounds r on r.id=m.round_id left join predict_private.knockout_nodes n on n.match_id=m.id where t.results_archived_at is null and (p_tournament is not null and t.id=p_tournament or p_tournament is null and p_pending)
  and (not p_pending or t.status in('published','active','completed') and m.status in('scheduled','live') and m.home_score is null and m.away_score is null and predict_private.pending_result(m)));
end $$;
revoke all on function predict_private.result_alert(),predict_private.admin_match_rows(uuid,boolean) from public,anon,service_role;
grant execute on function predict_private.result_alert(),predict_private.admin_match_rows(uuid,boolean) to authenticated;
create function public.admin_result_alert() returns jsonb language sql security invoker set search_path='' as $$select predict_private.result_alert()$$;
create function public.admin_match_overview(p_tournament uuid default null,p_pending boolean default false) returns jsonb language sql security invoker set search_path='' as $$select predict_private.admin_match_rows(p_tournament,p_pending)$$;
revoke all on function public.admin_result_alert(),public.admin_match_overview(uuid,boolean) from public,anon;
grant execute on function public.admin_result_alert(),public.admin_match_overview(uuid,boolean) to authenticated;

alter function predict_private.combined_leaderboard(uuid,uuid,uuid) rename to live_combined_leaderboard;
revoke all on function predict_private.live_combined_leaderboard(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create function predict_private.combined_leaderboard(p_tournament_id uuid,p_pool_id uuid,p_round_id uuid)
returns table(user_id uuid,display_name text,earned_points bigint,correct_winners bigint,exact_scores bigint,scored_predictions bigint,rank_position bigint)
language plpgsql stable security definer set search_path='' as $$
declare data jsonb;rows jsonb;
begin
 if exists(select 1 from predict_private.tournament_final_snapshots where tournament_id=p_tournament_id) then
  data:=predict_private.archive_detail(p_tournament_id);
  if p_round_id is not null then raise exception 'Het archief toont uitsluitend het eindklassement';end if;
  if p_pool_id is null then rows:=data->'standings';else
   select x->'standings' into rows from jsonb_array_elements(data->'pools')x where x->>'id'=p_pool_id::text;
   if rows is null then raise exception 'Geen toegang tot dit pouleklassement' using errcode='42501';end if;
  end if;
  return query select r.* from jsonb_to_recordset(rows)r(user_id uuid,display_name text,earned_points bigint,correct_winners bigint,exact_scores bigint,scored_predictions bigint,rank_position bigint);
 else return query select * from predict_private.live_combined_leaderboard(p_tournament_id,p_pool_id,p_round_id);end if;
end $$;
revoke all on function predict_private.combined_leaderboard(uuid,uuid,uuid) from public,anon;
grant execute on function predict_private.combined_leaderboard(uuid,uuid,uuid) to authenticated;

CREATE OR REPLACE FUNCTION predict_private.tournament_prediction_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 select jsonb_build_object('server_now',clock_timestamp(),'next_deadline',(select min(scheduled_start) from eligible),'tournaments',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'open_count',coalesce(c.open_count,0),'remaining_count',coalesce(c.remaining_count,0),'completed',predict_private.tournament_finished(t.id))),'[]') from public.tournaments t left join counts c on c.tournament_id=t.id where t.results_archived_at is null and t.status in ('published','active','completed','archived'))) into result;
 return result;
end $function$;
CREATE OR REPLACE FUNCTION predict_private.management_catalog_internal()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'status',t.status,'start',t.starts_at,'end',t.ends_at,'knockout',k.tournament_id is not null,'counts',predict_private.tournament_counts(t.id),'roster',coalesce(k.roster,array(select distinct x from public.matches m cross join lateral unnest(array[m.home_name,m.away_name])x where m.tournament_id=t.id and x<>'Vrijgesteld' and x not like 'Winnaar wedstrijd %' order by x)),'champion',(select to_jsonb(cs) from predict_private.champion_settings cs where cs.tournament_id=t.id),'rules',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'winner_points',rs.winner_points,'exact_points',rs.exact_score_points) order by r.round_order),'[]') from public.tournament_rounds r left join public.round_scoring rs on rs.round_id=r.id and rs.tournament_id=t.id where r.tournament_id=t.id)) order by t.name),'[]') from public.tournaments t left join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.results_archived_at is null);
end $function$;
CREATE OR REPLACE FUNCTION predict_private.manage_tournament(p_id uuid, p_action text, p_values jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=predict_private.ko_admin();t public.tournaments%rowtype;
begin
 if exists(select 1 from predict_private.tournament_final_snapshots where tournament_id=p_id) then raise exception 'Het eindklassement staat vast; beheerwijzigingen zijn gesloten' using errcode='42501';end if;
 if p_action='metadata' and exists(select 1 from predict_private.mastercaller_sources where tournament_id=p_id) and
  exists(select 1 from public.tournaments where id=p_id and (starts_at is distinct from nullif(p_values->>'start','')::timestamptz or
   ends_at is distinct from case when p_values?'end' then nullif(p_values->>'end','')::timestamptz else ends_at end))
 then raise exception 'De toernooiperiode wordt uitsluitend door Mastercaller bepaald' using errcode='42501';end if;
 if p_action not in('archive','unarchive') then return predict_private.manage_tournament_before_archive(p_id,p_action,p_values);end if;
 select * into t from public.tournaments where id=p_id for update;
 if not found then raise exception 'Toernooi niet gevonden';end if;
 perform 1 from public.matches where tournament_id=p_id order by id for update;
 if p_action='archive' and not predict_private.tournament_finished(p_id) then raise exception 'Archiveren kan zodra het toernooi is afgelopen en alle uitslagen bekend zijn';end if;
 update public.tournaments set admin_archived=(p_action='archive') where id=p_id;
 insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details) values(p_id,actor,p_action,'Toernooibeheer: '||p_action,jsonb_build_object('previous_admin_archived',t.admin_archived,'player_visible_until',t.ends_at+interval '72 hours'));
 return true;
end $function$;

CREATE OR REPLACE FUNCTION predict_private.ko_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform predict_private.ko_admin();
  return jsonb_build_object('sports',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'slug',slug)) from public.sports where slug in ('darts','football')),
    'templates',(select coalesce(jsonb_agg(to_jsonb(v) order by v.name),'[]') from (select id,sport_id,name,participant_kind,participant_count,rules,scoring_mode from predict_private.knockout_templates)v),
    'tournaments',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'status',t.status)),'[]') from public.tournaments t join predict_private.knockout_tournaments k on k.tournament_id=t.id where t.results_archived_at is null));
end $function$;
create or replace function predict_private.management_catalog() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(x||jsonb_build_object('admin_archived',t.admin_archived,'finished',predict_private.tournament_finished(t.id),
 'archive_blocked',t.ends_at<=clock_timestamp()-interval '72 hours' and not predict_private.finalization_ready(t.id),
 'pending_count',(select count(*) from public.matches m where m.tournament_id=t.id and m.status in('scheduled','live') and m.home_score is null and m.away_score is null and predict_private.pending_result(m)))),'[]')
 from jsonb_array_elements(predict_private.management_catalog_before_archive())x join public.tournaments t on t.id=(x->>'id')::uuid where t.results_archived_at is null);
end $$;