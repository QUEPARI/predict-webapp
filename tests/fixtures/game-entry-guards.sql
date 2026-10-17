CREATE OR REPLACE FUNCTION predict_private.create_pool(p_tournament_id uuid, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
  if p_name is null or length(btrim(p_name)) not between 2 and 80 then
    raise exception 'Gebruik een poulenaam van 2 tot 80 tekens'; end if;
  if not exists(select 1 from public.tournaments where id=p_tournament_id and status in ('published','active')) then
    raise exception 'Toernooi niet beschikbaar'; end if;
  insert into public.tournament_entries(tournament_id,user_id) values(p_tournament_id,v_uid) on conflict do nothing;
  insert into public.pools(tournament_id,name,owner_id) values(p_tournament_id,btrim(p_name),v_uid) returning id into v_id;
  insert into public.pool_members(pool_id,user_id) values(v_id,v_uid);
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION predict_private.join_tournament(p_tournament_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
create or replace function public.join_tournament(p_tournament_id uuid) returns uuid language sql security invoker set search_path='' as $$select predict_private.join_tournament(p_tournament_id)$$;
create or replace function public.create_pool(p_tournament_id uuid,p_name text) returns uuid language sql security invoker set search_path='' as $$select predict_private.create_pool(p_tournament_id,p_name)$$;
grant execute on function predict_private.join_tournament(uuid),predict_private.create_pool(uuid,text),public.join_tournament(uuid),public.create_pool(uuid,text) to authenticated;

