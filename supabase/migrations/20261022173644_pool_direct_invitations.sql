-- Account-bound pool invitations; privileged code stays outside the exposed schema.
alter table public.invitations add column recipient_id uuid references auth.users(id) on delete cascade;
update public.invitations i set recipient_id=u.id from auth.users u
where i.pool_id is not null and i.status='pending' and lower(btrim(u.email))=i.email;
create index invitations_recipient_pending_idx on public.invitations(recipient_id,pool_id) where status='pending';

create function predict_private.search_pool_users(p_pool_id uuid,p_query text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.pools where id=p_pool_id and owner_id=auth.uid()) then
 raise exception 'Alleen de poulebeheerder kan gebruikers zoeken' using errcode='42501'; end if;
 if length(btrim(coalesce(p_query,'')))<3 then return '[]'::jsonb; end if;
 return (select coalesce(jsonb_agg(to_jsonb(s)),'[]') from (
 select p.id as user_id,p.username from public.profiles p join auth.users u on u.id=p.id
 where position(lower(btrim(p_query)) in lower(p.username))>0 and u.deleted_at is null
 and not exists(select 1 from public.pool_members m where m.pool_id=p_pool_id and m.user_id=p.id)
 and not exists(select 1 from public.invitations i where i.pool_id=p_pool_id and i.recipient_id=p.id and i.status='pending' and i.expires_at>now())
 order by lower(p.username),p.id limit 3) s);
end $$;

create function predict_private.send_pool_invitation(p_pool_id uuid,p_user_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); mail text; result uuid;
begin
 if uid is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
 perform 1 from public.pools p join public.tournaments t on t.id=p.tournament_id
 where p.id=p_pool_id and p.owner_id=uid and t.status in ('published','active') for update of p;
 if not found then raise exception 'Alleen de poulebeheerder kan uitnodigen voor een beschikbaar toernooi' using errcode='42501'; end if;
 select lower(btrim(u.email)) into mail from public.profiles p join auth.users u on u.id=p.id where p.id=p_user_id and u.deleted_at is null;
 if mail is null then raise exception 'Selecteer een bestaande gebruiker'; end if;
 if exists(select 1 from public.pool_members where pool_id=p_pool_id and user_id=p_user_id) then raise exception 'Deze gebruiker is al lid'; end if;
 if exists(select 1 from public.invitations where pool_id=p_pool_id and recipient_id=p_user_id and status='pending' and expires_at>clock_timestamp()) then raise exception 'Deze gebruiker is al uitgenodigd'; end if;
 update public.invitations set status='revoked' where pool_id=p_pool_id and recipient_id=p_user_id and status='pending';
 insert into public.invitations(token_hash,email,invited_by,pool_id,recipient_id,expires_at)
 values(encode(extensions.digest(extensions.gen_random_bytes(32),'sha256'),'hex'),mail,uid,p_pool_id,p_user_id,clock_timestamp()+interval '7 days') returning id into result;
 return result;
end $$;

create function predict_private.get_my_pool_invitations() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(s)),'[]') from (
 select i.id,p.id as pool_id,p.name as pool_name,t.id as tournament_id,t.name as tournament_name,i.expires_at
 from public.invitations i join public.pools p on p.id=i.pool_id join public.tournaments t on t.id=p.tournament_id
 where i.recipient_id=auth.uid() and i.status='pending' and i.expires_at>now() and t.status in ('published','active')
 and not exists(select 1 from public.pool_members m where m.pool_id=p.id and m.user_id=auth.uid())
 order by i.created_at desc) s);
end $$;

