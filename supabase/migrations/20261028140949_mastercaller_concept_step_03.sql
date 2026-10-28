create function predict_private.finish_source_setup(p_tournament uuid,p_lease uuid,p_snapshot jsonb,p_error text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg predict_private.mastercaller_sources%rowtype;r jsonb;rid uuid;state text;problem text:=nullif(p_error,'');nr int;participants int;
begin
 perform 1 from public.tournaments where id=p_tournament for update;
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_tournament for update;
 if not found or not cfg.setup_pending or p_lease is null or cfg.lease is null or cfg.last_attempt is null or cfg.lease is distinct from p_lease or cfg.last_attempt<clock_timestamp()-interval '5 minutes' then raise exception 'Verouderde lotingcontrole';end if;
 if problem is null then begin
  if predict_private.mastercaller_url(p_snapshot->>'url') is distinct from cfg.url or coalesce(p_snapshot->>'start_date','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' or coalesce(p_snapshot->>'end_date','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$'
   or jsonb_typeof(p_snapshot->'rounds') is distinct from 'array' or jsonb_typeof(p_snapshot->'matches') is distinct from 'array' or jsonb_typeof(p_snapshot->'roster') is distinct from 'array'
   or coalesce(p_snapshot->>'format','') not in('knockout','groups') or jsonb_array_length(p_snapshot->'rounds') not between 1 and 8 or jsonb_array_length(p_snapshot->'matches')>256 then raise exception 'Ongeldige toernooigegevens in de bron';end if;
  nr:=jsonb_array_length(p_snapshot->'rounds');participants:=jsonb_array_length(p_snapshot->'roster');
  if exists(select 1 from jsonb_array_elements(p_snapshot->'rounds')x where (x->>'order')::int not between 1 and nr or length(coalesce(x->>'name','')) not between 1 and 80 or x->>'unit' not in('legs','sets') or ((x->>'first_to')::int is null and not(p_snapshot->>'format'='groups' and x->>'order'='1')) or (x->>'first_to')::int not between 1 and 99)
   or (select count(distinct x->>'order') from jsonb_array_elements(p_snapshot->'rounds')x)<>nr then raise exception 'Onvolledig bronformaat';end if;
  if coalesce((p_snapshot->>'ready')::boolean,false) then
   if participants not between 2 and 128 or (select count(distinct predict_private.score_name(value)) from jsonb_array_elements_text(p_snapshot->'roster'))<>participants
    or exists(select 1 from jsonb_array_elements_text(p_snapshot->'roster')x where length(btrim(x)) not between 1 and 80)
    or exists(select 1 from jsonb_array_elements(p_snapshot->'matches')x where (x->>'round')::int not between 1 and nr or length(coalesce(x->>'key','')) not between 1 and 300 or (x->>'round'='1' and (nullif(x->>'home_name','') is null or nullif(x->>'away_name','') is null)))
    or (select count(distinct x->>'key') from jsonb_array_elements(p_snapshot->'matches')x)<>jsonb_array_length(p_snapshot->'matches')
   then raise exception 'De eerste ronde is niet volledig bekend';end if;
  end if;
  perform predict_private.mc_enter(p_tournament);
  for r in select * from jsonb_array_elements(p_snapshot->'rounds') loop
   select id into rid from public.tournament_rounds where tournament_id=p_tournament and round_order=(r->>'order')::int;
   if rid is null then insert into public.tournament_rounds(tournament_id,name,round_order) values(p_tournament,r->>'name',(r->>'order')::int) returning id into rid;end if;
   if not exists(select 1 from public.round_scoring where round_id=rid) then insert into public.round_scoring(tournament_id,round_id,winner_points,exact_score_points) values(p_tournament,rid,cfg.setup_winner,cfg.setup_exact);end if;
  end loop;
  update public.tournaments set starts_at=(p_snapshot->>'start_date')::date::timestamp at time zone 'Europe/Amsterdam',ends_at=((p_snapshot->>'end_date')::date::timestamp+interval '23 hours 59 minutes') at time zone 'Europe/Amsterdam' where id=p_tournament;
  perform predict_private.mc_exit(p_tournament);
  state:=case when coalesce((p_snapshot->>'ready')::boolean,false) then 'ready' else 'waiting' end;
  update predict_private.mastercaller_sources set setup_state=state,setup_snapshot=p_snapshot,setup_error=null,setup_checked_at=clock_timestamp(),setup_ready_at=case when state='ready' then coalesce(setup_ready_at,clock_timestamp()) else setup_ready_at end,
   setup_next_check_at=clock_timestamp()+interval '24 hours',last_success=clock_timestamp(),lease=null,report=jsonb_build_object('checked_at',clock_timestamp(),'setup_state',state,'reason',p_snapshot->>'reason') where tournament_id=p_tournament;
  return jsonb_build_object('status',state,'id',p_tournament);
 exception when others then problem:=left(sqlerrm,400);end;end if;
 update predict_private.mastercaller_sources set setup_state='error',setup_error=left(problem,400),setup_checked_at=clock_timestamp(),setup_next_check_at=clock_timestamp()+interval '24 hours',lease=null,report=jsonb_build_object('error',left(problem,400),'checked_at',clock_timestamp()) where tournament_id=p_tournament;
 return jsonb_build_object('status','error','error',problem);
end $$;
revoke all on function predict_private.finish_source_setup(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function predict_private.finish_source_setup(uuid,uuid,jsonb,text) to service_role;
create function public.finish_mastercaller_setup(p_tournament uuid,p_lease uuid,p_snapshot jsonb,p_error text default null) returns jsonb language sql security invoker set search_path='' as $$select predict_private.finish_source_setup(p_tournament,p_lease,p_snapshot,p_error)$$;
revoke all on function public.finish_mastercaller_setup(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.finish_mastercaller_setup(uuid,uuid,jsonb,text) to service_role;
