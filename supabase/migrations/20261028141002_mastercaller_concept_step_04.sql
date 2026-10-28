create function predict_private.source_draft_preview(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform predict_private.ko_admin();return (select setup_snapshot from predict_private.mastercaller_sources where tournament_id=p_id and setup_pending);
end $$;
revoke all on function predict_private.source_draft_preview(uuid) from public,anon,service_role;
grant execute on function predict_private.source_draft_preview(uuid) to authenticated;
create function public.admin_source_draft_preview(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select predict_private.source_draft_preview(p_id)$$;
revoke all on function public.admin_source_draft_preview(uuid) from public,anon,service_role;
grant execute on function public.admin_source_draft_preview(uuid) to authenticated;
