alter table predict_branding.settings add column theme text not null default 'standard' check(theme in ('standard','christmas'));
alter table predict_branding.audit add column old_theme text, add column new_theme text;
create or replace function predict_branding.read_appearance() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('accent',accent,'theme',theme) from predict_branding.settings where singleton
$$;
create function predict_branding.write_theme(p_theme text) returns text language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();previous text;
begin
 if actor is null or not exists(select 1 from public.user_roles where user_id=actor and role='super_admin') then
  raise exception 'Alleen de Hoofdbeheerder kan het thema activeren' using errcode='42501';
 end if;
 if p_theme is null or p_theme not in ('standard','christmas') then raise exception 'Ongeldig thema' using errcode='22023';end if;
 select theme into strict previous from predict_branding.settings where singleton for update;
 if previous is distinct from p_theme then
  update predict_branding.settings set theme=p_theme,updated_by=actor,updated_at=clock_timestamp() where singleton;
  insert into predict_branding.audit(changed_by,old_theme,new_theme) values(actor,previous,p_theme);
 end if;
 return p_theme;
end $$;
create function public.set_app_theme(p_theme text) returns text language sql security invoker set search_path='' as $$select predict_branding.write_theme(p_theme)$$;
revoke all on function predict_branding.write_theme(text),public.set_app_theme(text) from public,anon,authenticated;
grant execute on function predict_branding.write_theme(text),public.set_app_theme(text) to authenticated;
