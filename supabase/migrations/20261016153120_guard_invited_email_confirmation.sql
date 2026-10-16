-- Gate first email confirmation in the same Auth transaction that issues a session.
-- A native Auth invite token must not outlive the application's invitation authority.
create function predict_private.guard_invited_email_confirmation() returns trigger
language plpgsql security definer set search_path='' as $$
declare e text:=lower(btrim(new.email)); i uuid;
begin
  -- Existing provisioned accounts retain their normal confirmation/recovery behavior.
  if exists(select 1 from public.profiles where id=new.id)
    and exists(select 1 from public.user_roles where user_id=new.id) then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('account-email:'||e,0));
  select id into i from public.invitations where pool_id is null and email=e and status='pending'
    and expires_at>clock_timestamp() and account_mail_requested_at is not null
    order by created_at desc limit 1 for update;
  if i is null then raise exception 'Account invitation invalid or expired' using errcode='42501'; end if;
  insert into public.profiles(id,username,display_name)
    values(new.id,'speler-'||replace(new.id::text,'-',''),'Nieuwe speler') on conflict(id) do nothing;
  insert into public.user_roles(user_id,role) values(new.id,'user') on conflict(user_id) do nothing;
  update public.invitations set status='accepted',accepted_by=new.id,accepted_at=clock_timestamp() where id=i;
  return new;
end $$;
revoke all on function predict_private.guard_invited_email_confirmation() from public,anon,authenticated;
create trigger predict_guard_invited_email_confirmation
after update of email_confirmed_at on auth.users for each row
when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
execute function predict_private.guard_invited_email_confirmation();
