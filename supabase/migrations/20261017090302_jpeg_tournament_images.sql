-- JPEG canvas encoding is supported on Safari, including browsers without WebP encoding.
update storage.buckets set allowed_mime_types=array['image/jpeg','image/webp'] where id='tournament-images';
create or replace function predict_branding.can_manage_tournament_image(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin'))
 and exists(select 1 from public.tournaments where p_name in(id::text || '/cover.jpg',id::text || '/cover.webp'));
$$;
revoke all on function predict_branding.can_manage_tournament_image(text) from public,anon,authenticated;
grant execute on function predict_branding.can_manage_tournament_image(text) to authenticated;
