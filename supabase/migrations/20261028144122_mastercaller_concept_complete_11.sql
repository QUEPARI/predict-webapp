-- Generic source layouts keep group matches and knock-out rounds separate.
alter function predict_private.ko_schema(uuid) rename to ko_schema_before_source_drafts;
revoke all on function predict_private.ko_schema_before_source_drafts(uuid) from public,anon,authenticated,service_role;
create function predict_private.ko_schema(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;cfg predict_private.mastercaller_sources%rowtype;admin boolean;
begin
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_id and source_layout='generic';
 if not found then return predict_private.ko_schema_before_source_drafts(p_id);end if;
 admin:=exists(select 1 from public.user_roles where user_id=auth.uid() and role in('admin','super_admin'));
 if auth.uid() is null or not exists(select 1 from public.tournaments where id=p_id and (admin or status in('published','active','completed','archived'))) then raise exception 'Toernooi niet beschikbaar' using errcode='42501';end if;
 select jsonb_build_object('tournament_id',t.id,'name',t.name,'status',t.status,'format',cfg.setup_snapshot->>'format','source_layout','generic','start',t.starts_at,'end',t.ends_at,'server_now',clock_timestamp(),'score_source',predict_private.mc_source_info(t.id),'roster',cfg.setup_snapshot->'roster',
  'rounds',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'order',r.round_order,'unit',(cfg.setup_snapshot->'rounds'->(r.round_order-1)->>'unit'),'first_to',coalesce((cfg.setup_snapshot->'rounds'->(r.round_order-1)->>'first_to')::int,case when r.round_order=1 then cfg.group_first_to end)) order by r.round_order) from public.tournament_rounds r where r.tournament_id=t.id),'[]'),
  'matches',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'number',rownum,'round',r.round_order,'group',map.group_name,'home',m.home_name,'away',m.away_name,'home_slot',case when not m.needs_review then 1 end,'away_slot',case when not m.needs_review then 2 end,'bye',false,'start',m.scheduled_start,'actual_start',m.actual_start,'status',m.status,'home_score',m.home_score,'away_score',m.away_score,'unit',m.score_unit,'first_to',m.first_to,'enabled',m.predictions_enabled,'needs_review',m.needs_review) order by r.round_order,map.source_key)
   from public.matches m join public.tournament_rounds r on r.id=m.round_id join predict_private.mastercaller_match_map map on map.match_id=m.id
   cross join lateral (select r.round_order*1000+map.position rownum) numbers where m.tournament_id=t.id),'[]')) into result from public.tournaments t where t.id=p_id;
 return result;
end $$;
revoke all on function predict_private.ko_schema(uuid) from public,anon,service_role;
grant execute on function predict_private.ko_schema(uuid) to authenticated;
