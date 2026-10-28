create function predict_private.claim_source_setups() returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg record;items jsonb:='[]';token uuid;
begin
 for cfg in select s.* from predict_private.mastercaller_sources s join public.tournaments t on t.id=s.tournament_id
 where s.setup_pending and t.status in('draft','announced') and coalesce(s.setup_next_check_at,'-infinity')<=clock_timestamp()
 and (s.lease is null or s.last_attempt<clock_timestamp()-interval '5 minutes')
 and (s.last_attempt is null or s.last_attempt<clock_timestamp()-interval '1 minute')
 order by s.setup_next_check_at nulls first limit 3 for update of s skip locked loop
  token:=gen_random_uuid();update predict_private.mastercaller_sources set lease=token,last_attempt=clock_timestamp(),setup_next_check_at=clock_timestamp()+interval '24 hours' where tournament_id=cfg.tournament_id;
  items:=items||jsonb_build_array(jsonb_build_object('kind','setup','tournament_id',cfg.tournament_id,'url',cfg.url,'lease',token));
 end loop;return items;
end $$;
revoke all on function predict_private.claim_source_setups() from public,anon,authenticated;
grant execute on function predict_private.claim_source_setups() to service_role;
create function public.claim_mastercaller_setups() returns jsonb language sql security invoker set search_path='' as $$select predict_private.claim_source_setups()$$;
revoke all on function public.claim_mastercaller_setups() from public,anon,authenticated;
grant execute on function public.claim_mastercaller_setups() to service_role;
