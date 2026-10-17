begin;
do $$
declare a uuid:=gen_random_uuid();u uuid:=gen_random_uuid();v uuid:=gen_random_uuid();sport uuid;tid uuid;mid uuid;pid uuid;other_pool uuid;data jsonb;rules jsonb:='[{"unit":"legs","first_to":6,"winner_points":10,"exact_points":15}]';
begin
 if to_regclass('auth.users') is not null then insert into auth.users(id,email,email_confirmed_at,aud,role) select x,x||'@match-popup-qa.invalid',now(),'authenticated','authenticated' from unnest(array[a,u,v])x;end if;
 insert into public.profiles(id,username) select x,'mp-'||substr(x::text,1,20) from unnest(array[a,u,v])x on conflict do nothing;
 insert into public.user_roles values(a,'admin'),(u,'user'),(v,'user');select id into sport from public.sports where slug='darts';
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 tid:=public.create_knockout_game('QA match popup',sport,'players',array['QA A','QA B'],now()+interval '1 day',rules,'replacement',null,'draft');mid:=(public.get_knockout_schema(tid)->'matches'->0->>'id')::uuid;
 perform public.edit_knockout(tid,'schedule',mid,jsonb_build_object('start',now()+interval '1 day','unit','legs','first_to',6));perform public.edit_knockout(tid,'publish');
 perform set_config('role','none',true);insert into public.tournament_entries values(tid,u),(tid,v);insert into public.pools(tournament_id,owner_id,name) values(tid,u,'QA own') returning id into pid;insert into public.pool_members(pool_id,user_id) values(pid,u),(pid,v);
 insert into public.pools(tournament_id,owner_id,name) values(tid,a,'QA other') returning id into other_pool;insert into public.pool_members(pool_id,user_id) values(other_pool,a);
 perform set_config('role','authenticated',true);perform set_config('request.jwt.claim.sub',u::text,true);perform public.submit_match_prediction(mid,6,4);perform set_config('request.jwt.claim.sub',v::text,true);perform public.submit_match_prediction(mid,6,3);
 perform set_config('request.jwt.claim.sub',a::text,true);perform public.edit_knockout(tid,'close',mid);
 perform set_config('request.jwt.claim.sub',u::text,true);data:=public.get_match_pool_comparison(mid,pid);if (data->>'visible')::boolean or jsonb_array_length(data->'members')<>0 then raise exception 'FAIL manual close leak';end if;
 begin perform public.get_match_pool_comparison(mid,other_pool);raise exception 'FAIL other pool leak';exception when insufficient_privilege then null;end;
 perform set_config('role','none',true);update public.matches set actual_start=now()+interval '1 hour' where id=mid;perform set_config('role','authenticated',true);
 if (public.get_match_pool_comparison(mid,pid)->>'visible')::boolean then raise exception 'FAIL future start leak';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','none',true);update public.matches set actual_start=now()-interval '1 minute',status='live' where id=mid;perform set_config('role','authenticated',true);
 perform public.edit_knockout(tid,'result',mid,'{"home_score":6,"away_score":4}');
 begin perform public.get_match_pool_comparison(mid,pid);raise exception 'FAIL admin not member';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',u::text,true);data:=public.get_match_pool_comparison(mid,pid);
 if not (data->>'visible')::boolean or jsonb_array_length(data->'members')<>2 or not exists(select 1 from jsonb_array_elements(data->'members')x where x->>'user_id'=u::text and x->>'points'='15') or not exists(select 1 from jsonb_array_elements(data->'members')x where x->>'user_id'=v::text and x->>'points'='10') then raise exception 'FAIL points or members %',data;end if;
 perform set_config('role','none',true);delete from public.pool_members where pool_id=pid and user_id=v;perform set_config('role','authenticated',true);
 if jsonb_array_length(public.get_match_pool_comparison(mid,pid)->'members')<>1 then raise exception 'FAIL removed member exposed';end if;
 perform set_config('request.jwt.claim.sub',v::text,true);begin perform public.get_match_pool_comparison(mid,pid);raise exception 'FAIL removed viewer';exception when insufficient_privilege then null;end;
end $$;
rollback;
