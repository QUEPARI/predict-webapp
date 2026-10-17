begin;
-- Enable the same read-policy enforcement in the isolated fixture; hosted tables already have RLS.
alter table public.tournaments enable row level security;
alter table public.matches enable row level security;
alter table public.tournament_rounds enable row level security;
alter table public.round_scoring enable row level security;
alter table public.tournament_scoring enable row level security;
grant select on public.tournaments,public.matches,public.tournament_rounds,public.round_scoring,public.tournament_scoring to authenticated;
do $$begin if not exists(select 1 from pg_policies where schemaname='public' and tablename='tournaments' and policyname='tournaments_read') then execute 'create policy tournaments_read on public.tournaments for select to authenticated using(status<>''draft'')';end if;end $$;
do $$
declare a uuid:=gen_random_uuid();u uuid:=gen_random_uuid();sport uuid;tid uuid;tpl uuid;rules jsonb;config jsonb;state jsonb;old_rules jsonb;rid uuid;mid uuid;begin
 if to_regclass('auth.users') is not null then
 insert into auth.users(id,email,email_confirmed_at,aud,role) values(a,a||'@preview-qa.invalid',now(),'authenticated','authenticated'),(u,u||'@preview-qa.invalid',now(),'authenticated','authenticated');
 insert into public.profiles(id,username) values(a,'pq-'||substr(a::text,1,20)),(u,'pq-'||substr(u::text,1,20)) on conflict do nothing;end if;
 insert into public.user_roles values(a,'admin'),(u,'user');select id into sport from public.sports where slug='darts';
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('role','authenticated',true);
 rules:='[{"unit":"legs","first_to":null,"winner_points":null,"exact_points":null}]';
 begin perform public.create_knockout_game('QA wrong dates',sport,'players',array['',''],now()+interval '2 days',rules,'replacement',now()+interval '1 day','announced');raise exception 'FAIL reversed range';exception when raise_exception then if sqlerrm='FAIL reversed range' then raise;end if;end;
 begin perform public.create_knockout_game('QA missing dates',sport,'players',array['',''],null,rules,'replacement',null,'announced');raise exception 'FAIL missing dates';exception when raise_exception then if sqlerrm='FAIL missing dates' then raise;end if;end;
 tid:=public.create_knockout_game('QA preview',sport,'players',array['',''],now()+interval '1 day',rules,'replacement',now()+interval '3 days','announced');
 state:=public.get_knockout_schema(tid);if state->>'status'<>'announced' or state->>'end' is null or (state->'matches'->0->>'enabled')::boolean then raise exception 'FAIL preview state';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 if not exists(select 1 from public.tournaments where id=tid and status='announced') then raise exception 'FAIL preview invisible';end if;
 if exists(select 1 from public.matches where tournament_id=tid) or exists(select 1 from public.tournament_rounds where tournament_id=tid) or exists(select 1 from public.round_scoring where tournament_id=tid) or exists(select 1 from public.tournament_scoring where tournament_id=tid) then raise exception 'FAIL preview exposes schedule or scoring';end if;
 begin perform public.get_knockout_schema(tid);raise exception 'FAIL preview schema leak';exception when insufficient_privilege then null;end;
 begin perform public.get_champion_prediction(tid);raise exception 'FAIL preview champion leak';exception when insufficient_privilege then null;end;
 begin perform public.join_tournament(tid);raise exception 'FAIL preview join';exception when raise_exception then if sqlerrm='FAIL preview join' then raise;end if;end;
 begin perform public.create_pool(tid,'QA pool');raise exception 'FAIL preview pool';exception when raise_exception then if sqlerrm='FAIL preview pool' then raise;end if;end;
 begin perform public.manage_tournament(tid,'announce','{"reason":"QA invalid role"}');raise exception 'FAIL user announcement';exception when insufficient_privilege then null;end;
 begin perform public.manage_knockout_template(null,'QA denied',sport,'players',2,rules,'replacement');raise exception 'FAIL user template';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin perform public.edit_knockout(tid,'publish');raise exception 'FAIL incomplete preview publish';exception when raise_exception then if sqlerrm='FAIL incomplete preview publish' then raise;end if;end;
 rid:=(state->'rounds'->0->>'id')::uuid;
 perform public.edit_knockout(tid,'roster',null,'{"names":["QA One","QA Two"]}');
 perform public.edit_knockout(tid,'rounds',null,jsonb_build_object('start',now()+interval '1 day','end',now()+interval '3 days','mode','replacement','rules',jsonb_build_array(jsonb_build_object('id',rid,'unit','legs','first_to',6,'winner_points',10,'exact_points',15))));
 perform public.edit_knockout(tid,'publish');
 if public.get_knockout_schema(tid)->>'status'<>'published' then raise exception 'FAIL publish from preview';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);perform public.join_tournament(tid);
 if not exists(select 1 from public.matches where tournament_id=tid) then raise exception 'FAIL published schedule hidden';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 rules:='[{"unit":"legs","first_to":6,"winner_points":10,"exact_points":15}]';
 tpl:=public.manage_knockout_template(null,'QA template',sport,'players',2,rules,'replacement');
 -- Create a separate game from the copied template values.
 tid:=public.create_knockout_game('QA template game',sport,'players',array['QA A','QA B'],now()+interval '2 days',rules,'replacement',now()+interval '4 days','draft');
 state:=public.get_knockout_schema(tid);old_rules:=state->'rounds';
 perform public.manage_knockout_template(tpl,'QA edited',sport,'players',2,'[{"unit":"sets","first_to":3,"winner_points":20,"exact_points":30}]','additive');
 if public.get_knockout_schema(tid)->'rounds' is distinct from old_rules or public.get_knockout_schema(tid)->'matches' is distinct from state->'matches' then raise exception 'FAIL template edit altered existing tournament';end if;
 if not exists(select 1 from jsonb_array_elements(public.knockout_catalog()->'templates')x where x->>'id'=tpl::text and x->>'name'='QA edited' and x->'rules'->0->>'unit'='sets') then raise exception 'FAIL template update';end if;
 begin perform public.manage_knockout_template(tpl,'QA incomplete',sport,'players',2,'[{"unit":"legs"}]','replacement');raise exception 'FAIL incomplete template';exception when raise_exception then if sqlerrm='FAIL incomplete template' then raise;end if;end;
end $$;
rollback;
