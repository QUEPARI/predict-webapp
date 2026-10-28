alter function predict_private.management_catalog() rename to management_catalog_before_source_roster;
revoke all on function predict_private.management_catalog_before_source_roster() from public,anon,authenticated,service_role;
create function predict_private.management_catalog() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(case when s.source_layout='generic' then x||jsonb_build_object('roster',coalesce(s.setup_snapshot->'roster','[]'::jsonb)) else x end),'[]')
 from jsonb_array_elements(predict_private.management_catalog_before_source_roster())x left join predict_private.mastercaller_sources s on s.tournament_id=(x->>'id')::uuid);
end $$;
revoke all on function predict_private.management_catalog() from public,anon,service_role;
grant execute on function predict_private.management_catalog() to authenticated;