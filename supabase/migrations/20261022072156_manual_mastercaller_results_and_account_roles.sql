-- Controlled manual results for source-owned games; existing schema locks stay intact.
create table predict_private.mastercaller_manual_results (
 match_id uuid primary key references public.matches(id) on delete cascade,
 home_score integer not null, away_score integer not null,
 recorded_by uuid not null, recorded_at timestamptz not null default now(),
 source_home_score integer, source_away_score integer, source_checked_at timestamptz,
 conflict boolean not null default false
);
alter table predict_private.mastercaller_manual_results enable row level security;
revoke all on predict_private.mastercaller_manual_results from public,anon,authenticated,service_role;

create function predict_private.record_source_result(p_match uuid,p_home integer,p_away integer) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin(); m public.matches%rowtype; tid uuid; state text;
begin
 select tournament_id into tid from public.matches where id=p_match;
 select status into state from public.tournaments where id=tid for update;
 if not exists(select 1 from predict_private.mastercaller_sources where tournament_id=tid) then raise exception 'Geen Mastercaller-wedstrijd';end if;
 select * into m from public.matches where id=p_match and tournament_id=tid for update;
 if state not in('published','active','completed') then raise exception 'Het toernooi is niet actief';end if;
 if m.status not in('scheduled','live','finished') or m.needs_review then raise exception 'Wedstrijd niet beschikbaar voor uitslaginvoer';end if;
 if p_home is null or p_away is null or p_home not between 0 and 99 or p_away not between 0 and 99
  or m.score_unit not in('legs','sets') or m.first_to is null
  or not ((p_home=m.first_to and p_away<m.first_to) or(p_away=m.first_to and p_home<m.first_to))
 then raise exception 'Uitslag past niet bij het wedstrijdformaat';end if;
 if not exists(select 1 from public.tournament_rounds where id=m.round_id and tournament_id=tid) then raise exception 'Wedstrijdronde ontbreekt';end if;
 if m.status<>'finished' then
  if coalesce(m.actual_start,m.scheduled_start) is not null then
   if coalesce(m.actual_start,m.scheduled_start)>clock_timestamp() then raise exception 'De wedstrijdstart ligt in de toekomst';end if;
  elsif not exists(select 1 from public.tournaments where id=tid and starts_at<=clock_timestamp()) then
   raise exception 'Het toernooi is nog niet begonnen';
  end if;
 end if;
 -- The private permit covers result propagation only, never arbitrary browser edits.
 perform predict_private.mc_enter(tid);
 update public.matches set home_score=p_home,away_score=p_away,status='finished',predictions_enabled=false,
  prediction_window_closed=true,updated_at=now() where id=m.id;
 perform predict_private.mc_exit(tid);
 insert into predict_private.mastercaller_manual_results(match_id,home_score,away_score,recorded_by)
 values(m.id,p_home,p_away,actor)
 on conflict(match_id) do update set home_score=excluded.home_score,away_score=excluded.away_score,
  recorded_by=excluded.recorded_by,recorded_at=now(),
  conflict=case when predict_private.mastercaller_manual_results.source_checked_at is null then false else
   predict_private.mastercaller_manual_results.source_home_score is distinct from excluded.home_score or
   predict_private.mastercaller_manual_results.source_away_score is distinct from excluded.away_score end;
 insert into public.match_audit_log(match_id,changed_by,action,old_values,new_values)
 values(m.id,actor,'mastercaller_manual_result',jsonb_build_object('home_score',m.home_score,'away_score',m.away_score,'status',m.status),
  jsonb_build_object('home_score',p_home,'away_score',p_away,'status','finished','result_source','manual_admin'));
 return true;
end $$;
revoke all on function predict_private.record_source_result(uuid,integer,integer) from public,anon,service_role;
grant execute on function predict_private.record_source_result(uuid,integer,integer) to authenticated;
create function public.admin_record_source_result(p_match uuid,p_home integer,p_away integer) returns boolean
language sql security invoker set search_path='' as $$select predict_private.record_source_result(p_match,p_home,p_away)$$;
revoke all on function public.admin_record_source_result(uuid,integer,integer) from public,anon;
grant execute on function public.admin_record_source_result(uuid,integer,integer) to authenticated;

