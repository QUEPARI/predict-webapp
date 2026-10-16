-- Mutate only explicitly supported preferences on the caller's existing profile.
create function predict_private.update_my_profile(p_display_name text default null,p_theme text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_profile public.profiles%rowtype;
begin
  if v_user is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
  if p_display_name is null and p_theme is null then raise exception 'Geen profielwijziging opgegeven'; end if;
  if p_display_name is not null and (length(btrim(p_display_name)) not between 1 and 40 or p_display_name ~ '[[:cntrl:]]') then
    raise exception 'Gebruik een weergavenaam van 1 tot 40 tekens zonder regelafbrekingen'; end if;
  if p_theme is not null and p_theme not in ('system','light','dark') then raise exception 'Ongeldig thema'; end if;
  update public.profiles set display_name=coalesce(btrim(p_display_name),display_name),theme=coalesce(p_theme,theme)
    where id=v_user returning * into v_profile;
  if not found then raise exception 'Eigen profiel niet gevonden' using errcode='42501'; end if;
  return jsonb_build_object('display_name',v_profile.display_name,'theme',v_profile.theme);
end;
$$;
create function public.update_my_profile(p_display_name text default null,p_theme text default null)
returns jsonb language sql security invoker set search_path='' as $$
  select predict_private.update_my_profile(p_display_name,p_theme);
$$;
revoke all on function predict_private.update_my_profile(text,text),public.update_my_profile(text,text) from public,anon;
grant execute on function predict_private.update_my_profile(text,text),public.update_my_profile(text,text) to authenticated;
-- Preserve the existing own-profile SELECT policy; direct edits are not an API.
revoke all on public.profiles from public,anon,authenticated;
grant select on public.profiles to authenticated;
alter table public.profiles enable row level security;
notify pgrst,'reload schema';
