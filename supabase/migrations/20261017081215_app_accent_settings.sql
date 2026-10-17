-- Isolated, non-exposed appearance storage. Anonymous schema usage grants no table access.
create schema predict_branding;
revoke all on schema predict_branding from public;
grant usage on schema predict_branding to anon,authenticated;
create table predict_branding.settings (
 singleton boolean primary key default true check(singleton),
 accent text check(accent is null or accent ~ '^#[0-9a-f]{6}$'),
 updated_by uuid,updated_at timestamptz not null default now()
);
insert into predict_branding.settings(singleton,accent) values(true,null);
create table predict_branding.audit (
 id uuid primary key default gen_random_uuid(),changed_by uuid not null,
 old_accent text,new_accent text,changed_at timestamptz not null default now()
);
alter table predict_branding.settings enable row level security;
alter table predict_branding.audit enable row level security;
revoke all on table predict_branding.settings,predict_branding.audit from public,anon,authenticated;
create function predict_branding.read_appearance() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('accent',accent) from predict_branding.settings where singleton
$$;
create function predict_branding.write_appearance(p_accent text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();chosen text:=lower(btrim(p_accent));previous text;
begin
 if chosen is not null and chosen !~ '^#[0-9a-f]{6}$' then raise exception 'Kies een geldige kleur (#RRGGBB)' using errcode='22023';end if;
 select accent into previous from predict_branding.settings where singleton for update;
 if previous is distinct from chosen then
   update predict_branding.settings set accent=chosen,updated_by=actor,updated_at=clock_timestamp() where singleton;
   insert into predict_branding.audit(changed_by,old_accent,new_accent) values(actor,previous,chosen);
 end if;
 return jsonb_build_object('accent',chosen);
end $$;
create function public.get_app_appearance() returns jsonb language sql security invoker set search_path='' as $$select predict_branding.read_appearance()$$;
create function public.set_app_appearance(p_accent text) returns jsonb language sql security invoker set search_path='' as $$select predict_branding.write_appearance(p_accent)$$;
revoke all on function predict_branding.read_appearance(),predict_branding.write_appearance(text),public.get_app_appearance(),public.set_app_appearance(text) from public,anon,authenticated;
grant execute on function predict_branding.read_appearance(),public.get_app_appearance() to anon,authenticated;
grant execute on function predict_branding.write_appearance(text),public.set_app_appearance(text) to authenticated;
