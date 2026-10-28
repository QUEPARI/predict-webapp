create or replace function predict_private.mc_source_info(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('locked',s.tournament_id is not null,'automatic_setup',coalesce(s.automatic_setup,false),'stopped',predict_private.mc_final_finished(p_id),
  'setup_pending',coalesce(s.setup_pending,false),'setup_state',s.setup_state,'setup_checked_at',s.setup_checked_at,'setup_next_check_at',s.setup_next_check_at,'setup_ready_at',s.setup_ready_at,'setup_error',s.setup_error,
  'setup_reason',s.setup_snapshot->>'reason','format',s.setup_snapshot->>'format','format_required',s.setup_pending and s.setup_snapshot->>'format'='groups' and s.setup_snapshot->'rounds'->0->>'first_to' is null)
 from public.tournaments t left join predict_private.mastercaller_sources s on s.tournament_id=t.id where t.id=p_id
$$;
