-- Run as postgres through an authorized SQL session. Everything is rolled back.
-- No passwords, real accounts, official fixtures or persistent QA rows.
begin;
do $$
declare
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  t uuid; r uuid; pool uuid; token text; old_token text; fixture uuid:=gen_random_uuid();
  n bigint; before_points bigint; after_points bigint;
begin
  select id into strict t from public.tournaments where name='Predict QA - dartstest' and status in ('published','active');
  select id into r from public.tournament_rounds where tournament_id=t order by round_order limit 1;
  if r is null then raise exception 'FAIL: QA round missing'; end if;
  insert into auth.users(id,email,email_confirmed_at,aud,role) values
    (a,a||'@predict-qa.invalid',now(),'authenticated','authenticated'),
    (b,b||'@predict-qa.invalid',now(),'authenticated','authenticated'),
    (outsider,outsider||'@predict-qa.invalid',now(),'authenticated','authenticated');
  insert into public.profiles(id,username,display_name) values(a,a::text,'QA eigenaar'),(b,b::text,'QA lid'),(outsider,outsider::text,'QA buitenstaander');
  insert into public.user_roles(user_id,role) values(a,'user'),(b,'user'),(outsider,'user');
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('role','authenticated',true);
  pool:=public.create_pool(t,'QA tijdelijke privépoule');
  if (select count(*) from public.pool_members where pool_id=pool)<>1 then raise exception 'FAIL: owner membership'; end if;
  if not exists(select 1 from public.tournament_entries where tournament_id=t and user_id=a) then raise exception 'FAIL: owner entry'; end if;
  begin
    insert into public.pool_members(pool_id,user_id) values(pool,b);
    raise exception 'FAIL: direct member insertion allowed';
  exception when insufficient_privilege then null; end;
  begin
    update public.pools set owner_id=b where id=pool;
    raise exception 'FAIL: direct ownership update allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform token_hash from public.invitations;
    raise exception 'FAIL: invitation hashes readable';
  exception when insufficient_privilege then null; end;
  token:=public.invite_pool_member(pool,b||'@predict-qa.invalid');
  old_token:=token;
  token:=public.invite_pool_member(pool,b||'@predict-qa.invalid');
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  if exists(select 1 from public.pools where id=pool) or exists(select 1 from public.pool_members where pool_id=pool) then
    raise exception 'FAIL: private pool visible to outsider'; end if;
  begin
    perform public.invite_pool_member(pool,outsider||'@predict-qa.invalid');
    raise exception 'FAIL: outsider invited member';
  exception when insufficient_privilege then null; end;
  begin
    perform public.accept_pool_invitation(token);
    raise exception 'FAIL: wrong email accepted';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
  begin
    perform public.get_tournament_leaderboard(t,pool,null);
    raise exception 'FAIL: outsider leaderboard';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',b::text,true);
  begin
    perform public.accept_pool_invitation(old_token);
    raise exception 'FAIL: replaced invitation accepted';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
  perform public.accept_pool_invitation(token);
  if (select count(*) from public.pool_members where pool_id=pool)<>2 then raise exception 'FAIL: join membership'; end if;
  if not exists(select 1 from public.tournament_entries where tournament_id=t and user_id=b) then raise exception 'FAIL: join entry'; end if;
  begin
    perform public.accept_pool_invitation(token);
    raise exception 'FAIL: invitation replay';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
  select count(*) into n from public.get_tournament_leaderboard(t,pool,null);
  if n<>2 then raise exception 'FAIL: pool ranking participants'; end if;
  begin
    perform public.manage_pool_member(pool,a,'remove');
    raise exception 'FAIL: member removed owner';
  exception when insufficient_privilege then null; end;

  -- Deadline: real RPC, genuinely elapsed time, no trigger bypass.
  perform set_config('role','postgres',true);
  insert into public.matches(id,tournament_id,round_id,home_name,away_name,scheduled_start,
    status,score_unit,first_to,start_time_confirmed,needs_review,predictions_enabled)
    values(fixture,t,r,'QA tijdelijk A','QA tijdelijk B',clock_timestamp()+interval '1 second',
    'scheduled','legs',6,true,false,true);
  perform set_config('role','authenticated',true);
  perform public.submit_match_prediction(fixture,6,4);
  perform set_config('request.jwt.claim.sub',a::text,true);
  if exists(select 1 from public.match_predictions where match_id=fixture and user_id=b) then
    raise exception 'FAIL: pool prediction visible before deadline'; end if;
  perform pg_sleep(1.1);
  perform set_config('request.jwt.claim.sub',b::text,true);
  begin
    perform public.submit_match_prediction(fixture,6,2);
    raise exception 'FAIL: prediction accepted after deadline';
  exception when others then
    if sqlerrm not like '%individuele voorspeldeadline%' then raise; end if;
  end;
  if (select away_score from public.match_predictions where match_id=fixture and user_id=b)<>4 then
    raise exception 'FAIL: late prediction changed data'; end if;
  select earned_points into before_points from public.get_tournament_leaderboard(t,pool,null) where user_id=b;
  perform set_config('role','postgres',true);
  update public.matches set predictions_enabled=false,status='finished',actual_start=clock_timestamp(),home_score=6,away_score=3 where id=fixture;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',a::text,true);
  if not exists(select 1 from public.match_predictions where match_id=fixture and user_id=b) then
    raise exception 'FAIL: pool prediction hidden after start'; end if;
  perform set_config('request.jwt.claim.sub',b::text,true);
  select earned_points into after_points from public.get_tournament_leaderboard(t,pool,null) where user_id=b;
  if after_points-before_points<>1 then raise exception 'FAIL: 6-4 versus 6-3 should earn 1 point'; end if;

  perform set_config('request.jwt.claim.sub',a::text,true);
  perform public.manage_pool_member(pool,b,'remove');
  perform set_config('request.jwt.claim.sub',b::text,true);
  if exists(select 1 from public.pools where id=pool) then raise exception 'FAIL: removed member retained access'; end if;
  if not exists(select 1 from public.match_predictions where match_id=fixture and user_id=b) then
    raise exception 'FAIL: removing membership deleted central prediction'; end if;
  begin
    perform public.get_tournament_leaderboard(t,pool,null);
    raise exception 'FAIL: removed member retained ranking access';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',a::text,true);
  token:=public.invite_pool_member(pool,b||'@predict-qa.invalid');
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.accept_pool_invitation(token);
  select earned_points into after_points from public.get_tournament_leaderboard(t,pool,null) where user_id=b;
  if after_points<>1 then raise exception 'FAIL: historical points missing after joining'; end if;
  perform set_config('request.jwt.claim.sub',a::text,true);
  begin
    perform public.manage_pool_member(pool,null,'leave');
    raise exception 'FAIL: owner left without transfer';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
  perform public.manage_pool_member(pool,b,'transfer');
  begin
    perform public.invite_pool_member(pool,outsider||'@predict-qa.invalid');
    raise exception 'FAIL: former owner invited';
  exception when insufficient_privilege then null; end;
  perform public.manage_pool_member(pool,null,'leave');
  if exists(select 1 from public.pools where id=pool) then raise exception 'FAIL: former member retained pool access'; end if;
  perform set_config('request.jwt.claim.sub',b::text,true);
  token:=public.invite_pool_member(pool,outsider||'@predict-qa.invalid');
  perform public.manage_pool_member(pool,null,'revoke');
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin
    perform public.accept_pool_invitation(token);
    raise exception 'FAIL: revoked invitation accepted';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
  perform set_config('request.jwt.claim.sub',b::text,true);
  token:=public.invite_pool_member(pool,outsider||'@predict-qa.invalid');
  perform set_config('role','postgres',true);
  update public.invitations set created_at=now()-interval '8 days',expires_at=now()-interval '1 day'
    where token_hash=encode(extensions.digest(token,'sha256'),'hex');
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin
    perform public.accept_pool_invitation(token);
    raise exception 'FAIL: expired invitation accepted';
  exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
  perform set_config('role','anon',true);
  begin
    perform public.create_pool(t,'Anonieme poule');
    raise exception 'FAIL: anonymous create';
  exception when insufficient_privilege then null; end;
  perform set_config('role','postgres',true);
end;
$$;
rollback;
select 'PASS: private pools, authorization, invitations, ownership, individual deadline and 1-point scoring; all fixtures rolled back' as result;
