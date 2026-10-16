create or replace function predict_private.invite_pool_member(p_pool_id uuid,p_email text) returns text
language plpgsql security definer set search_path='' as $$
declare e text:=p_email;
begin
  -- Check ownership before resolving names: outsiders must not probe a user directory.
  if auth.uid() is null or not exists(select 1 from public.pools where id=p_pool_id and owner_id=auth.uid()) then
    raise exception 'Alleen de poulebeheerder kan uitnodigen' using errcode='42501';end if;
  if position('@' in e)=0 then
    select a.email into e from auth.users a join public.profiles p on p.id=a.id where lower(p.username)=lower(btrim(p_email));
    if e is null then raise exception 'Gebruiker niet beschikbaar';end if;
  end if;
  return predict_private.invite_pool_member_email(p_pool_id,e);
end $$;
