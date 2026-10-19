alter table predict_private.mastercaller_sources add column automatic_setup boolean not null default false;
alter table predict_private.mastercaller_sources add column snapshot jsonb;

create function predict_private.sync_mastercaller_schema(p_tournament uuid,p_snapshot jsonb) returns void language plpgsql security definer set search_path='' as $$
declare cfg predict_private.mastercaller_sources%rowtype;k predict_private.knockout_tournaments%rowtype;f jsonb;m public.matches%rowtype;n predict_private.knockout_nodes%rowtype;rule jsonb;start_at timestamptz;nr integer;roster text[];
begin
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_tournament;
 if not cfg.automatic_setup then return;end if;
 if p_snapshot is null or predict_private.mastercaller_url(p_snapshot->>'url') is distinct from cfg.url or jsonb_typeof(p_snapshot->'bracket') is distinct from 'array' then raise exception 'Ongeldig bronschema';end if;
 perform 1 from public.tournaments where id=p_tournament for update;
 select * into k from predict_private.knockout_tournaments where tournament_id=p_tournament;
 select array_agg(value order by ord) into roster from jsonb_array_elements_text(p_snapshot->'roster') with ordinality x(value,ord);
 if cardinality(roster) is distinct from cardinality(k.roster) or exists(select 1 from unnest(roster,k.roster) x(a,b) where predict_private.score_name(a) is distinct from predict_private.score_name(b)) then raise exception 'De loting is gewijzigd; automatische verwerking gepauzeerd';end if;
 select count(*) into nr from public.tournament_rounds where tournament_id=p_tournament;
 if jsonb_array_length(p_snapshot->'rounds')<>nr or jsonb_array_length(p_snapshot->'bracket')<>cardinality(roster)-1 then raise exception 'Onvolledig bronschema';end if;
 for f in select value from jsonb_array_elements(p_snapshot->'bracket') loop
  select * into n from predict_private.knockout_nodes where tournament_id=p_tournament and round_no=(f->>'order')::integer and position=(f->>'position')::integer;
  if not found then raise exception 'Schemapositie ontbreekt';end if;
  select * into m from public.matches where id=n.match_id for update;
  if m.status<>'scheduled' or m.actual_start is not null or m.home_score is not null then continue;end if;
  select value into rule from jsonb_array_elements(p_snapshot->'rounds') where (value->>'order')::integer=n.round_no;
  if rule->>'unit' is distinct from m.score_unit or (rule->>'first_to')::integer is distinct from m.first_to then raise exception 'Het wedstrijdformat in de bron is gewijzigd';end if;
  if (nullif(f->>'home_name','') is not null and n.home_slot is not null and predict_private.score_name(f->>'home_name')<>predict_private.score_name(m.home_name))
   or (nullif(f->>'away_name','') is not null and n.away_slot is not null and predict_private.score_name(f->>'away_name')<>predict_private.score_name(m.away_name)) then raise exception 'Deelnemers wijken af van het bronschema';end if;
  start_at:=nullif(f->>'start','')::timestamptz;
  -- A source delay must not reopen an already expired prediction window.
  update public.matches set scheduled_start=start_at,start_time_confirmed=start_at is not null,needs_review=false,
   predictions_enabled=coalesce(start_at>clock_timestamp() and n.home_slot is not null and n.away_slot is not null
    and (m.scheduled_start is null or m.scheduled_start>clock_timestamp())
    and exists(select 1 from public.tournaments where id=p_tournament and status in('published','active')),false),
   updated_at=now() where id=m.id;
 end loop;
 update predict_private.mastercaller_sources set snapshot=p_snapshot-'records' where tournament_id=p_tournament;
end $$;
revoke all on function predict_private.sync_mastercaller_schema(uuid,jsonb) from public,anon,authenticated;

