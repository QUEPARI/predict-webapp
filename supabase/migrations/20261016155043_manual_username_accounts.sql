-- Mail-free accounts still use Supabase Auth for password hashing and sessions.
create unique index profiles_username_casefold_key on public.profiles(lower(username));
create table predict_private.manual_account_codes(
  id uuid primary key default gen_random_uuid(), username text not null,
  user_id uuid not null, kind text not null check(kind in ('activate','reset')),
  token_hash text unique not null, issued_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
  revoked_at timestamptz, claimed_at timestamptz, completed_at timestamptz
);
alter table predict_private.manual_account_codes enable row level security;
revoke all on predict_private.manual_account_codes from public,anon,authenticated;
create index manual_account_codes_username on predict_private.manual_account_codes(username);
create table predict_private.auth_attempt_budgets(key text primary key, window_start timestamptz not null, attempts integer not null);
alter table predict_private.auth_attempt_budgets enable row level security;
revoke all on predict_private.auth_attempt_budgets from public,anon,authenticated;

create function predict_private.issue_manual_account_code(p_username text,p_kind text) returns text
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); name text:=lower(btrim(p_username)); target uuid; token text;
begin
  if u is null or not exists(select 1 from public.user_roles where user_id=u and role in ('admin','super_admin')) then
    raise exception 'Alleen systeembeheerders kunnen accountcodes maken' using errcode='42501'; end if;
  if p_kind is null or p_kind not in ('activate','reset') or name is null or length(name) not between 1 and 128 then raise exception 'Ongeldige aanvraag';end if;
  perform pg_advisory_xact_lock(hashtextextended('manual-admin:'||u,0));
  perform pg_advisory_xact_lock(hashtextextended('manual-user:'||name,0));
  if exists(select 1 from predict_private.manual_account_codes where username=name and claimed_at>clock_timestamp()-interval '5 minutes' and completed_at is null) then
    raise exception 'Een code wordt verwerkt. Probeer over vijf minuten opnieuw';end if;
  if (select count(*) from predict_private.manual_account_codes where issued_by=u and created_at>clock_timestamp()-interval '24 hours')>=20 then
    raise exception 'Maximaal twintig accountcodes per 24 uur';end if;
  select id into target from public.profiles where lower(username)=name;
  if p_kind='activate' then
    if name !~ '^[a-z0-9][a-z0-9_-]{2,31}$' then raise exception 'Gebruik 3–32 letters, cijfers, streepjes of underscores';end if;
    if target is not null then raise exception 'Deze gebruikersnaam is al in gebruik';end if;
    target:=gen_random_uuid();
  elsif target is null then raise exception 'Gebruikersnaam niet gevonden';
  elsif exists(select 1 from public.user_roles where user_id=target and role in ('admin','super_admin')) and target<>u then
    -- Ordinary system admins must not take over other system admins through recovery.
    raise exception 'Herstel van een andere beheerder vereist afzonderlijk beheer' using errcode='42501';
  end if;
  update predict_private.manual_account_codes set revoked_at=clock_timestamp() where username=name and completed_at is null and revoked_at is null and claimed_at is null;
  token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into predict_private.manual_account_codes(username,user_id,kind,token_hash,issued_by,expires_at)
    values(name,target,p_kind,encode(extensions.digest(token,'sha256'),'hex'),u,
      clock_timestamp()+case when p_kind='activate' then interval '7 days' else interval '1 hour' end);
  return token;
end $$;
create function predict_private.revoke_manual_account_codes(p_username text) returns void
language plpgsql security definer set search_path='' as $$
declare name text:=lower(btrim(p_username));
begin
  if auth.uid() is null or not exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin')) then
    raise exception 'Geen beheerdersrechten' using errcode='42501';end if;
  perform pg_advisory_xact_lock(hashtextextended('manual-user:'||name,0));
  update predict_private.manual_account_codes set revoked_at=clock_timestamp() where username=name and completed_at is null and revoked_at is null and claimed_at is null;
end $$;
create function public.issue_manual_account_code(p_username text,p_kind text) returns text language sql security invoker set search_path='' as $$ select predict_private.issue_manual_account_code(p_username,p_kind); $$;
create function public.revoke_manual_account_codes(p_username text) returns void language sql security invoker set search_path='' as $$ select predict_private.revoke_manual_account_codes(p_username); $$;
revoke all on function predict_private.issue_manual_account_code(text,text),predict_private.revoke_manual_account_codes(text),public.issue_manual_account_code(text,text),public.revoke_manual_account_codes(text) from public,anon;
grant execute on function predict_private.issue_manual_account_code(text,text),predict_private.revoke_manual_account_codes(text),public.issue_manual_account_code(text,text),public.revoke_manual_account_codes(text) to authenticated;

-- Only backend code can resolve names or consume codes. No browser name/email directory.
create function predict_private.take_auth_budget(p_key text,p_limit integer) returns boolean
language plpgsql security definer set search_path='' as $$
declare used integer;
begin
  delete from predict_private.auth_attempt_budgets where window_start<clock_timestamp()-interval '1 day';
  insert into predict_private.auth_attempt_budgets values(p_key,clock_timestamp(),1)
  on conflict(key) do update set
    attempts=case when auth_attempt_budgets.window_start<clock_timestamp()-interval '15 minutes' then 1 else auth_attempt_budgets.attempts+1 end,
    window_start=case when auth_attempt_budgets.window_start<clock_timestamp()-interval '15 minutes' then clock_timestamp() else auth_attempt_budgets.window_start end
  returning attempts into used;
  return used<=p_limit;
