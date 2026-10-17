begin;
do $$
declare a uuid:=gen_random_uuid();u uuid:=gen_random_uuid();sport uuid;tid uuid;other uuid;rounds jsonb;complete jsonb;schema jsonb;m uuid;before_settings jsonb;
begin
 if to_regclass('auth.users') is not null then
  insert into auth.users(id,email,email_confirmed_at,aud,role) values(a,a||'@draft-qa.invalid',now(),'authenticated','authenticated'),(u,u||'@draft-qa.invalid',now(),'authenticated','authenticated');
  insert into public.profiles(id,username) values(a,'dq-'||substr(a::text,1,20)),(u,'dq-'||substr(u::text,1,20)) on conflict do nothing;
 end if;
 insert into public.user_roles values(a,'admin'),(u,'user');select id into sport from public.sports where slug='darts';
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 rounds:='[{"unit":"legs","first_to":null,"winner_points":null,"exact_points":null},{"unit":"legs","first_to":null,"winner_points":null,"exact_points":null}]';
 tid:=public.create_knockout_tournament('QA upcoming draft',sport,'players',array['','','',''],null,rounds);
 schema:=public.get_knockout_schema(tid);
 if schema->>'status'<>'draft' or schema->>'start' is not null or jsonb_array_length(schema->'publication_issues')<6 then raise exception 'FAIL incomplete draft';end if;
 if exists(select 1 from jsonb_array_elements(schema->'rounds')x where x->>'winner_points' is not null or x->>'exact_points' is not null) then raise exception 'FAIL blank points silently defaulted';end if;
 if exists(select 1 from jsonb_array_elements(schema->'matches')x where (x->>'enabled')::boolean or x->>'first_to' is not null) then raise exception 'FAIL incomplete match enabled';end if;
 begin perform public.edit_knockout(tid,'publish');raise exception 'FAIL incomplete publish';exception when raise_exception then if sqlerrm='FAIL incomplete publish' then raise;end if;end;
 begin perform public.admin_publish_tournament(tid);raise exception 'FAIL legacy incomplete publish';exception when raise_exception then if sqlerrm='FAIL legacy incomplete publish' then raise;end if;end;
 begin perform public.save_knockout_template('QA incomplete template',sport,'players',4,rounds,'replacement');raise exception 'FAIL incomplete template';exception when raise_exception then if sqlerrm='FAIL incomplete template' then raise;end if;end;
 m:=(schema->'matches'->0->>'id')::uuid;
 perform public.edit_knockout(tid,'schedule',m,jsonb_build_object('start',now()+interval '1 day','unit','legs','first_to',null,'reason','QA draft schedule'));
 select jsonb_agg(jsonb_build_object('id',x->>'id','unit','legs','first_to',null,'winner_points',0,'exact_points',null) order by (x->>'order')::integer) into rounds from jsonb_array_elements(public.get_knockout_schema(tid)->'rounds')x;
 perform public.edit_knockout(tid,'rounds',null,jsonb_build_object('start',null,'mode','additive','rules',rounds));
 if not exists(select 1 from jsonb_array_elements(public.get_knockout_schema(tid)->'rounds')x where (x->>'winner_points')::integer=0 and x->>'exact_points' is null) then raise exception 'FAIL partial values';end if;
 before_settings:=public.get_knockout_schema(tid);
 begin perform public.edit_knockout(tid,'rounds',null,jsonb_build_object('mode','additive','rules',jsonb_set(rounds,'{0,id}',to_jsonb(gen_random_uuid()))));raise exception 'FAIL foreign round';exception when raise_exception then if sqlerrm='FAIL foreign round' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',u::text,true);
 begin perform public.edit_knockout(tid,'rounds',null,jsonb_build_object('mode','additive','rules',rounds));raise exception 'FAIL user editing';exception when insufficient_privilege then null;end;
 begin perform public.get_knockout_schema(tid);raise exception 'FAIL user draft read';exception when insufficient_privilege then null;end;
 begin perform public.create_knockout_tournament('QA denied',sport,'players',array['',''],null,'[{"unit":"legs"}]');raise exception 'FAIL user draft create';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.edit_knockout(tid,'roster',null,'{"names":["QA A","QA B","QA C","QA D"]}');
 -- Names and a start alone do not satisfy publication; points and formats are checked by every route.
 perform public.manage_tournament(tid,'metadata',jsonb_build_object('name','QA upcoming draft','start',now()+interval '1 day','reason','QA set start'));
 begin perform public.admin_publish_tournament(tid);raise exception 'FAIL missing points legacy publish';exception when raise_exception then if sqlerrm='FAIL missing points legacy publish' then raise;end if;end;
 select jsonb_agg(jsonb_build_object('id',x->>'id','unit','legs','first_to',6,'winner_points',10,'exact_points',15) order by (x->>'order')::integer) into complete from jsonb_array_elements(public.get_knockout_schema(tid)->'rounds')x;
 perform public.edit_knockout(tid,'rounds',null,jsonb_build_object('start',now()+interval '1 day','mode','additive','rules',complete));
 if jsonb_array_length(public.get_knockout_schema(tid)->'publication_issues')<>0 then raise exception 'FAIL complete draft issues';end if;
 perform public.edit_knockout(tid,'publish');
 if (public.get_knockout_schema(tid)->>'status')<>'published' then raise exception 'FAIL complete publish';end if;
 begin perform public.edit_knockout(tid,'rounds',null,jsonb_build_object('mode','additive','rules',rounds));raise exception 'FAIL published round mutation';exception when raise_exception then if sqlerrm='FAIL published round mutation' then raise;end if;end;
 perform set_config('role','postgres',true);
 begin update public.round_scoring set winner_points=null where tournament_id=tid;raise exception 'FAIL published null scoring';exception when raise_exception then if sqlerrm='FAIL published null scoring' then raise;end if;end;
 if exists(select 1 from predict_private.tournament_mutation_permits where tournament_id=tid) then raise exception 'FAIL leftover permit';end if;
end $$;
rollback;