create function predict_private.create_mastercaller_game(p_snapshot jsonb,p_name text,p_winner integer,p_exact integer,p_mode text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();tid uuid;sport uuid;roster text[];rules jsonb;start_at timestamptz;end_at timestamptz;title text;
begin
 if p_winner is null or p_exact is null or p_winner not between 0 and 1000 or p_exact not between 0 and 1000 then raise exception 'Ongeldige puntentelling';end if;
 if jsonb_typeof(p_snapshot->'rounds') is distinct from 'array' or jsonb_typeof(p_snapshot->'roster') is distinct from 'array' then raise exception 'Bronschema ontbreekt';end if;
 if coalesce(p_snapshot->>'start_date','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' or coalesce(p_snapshot->>'end_date','')!~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'Bronperiode ontbreekt';end if;
 title:=coalesce(nullif(trim(p_name),''),trim(p_snapshot->>'title')||' '||split_part(predict_private.mastercaller_url(p_snapshot->>'url'),'/',6));
 select array_agg(value order by ord) into roster from jsonb_array_elements_text(p_snapshot->'roster') with ordinality x(value,ord);
 if cardinality(roster) not in(2,4,8,16,32,64,128) then raise exception 'Onbekend knock-outformat';end if;
 select jsonb_agg(jsonb_build_object('name',x->>'name','unit',x->>'unit','first_to',(x->>'first_to')::integer,'winner_points',p_winner,'exact_points',p_exact) order by (x->>'order')::integer) into rules from jsonb_array_elements(p_snapshot->'rounds')x;
 start_at:=(p_snapshot->>'start_date')::date::timestamp at time zone 'Europe/Amsterdam';
 end_at:=((p_snapshot->>'end_date')::date+1)::timestamp at time zone 'Europe/Amsterdam';
 select id into sport from public.sports where slug='darts';
 tid:=predict_private.create_knockout_game(title,sport,'players',roster,start_at,rules,p_mode,end_at,'draft');
 perform predict_private.set_score_source(tid,'mastercaller_test',p_snapshot->>'url');
 update predict_private.mastercaller_sources set automatic_setup=true,last_attempt=now(),last_success=now(),report=jsonb_build_object('checked_at',now(),'applied',0,'received',jsonb_array_length(p_snapshot->'records')) where tournament_id=tid;
 -- Source-owned games can be published with TBA times. No prediction opens until
 -- an actual source timestamp exists; manual publication checks stay unchanged.
 update public.tournaments set status='published' where id=tid;
 perform predict_private.sync_mastercaller_schema(tid,p_snapshot);
 return tid;
end $$;
create function public.create_mastercaller_game(p_snapshot jsonb,p_name text default null,p_winner integer default 1,p_exact integer default 3,p_mode text default 'replacement') returns uuid language sql security invoker set search_path='' as $$select predict_private.create_mastercaller_game(p_snapshot,p_name,p_winner,p_exact,p_mode)$$;
revoke all on function predict_private.create_mastercaller_game(jsonb,text,integer,integer,text),public.create_mastercaller_game(jsonb,text,integer,integer,text) from public,anon;
grant execute on function predict_private.create_mastercaller_game(jsonb,text,integer,integer,text),public.create_mastercaller_game(jsonb,text,integer,integer,text) to authenticated;

-- Preserve the tested result processor and wrap it with source-schema syncing.
alter function predict_private.finish_mastercaller(uuid,uuid,jsonb,text) rename to finish_mastercaller_scores;
create function predict_private.finish_mastercaller(p_tournament uuid,p_lease uuid,p_records jsonb,p_error text,p_snapshot jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg predict_private.mastercaller_sources%rowtype;issue text;result jsonb;
begin
 perform 1 from public.tournaments where id=p_tournament for update;
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_tournament for update;
 if not found or cfg.lease is distinct from p_lease or cfg.last_attempt<now()-interval '3 minutes' then raise exception 'Verouderde ophaalactie';end if;
 if cfg.automatic_setup and p_error is null then
  begin perform predict_private.sync_mastercaller_schema(p_tournament,p_snapshot);
  exception when others then issue:=left(sqlerrm,300);end;
 end if;
 result:=predict_private.finish_mastercaller_scores(p_tournament,p_lease,p_records,coalesce(p_error,issue));
 if cfg.automatic_setup and p_error is null and issue is null then
  perform predict_private.sync_mastercaller_schema(p_tournament,p_snapshot);
 end if;
 return result;
end $$;
revoke all on function predict_private.finish_mastercaller(uuid,uuid,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function predict_private.finish_mastercaller(uuid,uuid,jsonb,text,jsonb) to service_role;
drop function public.finish_mastercaller_job(uuid,uuid,jsonb,text);
create function public.finish_mastercaller_job(p_tournament uuid,p_lease uuid,p_records jsonb,p_error text default null,p_snapshot jsonb default null) returns jsonb language sql security invoker set search_path='' as $$select predict_private.finish_mastercaller(p_tournament,p_lease,p_records,p_error,p_snapshot)$$;
revoke all on function public.finish_mastercaller_job(uuid,uuid,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function public.finish_mastercaller_job(uuid,uuid,jsonb,text,jsonb) to service_role;

create function predict_private.mastercaller_interval(p_tournament uuid) returns interval language sql stable set search_path='' as $$
 select case when exists(select 1 from public.matches m where m.tournament_id=p_tournament and m.status in('scheduled','live') and m.home_score is null and coalesce(m.actual_start,m.scheduled_start)<=now())
 or exists(select 1 from predict_private.mastercaller_sources mc join public.tournaments t on t.id=mc.tournament_id where t.id=p_tournament and mc.automatic_setup and t.starts_at<=now() and (t.ends_at is null or t.ends_at>now()) and exists(select 1 from public.matches m where m.tournament_id=t.id and m.status='scheduled' and m.scheduled_start is null))
 then interval '15 minutes' else interval '4 hours' end
$$;
revoke all on function predict_private.mastercaller_interval(uuid) from public,anon,authenticated;
grant execute on function predict_private.mastercaller_interval(uuid) to service_role;
create or replace function public.claim_mastercaller_jobs(p_tournament uuid default null,p_actor uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare cfg record;items jsonb:='[]';newlease uuid;
begin
 if p_tournament is not null and (p_actor is null or not exists(select 1 from public.user_roles where user_id=p_actor and role in('admin','super_admin'))) then raise exception 'Geen beheerdersrechten';end if;
 for cfg in select mc.* from predict_private.mastercaller_sources mc join public.tournaments t on t.id=mc.tournament_id
 where (p_tournament is not null and t.id=p_tournament or p_tournament is null and t.status in('published','active')
  and (t.ends_at is null or t.ends_at>now()-interval '1 day') and exists(select 1 from public.matches m where m.tournament_id=t.id and m.home_score is null and m.status in('scheduled','live')))
 and (mc.last_attempt is null or mc.last_attempt<now()-case when p_tournament is not null then interval '1 minute' else predict_private.mastercaller_interval(t.id) end)
 order by mc.last_attempt nulls first limit 3 for update of mc skip locked loop
  newlease:=gen_random_uuid();update predict_private.mastercaller_sources set lease=newlease,last_attempt=now() where tournament_id=cfg.tournament_id;
  items:=items||jsonb_build_array(jsonb_build_object('tournament_id',cfg.tournament_id,'url',cfg.url,'lease',newlease,'automatic_setup',cfg.automatic_setup));
 end loop;return items;
end $$;
create or replace function predict_private.dispatch_mastercaller() returns void language plpgsql security definer set search_path='' as $$
declare token text;
begin
 if not exists(select 1 from predict_private.mastercaller_sources mc join public.tournaments t on t.id=mc.tournament_id where t.status in('published','active') and (t.ends_at is null or t.ends_at>now()-interval '1 day') and (mc.last_attempt is null or mc.last_attempt<now()-predict_private.mastercaller_interval(t.id)) and exists(select 1 from public.matches m where m.tournament_id=t.id and m.status in('scheduled','live') and m.home_score is null)) then return;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='predict_mastercaller_worker';
 if token is null then return;end if;
 perform net.http_post(url:='https://sfcozzjcuppfypetbbzn.supabase.co/functions/v1/sync-mastercaller',headers:=jsonb_build_object('Content-Type','application/json','x-mastercaller-worker',token),body:='{}',timeout_milliseconds:=55000);
end $$;

-- Date-only completed source results do not invent a start timestamp.
create or replace function predict_private.finish_mastercaller_scores(p_tournament uuid,p_lease uuid,p_records jsonb,p_error text) returns jsonb language plpgsql security definer set search_path='' as $$
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
   if cfg.automatic_setup and coalesce(m.actual_start,m.scheduled_start) is null then
    -- A completed source result proves play has ended even if no exact start was published.
    -- Do not fabricate actual_start or a scheduled timestamp.
    if (item->>'date')::date>(now() at time zone 'Europe/Amsterdam')::date or not exists(select 1 from public.tournaments t where t.id=p_tournament and (item->>'date')::date between (t.starts_at at time zone 'Europe/Amsterdam')::date and ((t.ends_at at time zone 'Europe/Amsterdam')::date-1)) then raise exception 'Bronuitslag buiten de toernooiperiode';end if;
   elsif coalesce(m.actual_start,m.scheduled_start) is null or coalesce(m.actual_start,m.scheduled_start)>clock_timestamp() or
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
