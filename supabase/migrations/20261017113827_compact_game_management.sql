-- Templates are snapshots; deleting a template never deletes or edits a game.
create function predict_private.delete_knockout_template(p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform predict_private.ko_admin();
 delete from predict_private.knockout_templates where id=p_id;
 if not found then raise exception 'Sjabloon niet gevonden';end if;
 return true;
end $$;
create function public.delete_knockout_template(p_id uuid)
returns boolean language sql security invoker set search_path='' as $$
 select predict_private.delete_knockout_template(p_id)
$$;
revoke all on function predict_private.delete_knockout_template(uuid),public.delete_knockout_template(uuid) from public,anon,authenticated;
grant execute on function predict_private.delete_knockout_template(uuid),public.delete_knockout_template(uuid) to authenticated;

-- Called only by the database scheduler, never from a browser. Keep all records.
create function predict_private.archive_expired_games()
returns integer language plpgsql security invoker set search_path='' as $$
declare archived_count integer;
begin
 update public.tournaments set status='archived'
 where status in('announced','published','active','completed')
 and ends_at is not null and ends_at<=clock_timestamp()-interval '168 hours';
 get diagnostics archived_count=row_count;
 if archived_count>0 then raise log 'Automatically archived % expired Predict games',archived_count;end if;
 return archived_count;
end $$;
revoke all on function predict_private.archive_expired_games() from public,anon,authenticated,service_role;

-- Hosted scheduler (omitted only by the isolated PGlite test runner).
create extension if not exists pg_cron;
select cron.schedule('predict-archive-expired-games','*/5 * * * *',
 $$select predict_private.archive_expired_games();$$);
