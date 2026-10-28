create function predict_private.source_lifecycle(p_id uuid,p_action text,p_group_first_to integer)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();cfg predict_private.mastercaller_sources%rowtype;t public.tournaments%rowtype;f jsonb;r jsonb;rid uuid;mid uuid;ft int;
begin
 select * into t from public.tournaments where id=p_id for update;
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_id for update;
 if not found or t.status not in('draft','announced') then raise exception 'Kies een Mastercaller-concept of voorvertoning';end if;
 if p_action not in('announce','draft','publish') or p_action is null then raise exception 'Onbekende bronactie';end if;
 perform predict_private.mc_enter(p_id);
 if p_action='announce' then
  if t.starts_at is null or t.ends_at is null then raise exception 'Wacht eerst op de bronperiode voordat je de voorvertoning toont';end if;
  update public.tournaments set status='announced' where id=p_id;
 elsif p_action='draft' then update public.tournaments set status='draft' where id=p_id;
 elsif cfg.source_layout='legacy' then
  if cardinality(predict_private.ko_publication_issues(p_id,t.starts_at))>0 then raise exception 'Controleer het volledige schema en de punten voordat je publiceert';end if;
  update public.tournaments set status='published' where id=p_id;
  perform predict_private.sync_mastercaller_schema(p_id,cfg.snapshot);
 else
  if cfg.setup_state is distinct from 'ready' or cfg.lease is not null or cfg.setup_checked_at<clock_timestamp()-interval '24 hours' or not coalesce((cfg.setup_snapshot->>'ready')::boolean,false) then raise exception 'De eerste ronde is nog niet volledig bekend of de controle is verouderd. Controleer de bron opnieuw.';end if;
  if t.starts_at is null or t.ends_at is null then raise exception 'De toernooiperiode ontbreekt';end if;
  if exists(select 1 from public.matches where tournament_id=p_id) then raise exception 'Dit concept bevat al wedstrijden';end if;
  if cfg.setup_snapshot->>'format'='groups' and cfg.setup_snapshot->'rounds'->0->>'first_to' is null and (p_group_first_to is null or p_group_first_to not between 1 and 99) then raise exception 'Vul de gecontroleerde first-to voor de groepsfase in';end if;
  if exists(select 1 from public.tournament_rounds tr left join public.round_scoring rs on rs.round_id=tr.id where tr.tournament_id=p_id and (rs.winner_points is null or rs.exact_score_points is null)) then raise exception 'Vul de punten voor iedere ronde in';end if;
  -- Only the explicit administrator action may publish a pending source concept.
  update public.tournaments set status='published' where id=p_id;
  for f in select * from jsonb_array_elements(cfg.setup_snapshot->'matches') loop
   select value into r from jsonb_array_elements(cfg.setup_snapshot->'rounds') where value->>'order'=f->>'round';
   select id into rid from public.tournament_rounds where tournament_id=p_id and round_order=(f->>'round')::int;
   ft:=coalesce((r->>'first_to')::int,case when cfg.setup_snapshot->>'format'='groups' and f->>'round'='1' then p_group_first_to end);
   if rid is null or ft is null or ft not between 1 and 99 then raise exception 'De bronspelvorm is nog niet volledig ingevuld';end if;
   insert into public.matches(tournament_id,round_id,home_name,away_name,score_unit,first_to,data_source,status,scheduled_start,start_time_confirmed,source_time_pending,needs_review,predictions_enabled)
    values(p_id,rid,coalesce(nullif(f->>'home_name',''),'NNB'),coalesce(nullif(f->>'away_name',''),'NNB'),r->>'unit',ft,'mastercaller','scheduled',nullif(f->>'start','')::timestamptz,nullif(f->>'start','') is not null,nullif(f->>'start','') is null,nullif(f->>'home_name','') is null or nullif(f->>'away_name','') is null,false) returning id into mid;
   insert into predict_private.mastercaller_match_map(match_id,tournament_id,source_key,group_name,position) values(mid,p_id,f->>'key',f->>'group',(f->>'position')::int);
  end loop;
  -- A past start already locks scoring through the existing time guard.
  if t.starts_at>clock_timestamp() then update public.tournament_scoring set is_locked=true where tournament_id=p_id and not is_locked;end if;
  update predict_private.mastercaller_sources set setup_pending=false,setup_state='published',group_first_to=p_group_first_to,last_attempt=null,lease=null,snapshot=cfg.setup_snapshot where tournament_id=p_id;
  perform predict_private.sync_generic_source(p_id,cfg.setup_snapshot);
 end if;
 perform predict_private.mc_exit(p_id);
 insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details) values(p_id,actor,'source_'||p_action,'Handmatige statuskeuze door beheerder',jsonb_build_object('before',t.status,'source',cfg.url,'checked_at',cfg.setup_checked_at));
 return true;
end $$;
revoke all on function predict_private.source_lifecycle(uuid,text,integer) from public,anon,service_role;
grant execute on function predict_private.source_lifecycle(uuid,text,integer) to authenticated;
create function public.admin_source_lifecycle(p_id uuid,p_action text,p_group_first_to integer default null) returns boolean language sql security invoker set search_path='' as $$select predict_private.source_lifecycle(p_id,p_action,p_group_first_to)$$;
revoke all on function public.admin_source_lifecycle(uuid,text,integer) from public,anon,service_role;
grant execute on function public.admin_source_lifecycle(uuid,text,integer) to authenticated;
