-- Run as postgres. All synthetic users, tournaments and predictions roll back.
begin;
do $$
declare u uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid(); t uuid; r uuid;
  closed uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); st text;
begin
  select id into strict t from public.tournaments where name='Predict QA - dartstest' and status in ('published','active');
  select id into r from public.tournament_rounds where tournament_id=t order by round_order limit 1;
  insert into public.tournaments(id,competition_id,name,status)
    select closed,competition_id,'QA tijdelijke deelnamecontrole','draft' from public.tournaments where id=t;
  insert into auth.users(id,email,email_confirmed_at,aud,role) values
    (u,u||'@predict-entry-qa.invalid',now(),'authenticated','authenticated'),
    (other_user,other_user||'@predict-entry-qa.invalid',now(),'authenticated','authenticated');
  insert into public.profiles(id,username) values(u,u::text),(other_user,other_user::text);
  insert into public.user_roles(user_id,role) values(u,'user'),(other_user,'user');
  insert into public.matches(id,tournament_id,round_id,home_name,away_name,scheduled_start,status,score_unit,first_to,start_time_confirmed,needs_review,predictions_enabled)
    values(m,t,r,'QA deelname A','QA deelname B',clock_timestamp()+interval '1 day','scheduled','legs',6,true,false,true);
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('role','authenticated',true);
  begin
    perform public.submit_match_prediction(m,6,4);
    raise exception 'FAIL: prediction before entry';
  exception when others then if sqlerrm not like '%neemt nog niet deel%' then raise; end if; end;
  perform public.join_tournament(t);
  perform public.join_tournament(t);
  if (select count(*) from public.tournament_entries where tournament_id=t and user_id=u)<>1 then raise exception 'FAIL: idempotent entry'; end if;
  if exists(select 1 from public.pool_members where user_id=u) then raise exception 'FAIL: entry requires pool'; end if;
  begin
    insert into public.tournament_entries(tournament_id,user_id) values(t,other_user);
    raise exception 'FAIL: adding another user directly';
  exception when insufficient_privilege then null; end;
  if exists(select 1 from public.tournaments where id=closed) then raise exception 'FAIL: draft visible'; end if;
  begin
    perform public.join_tournament(closed);
    raise exception 'FAIL: draft entry';
  exception when others then if sqlerrm not like '%niet beschikbaar voor deelname%' then raise; end if; end;
  begin
    perform public.join_tournament(null);
    raise exception 'FAIL: null entry';
  exception when others then if sqlerrm not like '%niet beschikbaar voor deelname%' then raise; end if; end;
  begin
    perform public.submit_match_prediction(m,6,6);
    raise exception 'FAIL: invalid leg score';
  exception when others then if sqlerrm not like '%Ongeldige voorspelde set- of legstand%' then raise; end if; end;
  perform public.submit_match_prediction(m,6,4);
  perform public.submit_match_prediction(m,6,3);
  if (select count(*) from public.match_predictions where match_id=m and user_id=u)<>1 then raise exception 'FAIL: duplicate prediction'; end if;
  if (select away_score from public.match_predictions where match_id=m and user_id=u)<>3 then raise exception 'FAIL: prediction not updated'; end if;
  perform set_config('request.jwt.claim.sub',other_user::text,true);
  if exists(select 1 from public.tournament_entries where user_id=u) then raise exception 'FAIL: other entry visible'; end if;
  if exists(select 1 from public.match_predictions where match_id=m) then raise exception 'FAIL: other prediction visible'; end if;
  perform set_config('role','postgres',true);
  foreach st in array array['completed','archived'] loop
    update public.tournaments set status=st where id=closed;
    perform set_config('role','authenticated',true);
    begin
      perform public.join_tournament(closed);
      raise exception 'FAIL: closed tournament entry';
    exception when others then if sqlerrm not like '%niet beschikbaar voor deelname%' then raise; end if; end;
    perform set_config('role','postgres',true);
  end loop;
  update public.tournaments set status='active' where id=closed;
  perform set_config('role','authenticated',true);
  perform public.join_tournament(closed);
  perform set_config('role','anon',true);
  begin
    perform public.join_tournament(t);
    raise exception 'FAIL: anonymous entry';
  exception when insufficient_privilege then null; end;
  perform set_config('role','postgres',true);
end;
$$;
rollback;
select 'PASS: own idempotent entry without pool, draft/closed/anonymous rejection, prediction validation and privacy; all test data rolled back' as result;
