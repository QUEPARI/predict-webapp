begin;
do $$
declare a uuid:=gen_random_uuid();u uuid:=gen_random_uuid();sport uuid;tpl uuid;tid uuid;recent uuid;undated uuid;draft_id uuid;rules jsonb:='[{"unit":"legs","first_to":6,"winner_points":10,"exact_points":15}]';before_game jsonb;before_matches text;
begin
 if to_regclass('auth.users') is not null then
  insert into auth.users(id,email,email_confirmed_at,aud,role) values(a,a||'@compact-qa.invalid',now(),'authenticated','authenticated'),(u,u||'@compact-qa.invalid',now(),'authenticated','authenticated');
  insert into public.profiles(id,username) values(a,'cq-'||substr(a::text,1,20)),(u,'cq-'||substr(u::text,1,20)) on conflict do nothing;
 end if;
 insert into public.user_roles values(a,'admin'),(u,'user');select id into sport from public.sports where slug='darts';
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 tpl:=public.manage_knockout_template(null,'QA delete snapshot',sport,'players',2,rules,'replacement');
 tid:=public.create_knockout_game('QA archive old',sport,'players',array['QA One','QA Two'],null,rules,'replacement',null,'draft');
 recent:=public.create_knockout_game('QA archive recent',sport,'players',array['QA One','QA Two'],null,rules,'replacement',null,'draft');
 undated:=public.create_knockout_game('QA archive no end',sport,'players',array['QA One','QA Two'],null,rules,'replacement',null,'draft');
 draft_id:=public.create_knockout_game('QA archive draft',sport,'players',array['QA One','QA Two'],null,rules,'replacement',null,'draft');
 before_game:=public.get_knockout_schema(tid);
 perform set_config('request.jwt.claim.sub',u::text,true);
 begin perform public.delete_knockout_template(tpl);raise exception 'FAIL user can delete';exception when insufficient_privilege then null;end;
 begin perform predict_private.archive_expired_games();raise exception 'FAIL user can archive';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',a::text,true);perform public.delete_knockout_template(tpl);
 if public.get_knockout_schema(tid) is distinct from before_game then
  -- server_now is intentionally dynamic; compare only the game settings.
  if (public.get_knockout_schema(tid)-'server_now') is distinct from (before_game-'server_now') then raise exception 'FAIL template deletion changed game';end if;
 end if;
 perform set_config('role','none',true);
 if exists(select 1 from predict_private.knockout_templates where id=tpl) then raise exception 'FAIL template remains';end if;
 update public.tournaments set status='completed',starts_at=now()-interval '10 days',ends_at=now()-interval '8 days' where id=tid;
 update public.tournaments set status='completed',starts_at=now()-interval '10 days',ends_at=now()-interval '6 days' where id=recent;
 update public.tournaments set status='completed' where id=undated;
 update public.tournaments set starts_at=now()-interval '10 days',ends_at=now()-interval '8 days' where id=draft_id;
 select md5(string_agg(to_jsonb(m)::text,'' order by id)) into before_matches from public.matches m;
 perform predict_private.archive_expired_games();
 if (select status from public.tournaments where id=tid)<>'archived' then raise exception 'FAIL old game not archived';end if;
 if (select status from public.tournaments where id=recent)<>'completed' or (select status from public.tournaments where id=undated)<>'completed' or (select status from public.tournaments where id=draft_id)<>'draft' then raise exception 'FAIL premature archival';end if;
 if (select md5(string_agg(to_jsonb(m)::text,'' order by id)) from public.matches m) is distinct from before_matches then raise exception 'FAIL archive mutated matches';end if;
 if predict_private.archive_expired_games()<>0 then raise exception 'FAIL archival not idempotent';end if;
end $$;
rollback;
