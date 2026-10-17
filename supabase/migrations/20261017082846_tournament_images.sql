-- Public tournament illustrations; only existing administrators may manage files.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('tournament-images','tournament-images',true,2097152,array['image/webp'])
on conflict(id) do nothing;
create function predict_branding.can_manage_tournament_image(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin'))
 and exists(select 1 from public.tournaments where id::text || '/cover.webp'=p_name);
$$;
revoke all on function predict_branding.can_manage_tournament_image(text) from public,anon,authenticated;
grant execute on function predict_branding.can_manage_tournament_image(text) to authenticated;
create policy tournament_image_read_admin on storage.objects for select to authenticated using(bucket_id='tournament-images' and predict_branding.can_manage_tournament_image(name));
create policy tournament_image_insert_admin on storage.objects for insert to authenticated with check(bucket_id='tournament-images' and predict_branding.can_manage_tournament_image(name));
create policy tournament_image_update_admin on storage.objects for update to authenticated using(bucket_id='tournament-images' and predict_branding.can_manage_tournament_image(name)) with check(bucket_id='tournament-images' and predict_branding.can_manage_tournament_image(name));
create policy tournament_image_delete_admin on storage.objects for delete to authenticated using(bucket_id='tournament-images' and predict_branding.can_manage_tournament_image(name));
