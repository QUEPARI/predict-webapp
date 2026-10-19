-- Opt-in score collection; existing tournaments remain manual.
create table predict_private.mastercaller_sources(
 tournament_id uuid primary key references public.tournaments(id) on delete cascade,
 url text not null,lease uuid,last_attempt timestamptz,last_success timestamptz,
 report jsonb not null default '{}'
);
alter table predict_private.mastercaller_sources enable row level security;
revoke all on predict_private.mastercaller_sources from public,anon,authenticated;

create function predict_private.mastercaller_url(p_url text) returns text language plpgsql immutable set search_path='' as $$
declare u text:=trim(p_url);
begin
 u:=regexp_replace(u,'^https://(www\.)?mastercaller\.(com|nl)/','https://mastercaller.com/');
 u:=replace(replace(u,'/toernooien/','/tournaments/'),'/uitslagen','/results');
 u:=regexp_replace(u,'/$','');
 if u is null or u!~'^https://mastercaller\.com/tournaments/[a-z0-9-]+/20[0-9]{2}/results$' then raise exception 'Gebruik de Mastercaller-uitslagenlink van één toernooi en jaargang';end if;
 return u;
end $$;
revoke all on function predict_private.mastercaller_url(text) from public,anon,authenticated;

create function predict_private.set_score_source(p_tournament uuid,p_source text,p_url text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform predict_private.ko_admin();
 perform 1 from public.tournaments where id=p_tournament for update;
 if not found then raise exception 'Toernooi niet gevonden';end if;
 if p_source='manual' then delete from predict_private.mastercaller_sources where tournament_id=p_tournament;return true;end if;
 if p_source is distinct from 'mastercaller_test' then raise exception 'Kies een uitslagenbron';end if;
 if not exists(select 1 from public.tournaments t join public.competitions c on c.id=t.competition_id join public.sports s on s.id=c.sport_id where t.id=p_tournament and s.slug='darts') then raise exception 'Mastercaller is alleen beschikbaar voor darten';end if;
 insert into predict_private.mastercaller_sources(tournament_id,url) values(p_tournament,predict_private.mastercaller_url(p_url))
 on conflict(tournament_id) do update set url=excluded.url,lease=null,last_attempt=null,last_success=null,report='{}';
 return true;
end $$;
create function public.set_tournament_score_source(p_tournament uuid,p_source text,p_url text default null) returns boolean language sql security invoker set search_path='' as $$select predict_private.set_score_source(p_tournament,p_source,p_url)$$;
revoke all on function predict_private.set_score_source(uuid,text,text),public.set_tournament_score_source(uuid,text,text) from public,anon;
grant execute on function predict_private.set_score_source(uuid,text,text),public.set_tournament_score_source(uuid,text,text) to authenticated;

create function predict_private.get_score_source(p_tournament uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform predict_private.ko_admin();
 select jsonb_build_object('source',case when mc.tournament_id is null then 'manual' else 'mastercaller_test' end,'url',mc.url,'last_attempt',mc.last_attempt,'last_success',mc.last_success,'report',coalesce(mc.report,'{}'),'darts',s.slug='darts') into result
 from public.tournaments t join public.competitions c on c.id=t.competition_id join public.sports s on s.id=c.sport_id left join predict_private.mastercaller_sources mc on mc.tournament_id=t.id where t.id=p_tournament;
 if result is null then raise exception 'Toernooi niet gevonden';end if;return result;
end $$;
create function public.get_tournament_score_source(p_tournament uuid) returns jsonb language sql security invoker set search_path='' as $$select predict_private.get_score_source(p_tournament)$$;
revoke all on function predict_private.get_score_source(uuid),public.get_tournament_score_source(uuid) from public,anon;
grant execute on function predict_private.get_score_source(uuid),public.get_tournament_score_source(uuid) to authenticated;

create function predict_private.create_game_with_scores(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text,p_end timestamptz,p_status text,p_source text,p_url text) returns uuid language plpgsql security definer set search_path='' as $$
declare tid uuid;
begin
 perform predict_private.ko_admin();
 tid:=predict_private.create_knockout_game(p_name,p_sport,p_kind,p_roster,p_start,p_rules,p_mode,p_end,p_status);
 perform predict_private.set_score_source(tid,p_source,p_url);return tid;
end $$;
create function public.create_knockout_game_with_scores(p_name text,p_sport uuid,p_kind text,p_roster text[],p_start timestamptz,p_rules jsonb,p_mode text,p_end timestamptz,p_status text,p_source text,p_url text) returns uuid language sql security invoker set search_path='' as $$select predict_private.create_game_with_scores(p_name,p_sport,p_kind,p_roster,p_start,p_rules,p_mode,p_end,p_status,p_source,p_url)$$;
revoke all on function predict_private.create_game_with_scores(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text,text,text),public.create_knockout_game_with_scores(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text,text,text) from public,anon;
grant execute on function predict_private.create_game_with_scores(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text,text,text),public.create_knockout_game_with_scores(text,uuid,text,text[],timestamptz,jsonb,text,timestamptz,text,text,text) to authenticated;

-- Conservative comparison; no fuzzy matching or first-name aliases.
create function predict_private.score_name(p_name text) returns text language sql immutable set search_path='' as $$
 select regexp_replace(lower(translate(trim(p_name),'ÁÀÂÄÃÅáàâäãåÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÖÕóòôöõÚÙÛÜúùûüÇçÑñŠšŽžČčĆćŁłÝýŸÿ’','AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNnSsZzCcCcLlYyYy''')),'\s+',' ','g')
$$;
revoke all on function predict_private.score_name(text) from public,anon,authenticated;

create function public.claim_mastercaller_jobs(p_tournament uuid default null,p_actor uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare cfg record;items jsonb:='[]';newlease uuid;
begin
 if p_tournament is not null and (p_actor is null or not exists(select 1 from public.user_roles where user_id=p_actor and role in('admin','super_admin'))) then raise exception 'Geen beheerdersrechten';end if;
 for cfg in select mc.* from predict_private.mastercaller_sources mc join public.tournaments t on t.id=mc.tournament_id
 where (p_tournament is not null and t.id=p_tournament or p_tournament is null and t.status in('published','active')
 and t.starts_at<=now() and (t.ends_at is null or t.ends_at>now()-interval '1 day')
 and exists(select 1 from public.matches m where m.tournament_id=t.id and m.status in('scheduled','live') and m.home_score is null and coalesce(m.actual_start,m.scheduled_start)<=now()))
 and (mc.last_attempt is null or mc.last_attempt<now()-interval '5 minutes')
 order by mc.last_attempt nulls first limit 3 for update of mc skip locked
 loop
  newlease:=gen_random_uuid();update predict_private.mastercaller_sources set lease=newlease,last_attempt=now() where tournament_id=cfg.tournament_id;
  items:=items||jsonb_build_array(jsonb_build_object('tournament_id',cfg.tournament_id,'url',cfg.url,'lease',newlease));
 end loop;return items;
end $$;
revoke all on function public.claim_mastercaller_jobs(uuid,uuid) from public,anon,authenticated;
grant execute on function public.claim_mastercaller_jobs(uuid,uuid) to service_role;
grant usage on schema predict_private to service_role;
grant select,update on predict_private.mastercaller_sources to service_role;

-- Worker-only processing. All matching and score validation is repeated in the DB.
create function predict_private.finish_mastercaller(p_tournament uuid,p_lease uuid,p_records jsonb,p_error text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg predict_private.mastercaller_sources%rowtype;item jsonb;m public.matches%rowtype;rowdata record;
 hs integer;aws integer;depth integer;roundorder integer;nr integer;cnt integer;applied integer:=0;unchanged integer:=0;notes jsonb:='[]';summary jsonb;oldrow jsonb;
begin
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_tournament for update;
 if not found or cfg.lease is distinct from p_lease or cfg.last_attempt<now()-interval '3 minutes' then raise exception 'Verouderde ophaalactie';end if;
 if p_error is not null then
  summary:=jsonb_build_object('error',left(p_error,300),'applied',0,'checked_at',now());
  update predict_private.mastercaller_sources set lease=null,report=summary where tournament_id=p_tournament;
  return summary;
 end if;
 if jsonb_typeof(p_records) is distinct from 'array' or jsonb_array_length(p_records)>256 then raise exception 'Ongeldige brongegevens';end if;
 select max(round_order) into nr from public.tournament_rounds where tournament_id=p_tournament;
 for item in select value from jsonb_array_elements(p_records) order by (value->>'depth')::integer desc loop
  begin
   depth:=(item->>'depth')::integer;roundorder:=nr-depth;
   hs:=(item->>'home_score')::integer;aws:=(item->>'away_score')::integer;
   if depth is null or depth not between 0 and 7 or hs is null or aws is null or hs not between 0 and 99 or aws not between 0 and 99 or hs=aws or coalesce(item->>'date','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'Ongeldige bronuitslag';end if;
   if length(trim(coalesce(item->>'home_name',''))) not between 1 and 120 or length(trim(coalesce(item->>'away_name',''))) not between 1 and 120 then raise exception 'Spelersnamen ontbreken';end if;
   if (select count(*) from jsonb_array_elements(p_records)x where (x->>'depth')::integer=depth and
    (predict_private.score_name(x->>'home_name')=predict_private.score_name(item->>'home_name') and predict_private.score_name(x->>'away_name')=predict_private.score_name(item->>'away_name')
    or predict_private.score_name(x->>'away_name')=predict_private.score_name(item->>'home_name') and predict_private.score_name(x->>'home_name')=predict_private.score_name(item->>'away_name')))<>1 then raise exception 'Dubbele bronwedstrijd';end if;
   select count(*) into cnt from public.matches x join public.tournament_rounds r on r.id=x.round_id where x.tournament_id=p_tournament and r.round_order=roundorder and
    ((predict_private.score_name(x.home_name)=predict_private.score_name(item->>'home_name') and predict_private.score_name(x.away_name)=predict_private.score_name(item->>'away_name')) or
    (predict_private.score_name(x.away_name)=predict_private.score_name(item->>'home_name') and predict_private.score_name(x.home_name)=predict_private.score_name(item->>'away_name')));
   if cnt<>1 then raise exception 'Geen unieke lokale wedstrijd met deze spelers en ronde';end if;
   select x.* into m from public.matches x join public.tournament_rounds r on r.id=x.round_id where x.tournament_id=p_tournament and r.round_order=roundorder and
    ((predict_private.score_name(x.home_name)=predict_private.score_name(item->>'home_name') and predict_private.score_name(x.away_name)=predict_private.score_name(item->>'away_name')) or
    (predict_private.score_name(x.away_name)=predict_private.score_name(item->>'home_name') and predict_private.score_name(x.home_name)=predict_private.score_name(item->>'away_name'))) for update of x;
   if predict_private.score_name(m.home_name)<>predict_private.score_name(item->>'home_name') then hs:=(item->>'away_score')::integer;aws:=(item->>'home_score')::integer;end if;
   if m.status='finished' then
    if m.home_score=hs and m.away_score=aws then unchanged:=unchanged+1;continue;end if;
    raise exception 'Bestaande uitslag wijkt af; niet overschreven';
   end if;
   if m.status not in('scheduled','live') or m.home_score is not null or m.away_score is not null or m.needs_review then raise exception 'Wedstrijd niet beschikbaar voor automatische uitslag';end if;
   if not exists(select 1 from public.tournaments where id=p_tournament and status in('published','active')) then raise exception 'Publiceer het toernooi vóór uitslagverwerking';end if;
   if coalesce(m.actual_start,m.scheduled_start) is null or coalesce(m.actual_start,m.scheduled_start)>clock_timestamp() or
    (coalesce(m.actual_start,m.scheduled_start) at time zone 'Europe/Amsterdam')::date<>(item->>'date')::date then raise exception 'Wedstrijddatum wijkt af of start ligt in de toekomst';end if;
   if m.score_unit not in('legs','sets') or m.first_to is null or not ((hs=m.first_to and aws<m.first_to) or(aws=m.first_to and hs<m.first_to)) then raise exception 'Uitslag past niet bij het lokale wedstrijdformaat';end if;
   oldrow:=jsonb_build_object('home_score',m.home_score,'away_score',m.away_score,'status',m.status);
   update public.matches set home_score=hs,away_score=aws,status='finished',predictions_enabled=false,last_synced_at=now(),updated_at=now() where id=m.id;
   insert into public.match_audit_log(match_id,changed_by,action,old_values,new_values) values(m.id,null,'mastercaller_test_result',oldrow,jsonb_build_object('home_score',hs,'away_score',aws,'source_url',cfg.url,'source_round',item->>'round'));
   applied:=applied+1;
  exception when others then
   if jsonb_array_length(notes)<100 then notes:=notes||jsonb_build_array(jsonb_build_object('match',left(concat(item->>'home_name',' – ',item->>'away_name'),240),'reason',left(sqlerrm,240)));end if;
  end;
 end loop;
 summary:=jsonb_build_object('applied',applied,'unchanged',unchanged,'received',jsonb_array_length(p_records),'issues',notes,'checked_at',now());
 update predict_private.mastercaller_sources set lease=null,last_success=now(),report=summary where tournament_id=p_tournament;
 return summary;
end $$;
revoke all on function predict_private.finish_mastercaller(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function predict_private.finish_mastercaller(uuid,uuid,jsonb,text) to service_role;
create function public.finish_mastercaller_job(p_tournament uuid,p_lease uuid,p_records jsonb,p_error text default null) returns jsonb language sql security invoker set search_path='' as $$select predict_private.finish_mastercaller(p_tournament,p_lease,p_records,p_error)$$;
revoke all on function public.finish_mastercaller_job(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.finish_mastercaller_job(uuid,uuid,jsonb,text) to service_role;

-- Hosted scheduler: secret stays in Vault and is never returned to browser roles.
create extension if not exists pg_cron;
create extension if not exists pg_net;
do $$begin
 if not exists(select 1 from vault.secrets where name='predict_mastercaller_worker') then
  perform vault.create_secret(replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),'predict_mastercaller_worker');
 end if;
end $$;
create function predict_private.verify_mc_worker(p_token text) returns boolean language sql security definer set search_path='' as $$select length(p_token)=64 and exists(select 1 from vault.decrypted_secrets where name='predict_mastercaller_worker' and decrypted_secret=p_token)$$;
revoke all on function predict_private.verify_mc_worker(text) from public,anon,authenticated;
grant execute on function predict_private.verify_mc_worker(text) to service_role;
create function public.verify_mastercaller_worker(p_token text) returns boolean language sql security invoker set search_path='' as $$select predict_private.verify_mc_worker(p_token)$$;
revoke all on function public.verify_mastercaller_worker(text) from public,anon,authenticated;
grant execute on function public.verify_mastercaller_worker(text) to service_role;
create function predict_private.dispatch_mastercaller() returns void language plpgsql security definer set search_path='' as $$
declare token text;
begin
 if not exists(select 1 from predict_private.mastercaller_sources mc join public.tournaments t on t.id=mc.tournament_id where t.status in('published','active') and t.starts_at<=now() and (t.ends_at is null or t.ends_at>now()-interval '1 day')) then return;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='predict_mastercaller_worker';
 if token is null then return;end if;
 perform net.http_post(url:='https://sfcozzjcuppfypetbbzn.supabase.co/functions/v1/sync-mastercaller',headers:=jsonb_build_object('Content-Type','application/json','x-mastercaller-worker',token),body:='{}',timeout_milliseconds:=55000);
end $$;
revoke all on function predict_private.dispatch_mastercaller() from public,anon,authenticated;
select cron.schedule('predict-mastercaller-test','*/5 * * * *',$$select predict_private.dispatch_mastercaller()$$);
