-- Claim only the tournament requested by the authenticated admin Edge handler.
create function predict_private.claim_source_setup_now(p_id uuid) returns jsonb
language sql security definer set search_path='' as $$
 with candidate as (
  select s.tournament_id from predict_private.mastercaller_sources s
  join public.tournaments t on t.id=s.tournament_id
  where s.tournament_id=p_id and s.setup_pending and t.status in ('draft','announced')
    and (s.lease is null or s.last_attempt<clock_timestamp()-interval '5 minutes')
    and (s.last_attempt is null or s.last_attempt<clock_timestamp()-interval '1 minute')
  for update of s skip locked
 ), claimed as (
  update predict_private.mastercaller_sources s set lease=gen_random_uuid(),
   last_attempt=clock_timestamp(),setup_next_check_at=clock_timestamp()+interval '24 hours'
  from candidate c where s.tournament_id=c.tournament_id
  returning s.tournament_id,s.url,s.lease
 ) select to_jsonb(claimed) from claimed
$$;
revoke all on function predict_private.claim_source_setup_now(uuid) from public,anon,authenticated;
grant execute on function predict_private.claim_source_setup_now(uuid) to service_role;
create function public.claim_mastercaller_setup_now(p_id uuid) returns jsonb
language sql security invoker set search_path='' as $$select predict_private.claim_source_setup_now(p_id)$$;
revoke all on function public.claim_mastercaller_setup_now(uuid) from public,anon,authenticated;
grant execute on function public.claim_mastercaller_setup_now(uuid) to service_role;
