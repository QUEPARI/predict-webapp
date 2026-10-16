-- Existing hosted schema; the private schema was created by secure_private_pools.
create function predict_private.join_tournament(p_tournament_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
  -- Serialize with concurrent tournament status changes; never accept drafts.
  perform 1 from public.tournaments where id=p_tournament_id
    and status in ('published','active') for share;
  if not found then raise exception 'Toernooi niet beschikbaar voor deelname'; end if;
  insert into public.tournament_entries(tournament_id,user_id)
    values(p_tournament_id,v_user) on conflict do nothing;
  return p_tournament_id;
end;
$$;
create function public.join_tournament(p_tournament_id uuid)
returns uuid language sql security invoker set search_path='' as $$
  select predict_private.join_tournament(p_tournament_id);
$$;
revoke all on function predict_private.join_tournament(uuid),public.join_tournament(uuid) from public,anon;
grant execute on function predict_private.join_tournament(uuid),public.join_tournament(uuid) to authenticated;
notify pgrst,'reload schema';
