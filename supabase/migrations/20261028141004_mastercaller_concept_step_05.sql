create function predict_private.request_source_setup_check(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform predict_private.ko_admin();perform 1 from public.tournaments where id=p_id and status in('draft','announced') for update;
 update predict_private.mastercaller_sources set setup_next_check_at=clock_timestamp() where tournament_id=p_id and setup_pending and lease is null and (last_attempt is null or last_attempt<clock_timestamp()-interval '1 minute');
 if not found then raise exception 'Er loopt al een lotingcontrole of de laatste controle was minder dan een minuut geleden';end if;
 return jsonb_build_object('status','queued','message','Lotingcontrole staat klaar. GitHub haalt de bron bij de volgende uitvoering op.');
end $$;
revoke all on function predict_private.request_source_setup_check(uuid) from public,anon,service_role;
grant execute on function predict_private.request_source_setup_check(uuid) to authenticated;
create function public.admin_request_mastercaller_setup_check(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select predict_private.request_source_setup_check(p_id)$$;
revoke all on function public.admin_request_mastercaller_setup_check(uuid) from public,anon,service_role;
grant execute on function public.admin_request_mastercaller_setup_check(uuid) to authenticated;