create function predict_private.respond_pool_invitation(p_invitation_id uuid,p_accept boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); inv public.invitations%rowtype; pool public.pools%rowtype;
begin
 if uid is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
 select * into inv from public.invitations where id=p_invitation_id and recipient_id=uid and pool_id is not null;
 if not found then raise exception 'Uitnodiging ongeldig of verlopen' using errcode='42501'; end if;
 select * into pool from public.pools where id=inv.pool_id for update;
 if not found then raise exception 'Poule bestaat niet meer'; end if;
 select * into inv from public.invitations where id=p_invitation_id for update;
 if inv.recipient_id<>uid or inv.status<>'pending' or inv.expires_at<=clock_timestamp() then raise exception 'Uitnodiging ongeldig of verlopen'; end if;
 if p_accept is null then raise exception 'Kies accepteren of weigeren'; end if;
 if p_accept then
  if not exists(select 1 from public.tournaments where id=pool.tournament_id and status in ('published','active')) then raise exception 'Toernooi niet beschikbaar'; end if;
  insert into public.tournament_entries(tournament_id,user_id) values(pool.tournament_id,uid) on conflict do nothing;
  insert into public.pool_members(pool_id,user_id) values(pool.id,uid) on conflict do nothing;
  update public.invitations set status='accepted',accepted_by=uid,accepted_at=clock_timestamp() where id=inv.id;
 else
  update public.invitations set status='revoked' where id=inv.id;
 end if;
 return pool.id;
end $$;

create function predict_private.delete_pool(p_pool_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); owner uuid;
begin
 if uid is null then raise exception 'Inloggen vereist' using errcode='42501'; end if;
 select owner_id into owner from public.pools where id=p_pool_id for update;
 if not found then raise exception 'Poule bestaat niet meer'; end if;
 if owner<>uid and not exists(select 1 from public.user_roles where user_id=uid and role in ('admin','super_admin')) then
 raise exception 'Alleen de poulebeheerder of een beheerder kan deze poule verwijderen' using errcode='42501'; end if;
 delete from public.pools where id=p_pool_id;
end $$;

create function public.search_pool_users(p_pool_id uuid,p_query text) returns jsonb language sql security invoker set search_path='' as $$select predict_private.search_pool_users(p_pool_id,p_query)$$;
create function public.send_pool_invitation(p_pool_id uuid,p_user_id uuid) returns uuid language sql security invoker set search_path='' as $$select predict_private.send_pool_invitation(p_pool_id,p_user_id)$$;
create function public.get_my_pool_invitations() returns jsonb language sql security invoker set search_path='' as $$select predict_private.get_my_pool_invitations()$$;
create function public.respond_pool_invitation(p_invitation_id uuid,p_accept boolean) returns uuid language sql security invoker set search_path='' as $$select predict_private.respond_pool_invitation(p_invitation_id,p_accept)$$;
create function public.delete_pool(p_pool_id uuid) returns void language sql security invoker set search_path='' as $$select predict_private.delete_pool(p_pool_id)$$;
revoke all on function public.search_pool_users(uuid,text),public.send_pool_invitation(uuid,uuid),public.get_my_pool_invitations(),public.respond_pool_invitation(uuid,boolean),public.delete_pool(uuid),predict_private.search_pool_users(uuid,text),predict_private.send_pool_invitation(uuid,uuid),predict_private.get_my_pool_invitations(),predict_private.respond_pool_invitation(uuid,boolean),predict_private.delete_pool(uuid) from public,anon,authenticated;
grant execute on function public.search_pool_users(uuid,text),public.send_pool_invitation(uuid,uuid),public.get_my_pool_invitations(),public.respond_pool_invitation(uuid,boolean),public.delete_pool(uuid),predict_private.search_pool_users(uuid,text),predict_private.send_pool_invitation(uuid,uuid),predict_private.get_my_pool_invitations(),predict_private.respond_pool_invitation(uuid,boolean),predict_private.delete_pool(uuid) to authenticated;
-- Existing account-invitation flows remain intact; pool codes can no longer be created.
revoke execute on function public.invite_pool_member(uuid,text),predict_private.invite_pool_member(uuid,text),predict_private.invite_pool_member_email(uuid,text) from authenticated;
notify pgrst,'reload schema';
