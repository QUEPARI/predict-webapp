-- Account invitations are separate from pool invitations (pool_id IS NULL).
alter table public.invitations add column account_mail_requested_at timestamptz;
alter table public.invitations add column account_mail_attempts integer not null default 0;

create function predict_private.create_account_invitation(p_email text) returns text
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); e text:=lower(btrim(p_email)); token text;
begin
  if u is null or not exists(select 1 from public.user_roles where user_id=u and role in ('admin','super_admin')) then
    raise exception 'Alleen systeembeheerders kunnen accounts uitnodigen' using errcode='42501'; end if;
  if e is null or length(e)>254 or e !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Ongeldig e-mailadres'; end if;
  -- Serialize both the per-admin budget and replacement of invitations for an email.
  perform pg_advisory_xact_lock(hashtextextended('account-admin:'||u,0));
  perform pg_advisory_xact_lock(hashtextextended('account-email:'||e,0));
  if (select count(*) from public.invitations where invited_by=u and pool_id is null and created_at>clock_timestamp()-interval '24 hours')>=20 then
    raise exception 'Maximaal twintig accountuitnodigingen per 24 uur'; end if;
  if exists(select 1 from auth.users a join public.profiles p on p.id=a.id where lower(a.email)=e) then
    raise exception 'Dit adres heeft al een Predict-account'; end if;
  update public.invitations set status='revoked' where email=e and pool_id is null and status='pending';
  token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.invitations(email,token_hash,invited_by,expires_at)
    values(e,encode(extensions.digest(token,'sha256'),'hex'),u,clock_timestamp()+interval '7 days');
  return token;
end $$;

create function predict_private.revoke_account_invitations(p_email text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin')) then
    raise exception 'Geen beheerdersrechten' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('account-email:'||lower(btrim(p_email)),0));
  update public.invitations set status='revoked' where pool_id is null and email=lower(btrim(p_email)) and status='pending';
end $$;

-- Service-only capability check. Reserve the mail budget atomically before contacting Auth.
create function public.reserve_account_invitation_mail(p_token text,p_email text) returns text
language plpgsql security invoker set search_path='' as $$
declare i public.invitations%rowtype;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
  select * into i from public.invitations where pool_id is null and email=lower(btrim(p_email))
    and token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
  if not found or i.status<>'pending' or i.expires_at<=clock_timestamp() or i.account_mail_attempts>=5
    or i.account_mail_requested_at>clock_timestamp()-interval '60 seconds' then return null; end if;
  update public.invitations set account_mail_requested_at=clock_timestamp(),account_mail_attempts=account_mail_attempts+1 where id=i.id;
  return i.email;
end $$;
revoke all on function public.reserve_account_invitation_mail(text,text) from public,anon,authenticated;
grant execute on function public.reserve_account_invitation_mail(text,text) to service_role;

create function predict_private.complete_account_invitation() returns void
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); e text; i uuid;
begin
  select lower(btrim(email)) into e from auth.users where id=u and email_confirmed_at is not null;
  if u is null or e is null then raise exception 'Bevestig eerst je e-mailadres' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('account-email:'||e,0));
  -- Retry after success is safe; never change an existing role/profile.
  if exists(select 1 from public.profiles where id=u) and exists(select 1 from public.user_roles where user_id=u) then return; end if;
  select id into i from public.invitations where pool_id is null and email=e and status='pending'
    and expires_at>clock_timestamp() and account_mail_requested_at is not null order by created_at desc limit 1 for update;
  if i is null then raise exception 'Accountuitnodiging ongeldig of verlopen' using errcode='42501'; end if;
  insert into public.profiles(id,username,display_name) values(u,'speler-'||replace(u::text,'-',''),'Nieuwe speler') on conflict(id) do nothing;
  insert into public.user_roles(user_id,role) values(u,'user') on conflict(user_id) do nothing;
  update public.invitations set status='accepted',accepted_by=u,accepted_at=clock_timestamp() where id=i;
end $$;

create function public.create_account_invitation(p_email text) returns text language sql security invoker set search_path='' as $$ select predict_private.create_account_invitation(p_email); $$;
create function public.revoke_account_invitations(p_email text) returns void language sql security invoker set search_path='' as $$ select predict_private.revoke_account_invitations(p_email); $$;
create function public.complete_account_invitation() returns void language sql security invoker set search_path='' as $$ select predict_private.complete_account_invitation(); $$;
revoke all on function predict_private.create_account_invitation(text),predict_private.revoke_account_invitations(text),predict_private.complete_account_invitation(),public.create_account_invitation(text),public.revoke_account_invitations(text),public.complete_account_invitation() from public,anon;
grant execute on function predict_private.create_account_invitation(text),predict_private.revoke_account_invitations(text),predict_private.complete_account_invitation(),public.create_account_invitation(text),public.revoke_account_invitations(text),public.complete_account_invitation() to authenticated;
