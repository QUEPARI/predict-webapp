-- Hosted verification: metadata only, rolled back; no physical uploads or sport changes.
begin;
do $$ begin
 if not exists(select 1 from storage.buckets where id='tournament-images' and public and file_size_limit=2097152 and allowed_mime_types @> array['image/jpeg','image/webp']) then raise exception 'Bucket configuratie onjuist'; end if;
end $$;
select set_config('qa.image_path',(select id::text || '/cover.jpg' from public.tournaments order by id limit 1),true);
select set_config('request.jwt.claim.sub',(select user_id::text from public.user_roles where role='super_admin' limit 1),true);
set local role authenticated;
do $$ begin
 if not predict_branding.can_manage_tournament_image(current_setting('qa.image_path')) then raise exception 'Admin geweigerd';end if;
 if predict_branding.can_manage_tournament_image('../cover.jpg') or predict_branding.can_manage_tournament_image('00000000-0000-0000-0000-000000000000/cover.jpg') then raise exception 'Ongeldig pad toegestaan';end if;
 insert into storage.objects(bucket_id,name,metadata) values('tournament-images',current_setting('qa.image_path'),'{"mimetype":"image/jpeg"}');
 update storage.objects set metadata='{"mimetype":"image/jpeg","size":123}' where bucket_id='tournament-images' and name=current_setting('qa.image_path');if not found then raise exception 'Vervangen geweigerd';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
do $$ begin
 if predict_branding.can_manage_tournament_image(current_setting('qa.image_path')) then raise exception 'Gewone gebruiker toegestaan';end if;
 if exists(select 1 from storage.objects where bucket_id='tournament-images') then raise exception 'Gewone gebruiker kan metadata lezen';end if;
 begin insert into storage.objects(bucket_id,name) values('tournament-images',current_setting('qa.image_path'));raise exception 'Upload gebruiker toegestaan';exception when insufficient_privilege then null;end;
end $$;
set local role anon;
do $$ begin
 begin perform predict_branding.can_manage_tournament_image(current_setting('qa.image_path'));raise exception 'Anonieme helper toegestaan';exception when insufficient_privilege then null;end;
 begin insert into storage.objects(bucket_id,name) values('tournament-images',current_setting('qa.image_path'));raise exception 'Anonieme upload toegestaan';exception when insufficient_privilege then null;end;
end $$;
rollback;
