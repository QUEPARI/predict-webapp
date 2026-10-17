begin;
do $$
declare a uuid:=gen_random_uuid();u uuid:=gen_random_uuid();r jsonb;
begin
 if to_regclass('auth.users') is not null then insert into auth.users(id,email,email_confirmed_at,aud,role) values(a,a||'@accent-qa.invalid',now(),'authenticated','authenticated'),(u,u||'@accent-qa.invalid',now(),'authenticated','authenticated');end if;
 insert into public.profiles(id,username) values(a,'accent-'||substr(a::text,1,20)),(u,'accent-'||substr(u::text,1,20)) on conflict do nothing;
 insert into public.user_roles values(a,'admin'),(u,'user');
 perform set_config('role','anon',true);r:=public.get_app_appearance();
 if (select count(*) from jsonb_object_keys(r))<>1 or not r ? 'accent' then raise exception 'FAIL public response contract';end if;
 begin perform public.set_app_appearance('#abcdef');raise exception 'FAIL anon write';exception when insufficient_privilege then null;end;
 begin perform 1 from predict_branding.settings;raise exception 'FAIL anon table access';exception when insufficient_privilege then null;end;
 perform set_config('role','authenticated',true);perform set_config('request.jwt.claim.sub',u::text,true);
 begin perform public.set_app_appearance('#abcdef');raise exception 'FAIL ordinary user write';exception when insufficient_privilege then null;end;
 begin perform 1 from predict_branding.audit;raise exception 'FAIL user audit access';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',a::text,true);r:=public.set_app_appearance('#ABCDEF');
 if r->>'accent'<>'#abcdef' or public.get_app_appearance()->>'accent'<>'#abcdef' then raise exception 'FAIL persisted normalized color';end if;
 begin perform public.set_app_appearance('red;url(evil)');raise exception 'FAIL CSS injection accepted';exception when invalid_parameter_value then null;end;
 begin perform public.set_app_appearance('#123');raise exception 'FAIL short color accepted';exception when invalid_parameter_value then null;end;
 begin perform public.set_app_appearance('');raise exception 'FAIL empty color accepted';exception when invalid_parameter_value then null;end;
 perform public.set_app_appearance(null);
 if public.get_app_appearance()->>'accent' is not null then raise exception 'FAIL default reset';end if;
 begin update predict_branding.settings set accent='#112233';raise exception 'FAIL direct admin write';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.set_app_appearance('#abcdef');raise exception 'FAIL missing identity';exception when insufficient_privilege then null;end;
 perform set_config('role','postgres',true);
 if (select count(*) from predict_branding.audit where changed_by=a) not between 1 and 2 then raise exception 'FAIL audit history';end if;
end $$;
select 'PASS: public color only, admin write/reset, invalid colors rejected, audit and direct-table isolation' as result;
rollback;