create table predict_private.account_role_audit (
 id bigint generated always as identity primary key, actor uuid not null, target uuid not null,
 old_role text not null, new_role text not null, changed_at timestamptz not null default now()
);
alter table predict_private.account_role_audit enable row level security;
revoke all on predict_private.account_role_audit from public,anon,authenticated,service_role;
create function predict_private.list_accounts() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'username',coalesce(p.username,'Account zonder profiel'),
  'display_name',p.display_name,'role',coalesce(r.role,'user'),'created_at',u.created_at,
  'activated',u.last_sign_in_at is not null,'can_change_role',
  exists(select 1 from public.user_roles where user_id=auth.uid() and role='super_admin')
   and u.id<>auth.uid() and coalesce(r.role,'user')<>'super_admin')
  order by lower(coalesce(p.username,'')),u.id),'[]'::jsonb)
 from auth.users u left join public.profiles p on p.id=u.id left join public.user_roles r on r.user_id=u.id
 where u.deleted_at is null);
end $$;
create function predict_private.set_account_role(p_user uuid,p_role text) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); oldrole text;
begin
 -- Lock live role rows so a concurrent revocation cannot leave stale authority.
 perform 1 from public.user_roles where user_id in(actor,p_user) order by user_id for update;
 if actor is null or not exists(select 1 from public.user_roles where user_id=actor and role='super_admin') then
  raise exception 'Alleen de hoofdbeheerder kan beheerrechten wijzigen' using errcode='42501';end if;
 if p_role is null or p_role not in('user','admin') then raise exception 'Kies gebruiker of beheerder';end if;
 if p_user=actor then raise exception 'Je kunt je eigen hoofdbeheerrechten niet wijzigen';end if;
 if not exists(select 1 from auth.users where id=p_user and deleted_at is null) then raise exception 'Account niet gevonden';end if;
 select role into oldrole from public.user_roles where user_id=p_user;
 if oldrole='super_admin' then raise exception 'Hoofdbeheerrechten zijn beschermd' using errcode='42501';end if;
 oldrole:=coalesce(oldrole,'user');
 if oldrole=p_role then return true;end if;
 insert into public.user_roles(user_id,role) values(p_user,p_role) on conflict(user_id) do update set role=excluded.role;
 insert into predict_private.account_role_audit(actor,target,old_role,new_role) values(actor,p_user,oldrole,p_role);
 return true;
end $$;
revoke all on function predict_private.list_accounts(),predict_private.set_account_role(uuid,text) from public,anon,service_role;
grant execute on function predict_private.list_accounts(),predict_private.set_account_role(uuid,text) to authenticated;
create function public.admin_list_accounts() returns jsonb language sql security invoker set search_path='' as $$select predict_private.list_accounts()$$;
create function public.admin_set_account_role(p_user uuid,p_role text) returns boolean language sql security invoker set search_path='' as $$select predict_private.set_account_role(p_user,p_role)$$;
revoke all on function public.admin_list_accounts(),public.admin_set_account_role(uuid,text) from public,anon;
grant execute on function public.admin_list_accounts(),public.admin_set_account_role(uuid,text) to authenticated;

CREATE OR REPLACE FUNCTION predict_private.finish_mastercaller_scores(p_tournament uuid, p_lease uuid, p_records jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    update predict_private.mastercaller_manual_results set source_home_score=hs,source_away_score=aws,source_checked_at=now(),
     conflict=(m.home_score is distinct from hs or m.away_score is distinct from aws) where match_id=m.id;
    if m.home_score=hs and m.away_score=aws then unchanged:=unchanged+1;continue;end if;
    if jsonb_array_length(notes)<100 then
     notes:=notes||jsonb_build_array(jsonb_build_object('match',left(concat(m.home_name,' – ',m.away_name),240),
      'reason','Bronuitslag wijkt af; opgeslagen uitslag blijft behouden'));
    end if;
    continue;
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
end $function$;
create or replace function predict_private.get_score_source(p_tournament uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return predict_private.get_score_source_internal(p_tournament)||predict_private.mc_source_info(p_tournament)||
 jsonb_build_object('manual_results',(select coalesce(jsonb_agg(jsonb_build_object(
  'match_id',m.id,'home_name',m.home_name,'away_name',m.away_name,'home_score',r.home_score,'away_score',r.away_score,
  'source_home_score',r.source_home_score,'source_away_score',r.source_away_score,'source_checked_at',r.source_checked_at,'conflict',r.conflict)),'[]')
  from predict_private.mastercaller_manual_results r join public.matches m on m.id=r.match_id where m.tournament_id=p_tournament));
end $$;