end $$;
revoke all on function predict_private.take_auth_budget(text,integer) from public,anon,authenticated;

create function public.resolve_username_login(p_username text) returns text
language plpgsql security definer set search_path='' as $$
declare name text:=lower(btrim(p_username)); e text;
begin
  if name is null or length(name) not between 1 and 128 then return null;end if;
  if not predict_private.take_auth_budget('global-login',1000) then return null;end if;
  if not predict_private.take_auth_budget('login:'||encode(extensions.digest(name,'sha256'),'hex'),20) then return null;end if;
  select a.email into e from public.profiles p join auth.users a on a.id=p.id where lower(p.username)=name and a.email_confirmed_at is not null;
  return e;
end $$;
create function public.claim_manual_account_code(p_username text,p_kind text,p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare name text:=lower(btrim(p_username)); c predict_private.manual_account_codes%rowtype; e text;
begin
  if name is null or length(name) not between 1 and 128 or p_token is null or p_token !~ '^[0-9a-f]{64}$' or p_kind not in ('activate','reset') then return null;end if;
  if not predict_private.take_auth_budget('global-codes',1000) then return null;end if;
  if not predict_private.take_auth_budget('code:'||encode(extensions.digest(name,'sha256'),'hex'),20) then return null;end if;
  perform pg_advisory_xact_lock(hashtextextended('manual-user:'||name,0));
  select * into c from predict_private.manual_account_codes where username=name and kind=p_kind and token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
  if not found or c.revoked_at is not null or c.claimed_at is not null or c.expires_at<=clock_timestamp() then return null;end if;
  if p_kind='activate' then
    if exists(select 1 from public.profiles where lower(username)=name) then return null;end if;
    e:=c.user_id::text||'@accounts.predict.invalid';
  else
    select a.email into e from auth.users a join public.profiles p on p.id=a.id where a.id=c.user_id and lower(p.username)=name;
    if e is null then return null;end if;
  end if;
  -- Fail closed across the external Auth API call. On failure an admin issues a fresh code.
  update predict_private.manual_account_codes set claimed_at=clock_timestamp() where id=c.id;
  return jsonb_build_object('code_id',c.id,'user_id',c.user_id,'username',name,'email',e);
end $$;
create function predict_private.provision_manual_account() returns trigger
language plpgsql security definer set search_path='' as $$
declare c predict_private.manual_account_codes%rowtype;
begin
  if new.email<>new.id::text||'@accounts.predict.invalid' then return new;end if;
  select * into c from predict_private.manual_account_codes where user_id=new.id and kind='activate'
    and claimed_at>clock_timestamp()-interval '5 minutes' and revoked_at is null and completed_at is null
    and expires_at>clock_timestamp();
  if not found then raise exception 'Activatiecode ongeldig' using errcode='42501';end if;
  perform pg_advisory_xact_lock(hashtextextended('manual-user:'||c.username,0));
  select * into c from predict_private.manual_account_codes where id=c.id and revoked_at is null and completed_at is null and expires_at>clock_timestamp() for update;
  if not found then raise exception 'Activatiecode ongeldig' using errcode='42501';end if;
  insert into public.profiles(id,username,display_name) values(new.id,c.username,c.username);
  insert into public.user_roles(user_id,role) values(new.id,'user');
  update predict_private.manual_account_codes set completed_at=clock_timestamp() where id=c.id;
  return new;
end $$;
revoke all on function predict_private.provision_manual_account() from public,anon,authenticated;
create trigger predict_provision_manual_account after insert on auth.users for each row execute function predict_private.provision_manual_account();

create function public.complete_manual_password_reset(p_code_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c predict_private.manual_account_codes%rowtype;
begin
  select * into c from predict_private.manual_account_codes where id=p_code_id and kind='reset' for update;
  if not found or c.claimed_at is null or c.claimed_at<clock_timestamp()-interval '5 minutes' or c.revoked_at is not null or c.completed_at is not null then
    raise exception 'Herstelcode ongeldig' using errcode='42501';end if;
  -- Refresh tokens cascade from sessions. Existing access JWTs keep their normal expiry.
  delete from auth.sessions where user_id=c.user_id;
  update predict_private.manual_account_codes set completed_at=clock_timestamp() where id=c.id;
end $$;
revoke all on function public.resolve_username_login(text),public.claim_manual_account_code(text,text,text),public.complete_manual_password_reset(uuid) from public,anon,authenticated;
grant execute on function public.resolve_username_login(text),public.claim_manual_account_code(text,text,text),public.complete_manual_password_reset(uuid) to service_role;

-- The existing email-bound pool authorization remains authoritative. Resolve a username
-- on the server so mail-free users can be invited without exposing internal Auth addresses.
alter function predict_private.invite_pool_member(uuid,text) rename to invite_pool_member_email;
create function predict_private.invite_pool_member(p_pool_id uuid,p_email text) returns text
language plpgsql security definer set search_path='' as $$
declare e text:=p_email;
begin
  if position('@' in e)=0 then
    select a.email into e from auth.users a join public.profiles p on p.id=a.id where lower(p.username)=lower(btrim(p_email));
    if e is null then raise exception 'Gebruiker niet beschikbaar';end if;
  end if;
  return predict_private.invite_pool_member_email(p_pool_id,e);
end $$;
revoke all on function predict_private.invite_pool_member(uuid,text) from public,anon;
grant execute on function predict_private.invite_pool_member(uuid,text) to authenticated;
