begin;
do $$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); token text; replacement text; address text:=b||'@predict-account-qa.invalid'; n integer;
begin
  insert into auth.users(id,email,email_confirmed_at,aud,role,raw_user_meta_data) values
    (a,a||'@predict-account-qa.invalid',now(),'authenticated','authenticated','{}'),
    (b,address,null,'authenticated','authenticated','{"role":"super_admin"}'),
    (c,c||'@predict-account-qa.invalid',null,'authenticated','authenticated','{}');
  insert into public.user_roles values(a,'admin'),(c,'user');
  perform set_config('request.jwt.claim.sub',c::text,true);perform set_config('role','authenticated',true);
  begin perform public.create_account_invitation(address);raise exception 'FAIL ordinary user issued invitation';exception when insufficient_privilege then null;end;
  begin perform public.reserve_account_invitation_mail(repeat('0',64),address);raise exception 'FAIL client can reserve mail';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',a::text,true);
  token:=public.create_account_invitation(address);
  if token !~ '^[0-9a-f]{64}$' then raise exception 'FAIL token entropy/format';end if;
  perform set_config('role','postgres',true);
  if exists(select 1 from public.invitations where token_hash=token) then raise exception 'FAIL plaintext storage';end if;
  perform set_config('role','service_role',true);
  if public.reserve_account_invitation_mail(token,'wrong@predict-account-qa.invalid') is not null then raise exception 'FAIL wrong address';end if;
  if public.reserve_account_invitation_mail(token,address)<>address then raise exception 'FAIL valid mail';end if;
  if public.reserve_account_invitation_mail(token,address) is not null then raise exception 'FAIL mail cooldown';end if;
  for n in 2..5 loop
    perform set_config('role','postgres',true);
    update public.invitations set account_mail_requested_at=now()-interval '2 minutes' where token_hash=encode(extensions.digest(token,'sha256'),'hex');
    perform set_config('role','service_role',true);
    if public.reserve_account_invitation_mail(token,address)<>address then raise exception 'FAIL mail retry';end if;
  end loop;
  perform set_config('role','postgres',true);
  update public.invitations set account_mail_requested_at=now()-interval '2 minutes' where token_hash=encode(extensions.digest(token,'sha256'),'hex');
  perform set_config('role','service_role',true);
  if public.reserve_account_invitation_mail(token,address) is not null then raise exception 'FAIL five mail budget';end if;
  perform set_config('role','authenticated',true);perform set_config('request.jwt.claim.sub',b::text,true);
  begin perform public.complete_account_invitation();raise exception 'FAIL unconfirmed email';exception when insufficient_privilege then null;end;
  begin perform public.create_account_invitation('other@predict-account-qa.invalid');raise exception 'FAIL metadata grants admin';exception when insufficient_privilege then null;end;
  perform set_config('role','postgres',true);update auth.users set email_confirmed_at=now() where id=b;
  perform set_config('role','authenticated',true);perform public.complete_account_invitation();perform public.complete_account_invitation();
  if not exists(select 1 from public.user_roles where user_id=b and role='user') then raise exception 'FAIL role';end if;
  if not exists(select 1 from public.profiles where id=b) then raise exception 'FAIL profile';end if;
  begin perform public.create_account_invitation('other@predict-account-qa.invalid');raise exception 'FAIL provisioned user becomes admin';exception when insufficient_privilege then null;end;
  perform set_config('role','postgres',true);
  if not exists(select 1 from public.invitations where email=address and status='accepted' and accepted_by=b) then raise exception 'FAIL consume';end if;
  perform set_config('role','service_role',true);
  if public.reserve_account_invitation_mail(token,address) is not null then raise exception 'FAIL reuse';end if;
  perform set_config('role','authenticated',true);perform set_config('request.jwt.claim.sub',a::text,true);
  token:=public.create_account_invitation(c||'@predict-account-qa.invalid');replacement:=public.create_account_invitation(c||'@predict-account-qa.invalid');
  perform set_config('role','service_role',true);
  if public.reserve_account_invitation_mail(token,c||'@predict-account-qa.invalid') is not null then raise exception 'FAIL replaced';end if;
  perform set_config('role','postgres',true);
  update public.invitations set created_at=now()-interval '9 days',expires_at=now()-interval '1 day' where token_hash=encode(extensions.digest(replacement,'sha256'),'hex');
  perform set_config('role','service_role',true);
  if public.reserve_account_invitation_mail(replacement,c||'@predict-account-qa.invalid') is not null then raise exception 'FAIL expired';end if;
  perform set_config('role','postgres',true);
  begin update auth.users set email_confirmed_at=now() where id=c;raise exception 'FAIL expired Auth confirmation';exception when insufficient_privilege then null;end;
  perform set_config('role','authenticated',true);perform set_config('request.jwt.claim.sub',a::text,true);
  token:=public.create_account_invitation(c||'@predict-account-qa.invalid');perform public.revoke_account_invitations(c||'@predict-account-qa.invalid');
  perform set_config('role','service_role',true);
  if public.reserve_account_invitation_mail(token,c||'@predict-account-qa.invalid') is not null then raise exception 'FAIL revoked';end if;
  perform set_config('role','postgres',true);
  begin update auth.users set email_confirmed_at=now() where id=c;raise exception 'FAIL revoked Auth confirmation';exception when insufficient_privilege then null;end;
  perform set_config('role','authenticated',true);perform set_config('request.jwt.claim.sub',c::text,true);
  begin perform public.complete_account_invitation();raise exception 'FAIL revoked completion';exception when insufficient_privilege then null;end;
  perform set_config('role','anon',true);perform set_config('request.jwt.claim.sub','',true);
  begin perform public.complete_account_invitation();raise exception 'FAIL anon completion';exception when insufficient_privilege then null;end;
  perform set_config('role','postgres',true);
  perform set_config('request.jwt.claim.sub',a::text,true);
  for n in 1..20-(select count(*)::integer from public.invitations where invited_by=a and pool_id is null and created_at>clock_timestamp()-interval '24 hours') loop
    perform set_config('role','authenticated',true);
    perform public.create_account_invitation('budget-'||n||'-'||a||'@predict-account-qa.invalid');
  end loop;
  begin
    perform public.create_account_invitation('over-budget@predict-account-qa.invalid');raise exception 'FAIL twenty invite budget';
  exception when others then if sqlerrm<>'Maximaal twintig accountuitnodigingen per 24 uur' then raise;end if;end;
  perform set_config('role','postgres',true);
end $$;
rollback;
