create function predict_private.guard_source_publication() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status in('published','active') and exists(select 1 from predict_private.mastercaller_sources where tournament_id=new.id and setup_pending and (setup_state is distinct from 'ready' or lease is not null or setup_checked_at is null or setup_checked_at<clock_timestamp()-interval '24 hours' or not coalesce((setup_snapshot->>'ready')::boolean,false))) then raise exception 'De loting is nog niet volledig beschikbaar of moet opnieuw worden gecontroleerd';end if;
 return new;
end $$;
revoke all on function predict_private.guard_source_publication() from public,anon,authenticated,service_role;
create trigger source_publication_guard before update of status on public.tournaments for each row execute function predict_private.guard_source_publication();
