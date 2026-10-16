begin;
do $$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); result jsonb; bad text; t uuid;
begin
  insert into auth.users(id,email,email_confirmed_at,aud,role) values
    (a,a||'@predict-profile-qa.invalid',now(),'authenticated','authenticated'),
    (b,b||'@predict-profile-qa.invalid',now(),'authenticated','authenticated');
  insert into public.profiles(id,username,display_name,theme) values(a,a::text,'QA oud','system'),(b,b::text,'QA ander','light');
  insert into public.user_roles(user_id,role) values(a,'user'),(b,'user');
  select id into strict t from public.tournaments where name='Predict QA - dartstest';
  insert into public.tournament_entries(tournament_id,user_id) values(t,a);
  perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
  if exists(select 1 from public.profiles where id=b) then raise exception 'FAIL: other profile visible'; end if;
  begin
    update public.profiles set display_name='Ongeoorloofd' where id=a;
    raise exception 'FAIL: direct profile update';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.profiles where id=a;
    raise exception 'FAIL: direct profile delete';
  exception when insufficient_privilege then null; end;
  result:=public.update_my_profile('  QA nieuwe naam  ','dark');
  if result->>'display_name'<>'QA nieuwe naam' or result->>'theme'<>'dark' then raise exception 'FAIL: profile normalization'; end if;
  result:=public.update_my_profile(p_theme=>'system');
  if result->>'display_name'<>'QA nieuwe naam' or result->>'theme'<>'system' then raise exception 'FAIL: partial theme update'; end if;
  result:=public.update_my_profile(p_display_name=>'QA definitief');
  if result->>'theme'<>'system' then raise exception 'FAIL: partial name changed theme'; end if;
  if not exists(select 1 from public.get_tournament_leaderboard(t,null,null) where user_id=a and display_name='QA definitief') then
    raise exception 'FAIL: leaderboard name not updated'; end if;
  if (select username from public.profiles where id=a)<>a::text then raise exception 'FAIL: username changed'; end if;
  if (select role from public.user_roles where user_id=a)<>'user' then raise exception 'FAIL: role changed'; end if;
  foreach bad in array array['','   ',repeat('x',41),E'QA\nnaam'] loop
    begin
      perform public.update_my_profile(bad,null);
      raise exception 'FAIL: invalid display name accepted';
    exception when others then if sqlerrm not like '%weergavenaam van 1 tot 40%' then raise; end if; end;
  end loop;
  begin
    perform public.update_my_profile(null,'admin');
    raise exception 'FAIL: invalid theme';
  exception when others then if sqlerrm<>'Ongeldig thema' then raise; end if; end;
  begin
    perform public.update_my_profile();
    raise exception 'FAIL: empty update';
  exception when others then if sqlerrm<>'Geen profielwijziging opgegeven' then raise; end if; end;
  perform set_config('request.jwt.claim.sub',b::text,true);
  if (select display_name from public.profiles where id=b)<>'QA ander' then raise exception 'FAIL: another profile changed'; end if;
  perform set_config('role','anon',true);
  begin
    perform public.update_my_profile('Anoniem','dark');
    raise exception 'FAIL: anonymous update';
  exception when insufficient_privilege then null; end;
  begin
    perform username from public.profiles;
    raise exception 'FAIL: anonymous profile read';
  exception when insufficient_privilege then null; end;
  perform set_config('role','authenticated',true);perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.update_my_profile('Zonder identiteit','dark');
    raise exception 'FAIL: unauthenticated helper';
  exception when insufficient_privilege then null; end;
  perform set_config('role','postgres',true);
end;
$$;
rollback;
select 'PASS: own profile updates only, validation, partial updates, leaderboard names, identity/role preservation, no anonymous access; rolled back' as result;
