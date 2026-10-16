-- Incremental migration against the existing hosted schema, NOT schema.sql.
-- Privileged implementations are private; exposed RPCs use invoker rights.
create schema if not exists predict_private;
revoke all on schema predict_private from public, anon;
grant usage on schema predict_private to authenticated;

create function predict_private.can_read_pool(p_pool_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (
    exists(select 1 from public.pool_members m where m.pool_id=p_pool_id and m.user_id=auth.uid())
    or exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.role in ('admin','super_admin'))
  );
$$;
revoke all on function predict_private.can_read_pool(uuid) from public, anon;
grant execute on function predict_private.can_read_pool(uuid) to authenticated;

alter table public.pools enable row level security;
alter table public.pool_members enable row level security;
alter table public.invitations enable row level security;
revoke all on public.pools, public.pool_members, public.invitations from public, anon, authenticated;
grant select on public.pools, public.pool_members to authenticated;
-- Invitation hashes and email addresses are not available through table reads.
create policy pools_read_member on public.pools for select to authenticated
using (predict_private.can_read_pool(id));
create policy pool_members_read_member on public.pool_members for select to authenticated
using (predict_private.can_read_pool(pool_id));
create index if not exists pool_members_user_pool_idx on public.pool_members(user_id,pool_id);
create index if not exists pools_tournament_idx on public.pools(tournament_id);

create function predict_private.create_pool(p_tournament_id uuid,p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
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
$$;

create function predict_private.invite_pool_member(p_pool_id uuid,p_email text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_token text; v_email text:=lower(btrim(p_email));
begin
  if v_uid is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
  perform 1 from public.pools where id=p_pool_id and owner_id=v_uid for update;
  if not found then raise exception 'Alleen de poulebeheerder kan uitnodigen' using errcode='42501'; end if;
  if not exists(select 1 from public.pools p join public.tournaments t on t.id=p.tournament_id
    where p.id=p_pool_id and t.status in ('published','active')) then raise exception 'Toernooi niet beschikbaar'; end if;
  if v_email is null or length(v_email) not between 3 and 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Vul een geldig e-mailadres in'; end if;
  -- Replacement invitation invalidates earlier pending codes for this recipient.
  update public.invitations set status='revoked' where pool_id=p_pool_id and email=v_email and status='pending';
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.invitations(token_hash,email,invited_by,pool_id,expires_at)
    values(encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_uid,p_pool_id,clock_timestamp()+interval '7 days');
  return v_token;
end;
$$;

create function predict_private.accept_pool_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_inv public.invitations%rowtype; v_pool public.pools%rowtype; v_email text;
begin
  if v_uid is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then raise exception 'Uitnodiging ongeldig of verlopen'; end if;
  select * into v_inv from public.invitations where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and pool_id is not null;
  if not found then raise exception 'Uitnodiging ongeldig of verlopen'; end if;
  -- All membership operations lock the pool first, then the invitation.
  select * into v_pool from public.pools where id=v_inv.pool_id for update;
  if not found then raise exception 'Uitnodiging ongeldig of verlopen'; end if;
  select * into v_inv from public.invitations where id=v_inv.id for update;
  select lower(btrim(email)) into v_email from auth.users where id=v_uid and email_confirmed_at is not null;
  if v_inv.status<>'pending' or v_inv.expires_at<=clock_timestamp()
    or v_email is null or v_email<>v_inv.email then raise exception 'Uitnodiging ongeldig of verlopen'; end if;
  if not exists(select 1 from public.tournaments where id=v_pool.tournament_id and status in ('published','active')) then
    raise exception 'Toernooi niet beschikbaar'; end if;
  insert into public.tournament_entries(tournament_id,user_id) values(v_pool.tournament_id,v_uid) on conflict do nothing;
  insert into public.pool_members(pool_id,user_id) values(v_pool.id,v_uid) on conflict do nothing;
  update public.invitations set status='accepted',accepted_by=v_uid,accepted_at=clock_timestamp() where id=v_inv.id;
  return v_pool.id;
end;
$$;

create function predict_private.manage_pool_member(p_pool_id uuid,p_user_id uuid,p_action text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_pool public.pools%rowtype;
begin
  if v_uid is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
  select * into v_pool from public.pools where id=p_pool_id for update;
  if not found then raise exception 'Geen toegang tot deze poule' using errcode='42501'; end if;
  if p_action='leave' then
    if v_uid=v_pool.owner_id then raise exception 'Draag eerst het poulebeheer over'; end if;
    delete from public.pool_members where pool_id=p_pool_id and user_id=v_uid;
  elsif p_action in ('remove','transfer','revoke') then
    if v_uid<>v_pool.owner_id then raise exception 'Alleen de poulebeheerder mag dit doen' using errcode='42501'; end if;
    if p_action='revoke' then
      update public.invitations set status='revoked' where pool_id=p_pool_id and status='pending';
    else
      if p_user_id is null or not exists(select 1 from public.pool_members where pool_id=p_pool_id and user_id=p_user_id) then
        raise exception 'Lid niet gevonden'; end if;
      if p_action='transfer' then
        update public.pools set owner_id=p_user_id where id=p_pool_id;
        -- The former owner must no longer have outstanding invitations.
        update public.invitations set status='revoked' where pool_id=p_pool_id and status='pending';
      else
        if p_user_id=v_pool.owner_id then raise exception 'De poulebeheerder kan niet worden verwijderd'; end if;
        delete from public.pool_members where pool_id=p_pool_id and user_id=p_user_id;
        update public.invitations set status='revoked' where pool_id=p_pool_id and status='pending'
          and email=(select lower(btrim(email)) from auth.users where id=p_user_id);
      end if;
    end if;
  else raise exception 'Onbekende handeling'; end if;
end;
$$;

create function public.create_pool(p_tournament_id uuid,p_name text) returns uuid
language sql security invoker set search_path='' as $$ select predict_private.create_pool(p_tournament_id,p_name); $$;
create function public.invite_pool_member(p_pool_id uuid,p_email text) returns text
language sql security invoker set search_path='' as $$ select predict_private.invite_pool_member(p_pool_id,p_email); $$;
create function public.accept_pool_invitation(p_token text) returns uuid
language sql security invoker set search_path='' as $$ select predict_private.accept_pool_invitation(p_token); $$;
create function public.manage_pool_member(p_pool_id uuid,p_user_id uuid,p_action text) returns void
language sql security invoker set search_path='' as $$ select predict_private.manage_pool_member(p_pool_id,p_user_id,p_action); $$;

revoke all on function predict_private.create_pool(uuid,text), predict_private.invite_pool_member(uuid,text),
  predict_private.accept_pool_invitation(text), predict_private.manage_pool_member(uuid,uuid,text) from public,anon;
grant execute on function predict_private.create_pool(uuid,text), predict_private.invite_pool_member(uuid,text),
  predict_private.accept_pool_invitation(text), predict_private.manage_pool_member(uuid,uuid,text) to authenticated;
revoke all on function public.create_pool(uuid,text), public.invite_pool_member(uuid,text),
  public.accept_pool_invitation(text), public.manage_pool_member(uuid,uuid,text) from public,anon;
grant execute on function public.create_pool(uuid,text), public.invite_pool_member(uuid,text),
  public.accept_pool_invitation(text), public.manage_pool_member(uuid,uuid,text) to authenticated;

notify pgrst,'reload schema';
