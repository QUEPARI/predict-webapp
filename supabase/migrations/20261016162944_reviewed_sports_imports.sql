grant usage on schema predict_private to service_role;
create table predict_private.darts_import_items(
  id uuid primary key default gen_random_uuid(), run_id uuid not null references public.sports_sync_runs(id),
  tournament_id uuid not null references public.tournaments(id), kind text not null check(kind in ('fixtures','results')),
  external_id text not null, payload jsonb not null, payload_hash text not null,
  state text not null default 'pending' check(state in ('pending','applied','rejected','conflict')),
  match_id uuid references public.matches(id), reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
  review_note text, history jsonb not null default '[]'::jsonb, created_at timestamptz not null default clock_timestamp(),
  unique(kind,external_id,payload_hash)
);
alter table predict_private.darts_import_items enable row level security;
revoke all on predict_private.darts_import_items from public,anon,authenticated;
create index darts_import_items_review on predict_private.darts_import_items(tournament_id,state,created_at);

create function predict_private.require_import_admin() returns uuid
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','super_admin')) then
    raise exception 'Geen beheerdersrechten' using errcode='42501';end if;
  return auth.uid();
end $$;
revoke all on function predict_private.require_import_admin() from public,anon;
grant execute on function predict_private.require_import_admin() to authenticated;

create function predict_private.begin_darts_import(p_tournament_id uuid,p_kind text) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=predict_private.require_import_admin(); run uuid;
begin
  if p_kind is null or p_kind not in ('fixtures','results') then raise exception 'Ongeldig importtype';end if;
  if not exists(select 1 from public.tournaments t join public.competitions c on c.id=t.competition_id
    join public.sports s on s.id=c.sport_id where t.id=p_tournament_id and s.slug='darts' and t.status in ('draft','published','active')) then
    raise exception 'Beschikbaar dartstoernooi vereist';end if;
  perform pg_advisory_xact_lock(hashtextextended('darts-import-budget',0));
  if exists(select 1 from public.sports_sync_runs where provider='dartsapi' and
    (started_at>clock_timestamp()-interval '60 seconds' or (status='running' and started_at>clock_timestamp()-interval '2 minutes')))
    or (select count(*) from public.sports_sync_runs where provider='dartsapi' and started_at>clock_timestamp()-interval '1 hour')>=12 then
    raise exception 'Importlimiet: wacht even en probeer later opnieuw';end if;
  insert into public.sports_sync_runs(provider,sync_type,metadata) values('dartsapi',p_kind,
    jsonb_build_object('flow','reviewed_v1','requested_by',u,'tournament_id',p_tournament_id)) returning id into run;
  return run;
end $$;
create function public.begin_darts_import(p_tournament_id uuid,p_kind text) returns uuid language sql security invoker set search_path='' as $$ select predict_private.begin_darts_import(p_tournament_id,p_kind); $$;
revoke all on function public.begin_darts_import(uuid,text),predict_private.begin_darts_import(uuid,text) from public,anon;
grant execute on function public.begin_darts_import(uuid,text),predict_private.begin_darts_import(uuid,text) to authenticated;

-- Only the Edge Function may submit provider responses. Browser admins cannot impersonate the provider.
create function predict_private.finish_darts_import(p_run_id uuid,p_actor uuid,p_items jsonb,p_error text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare run public.sports_sync_runs%rowtype; item jsonb; tid uuid; h text; added integer:=0; total integer; rowcount integer;
begin
  select * into run from public.sports_sync_runs where id=p_run_id for update;
  if not found or run.provider<>'dartsapi' or run.metadata->>'flow'<>'reviewed_v1' or run.status<>'running'
    or run.metadata->>'requested_by' is distinct from p_actor::text or run.started_at<clock_timestamp()-interval '5 minutes'
    or not exists(select 1 from public.user_roles where user_id=p_actor and role in ('admin','super_admin')) then
    raise exception 'Importaanvraag ongeldig' using errcode='42501';end if;
  if p_error is not null then
    if p_error not in ('upstream_error','invalid_data','rate_limited') then raise exception 'Ongeldige foutcode';end if;
    update public.sports_sync_runs set status='failed',finished_at=clock_timestamp(),error_count=1,error_message=p_error where id=run.id;
    return jsonb_build_object('state','failed');
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)>500 or octet_length(p_items::text)>2000000 then raise exception 'Import te groot of ongeldig';end if;
  tid:=(run.metadata->>'tournament_id')::uuid; total:=jsonb_array_length(p_items);
  if exists(select 1 from jsonb_array_elements(p_items) x group by x->>'external_id' having count(*)>1) then raise exception 'Dubbele bron-id';end if;
  for item in select value from jsonb_array_elements(p_items) order by value->>'external_id' loop
    if item->>'external_id' is null or length(item->>'external_id')>120 or item->>'external_id' !~ '^[a-zA-Z0-9_-]+$'
      or item->>'home_name' is null or item->>'away_name' is null or length(btrim(item->>'home_name')) not between 1 and 120
      or length(btrim(item->>'away_name')) not between 1 and 120 or lower(item->>'home_name')=lower(item->>'away_name')
      or ((item->>'home_name')||(item->>'away_name')) ~ '[[:cntrl:]]'
      or item->>'played_on' is null or item->>'played_on' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Ongeldig bronrecord';end if;
    perform (item->>'played_on')::date;
    if run.sync_type='results' and (jsonb_typeof(item->'home_score') is distinct from 'number' or jsonb_typeof(item->'away_score') is distinct from 'number'
      or item->>'home_score' !~ '^\d{1,2}$' or item->>'away_score' !~ '^\d{1,2}$'
      or (item->>'home_score')::integer<=(item->>'away_score')::integer) then raise exception 'Ongeldige dartsscore';end if;
    perform pg_advisory_xact_lock(hashtextextended('darts-source:'||run.sync_type||':'||(item->>'external_id'),0));
    if exists(select 1 from predict_private.darts_import_items where kind=run.sync_type and external_id=item->>'external_id' and tournament_id<>tid) then
      raise exception 'Bron-id is al gekoppeld aan een ander toernooi';end if;
    h:=encode(extensions.digest(item::text,'sha256'),'hex');
    insert into predict_private.darts_import_items(run_id,tournament_id,kind,external_id,payload,payload_hash)
      values(run.id,tid,run.sync_type,item->>'external_id',item,h) on conflict(kind,external_id,payload_hash) do nothing;
    get diagnostics rowcount=row_count;added:=added+rowcount;
  end loop;
  update public.sports_sync_runs set status=case when added>0 then 'needs_review' else 'completed' end,
    finished_at=clock_timestamp(),fetched_count=total,created_count=added where id=run.id;
  return jsonb_build_object('fetched',total,'queued',added,'unchanged',total-added);
end $$;
revoke all on function predict_private.finish_darts_import(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function predict_private.finish_darts_import(uuid,uuid,jsonb,text) to service_role;
create function public.finish_darts_import(p_run_id uuid,p_actor uuid,p_items jsonb,p_error text default null) returns jsonb language sql security invoker set search_path='' as $$ select predict_private.finish_darts_import(p_run_id,p_actor,p_items,p_error); $$;
revoke all on function public.finish_darts_import(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.finish_darts_import(uuid,uuid,jsonb,text) to service_role;

create function predict_private.list_darts_imports(p_tournament_id uuid,p_offset integer) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform predict_private.require_import_admin();
  if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'Ongeldige pagina';end if;
  return jsonb_build_object('total',(select count(*) from predict_private.darts_import_items where tournament_id=p_tournament_id),
    'items',coalesce((select jsonb_agg(to_jsonb(q)) from (select * from predict_private.darts_import_items where tournament_id=p_tournament_id order by created_at desc,id limit 25 offset p_offset) q),'[]'::jsonb));
end $$;
create function public.list_darts_imports(p_tournament_id uuid,p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$ select predict_private.list_darts_imports(p_tournament_id,p_offset); $$;
revoke all on function public.list_darts_imports(uuid,integer),predict_private.list_darts_imports(uuid,integer) from public,anon;
grant execute on function public.list_darts_imports(uuid,integer),predict_private.list_darts_imports(uuid,integer) to authenticated;

create function predict_private.review_darts_import(p_item_id uuid,p_action text,p_match_id uuid,p_round_id uuid,p_unit text,p_first_to integer,p_attested boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=predict_private.require_import_admin(); item predict_private.darts_import_items%rowtype; m public.matches%rowtype;
  mapped uuid; hs integer; aw integer; newmatch uuid; reason text; outcome text:='applied';
begin
  select * into item from predict_private.darts_import_items where id=p_item_id;
  if not found then raise exception 'Voorstel niet gevonden';end if;
  perform pg_advisory_xact_lock(hashtextextended('darts-source:'||item.kind||':'||item.external_id,0));
  -- Existing match mutators lock only the match. Use source -> match -> proposal consistently.
  if p_match_id is not null then select * into m from public.matches where id=p_match_id for update;end if;
  select * into item from predict_private.darts_import_items where id=p_item_id for update;
  if item.state in ('applied','rejected') then return jsonb_build_object('state',item.state,'match_id',item.match_id);end if;
  if p_action='reject' then
    update predict_private.darts_import_items set state='rejected',reviewed_by=u,reviewed_at=clock_timestamp(),review_note='Afgewezen door beheerder',
      history=history||jsonb_build_array(jsonb_build_object('state','rejected','actor',u,'at',clock_timestamp(),'previous_note',item.review_note)) where id=item.id;
    return jsonb_build_object('state','rejected');
  end if;
  if p_action is distinct from 'apply' or p_attested is distinct from true then raise exception 'Bevestig toernooi, ronde, spelvorm en normaal wedstrijdverloop';end if;
  if item.state='conflict' then raise exception 'Conflict: gebruik afzonderlijke controle; bestaande gegevens blijven behouden';end if;
  if exists(select 1 from predict_private.darts_import_items where kind=item.kind and external_id=item.external_id and created_at>item.created_at) then reason:='Er is een nieuwere bronversie';end if;
  if p_unit is null or p_unit not in ('sets','legs') or p_round_id is null or not exists(select 1 from public.tournament_rounds where id=p_round_id and tournament_id=item.tournament_id) then raise exception 'Geldige dartsronde en spelvorm vereist';end if;
  if not exists(select 1 from public.tournaments t join public.competitions c on c.id=t.competition_id join public.sports s on s.id=c.sport_id where t.id=item.tournament_id and s.slug='darts' and t.status in ('draft','published','active')) then raise exception 'Toernooi niet beschikbaar';end if;
  select match_id into mapped from public.external_match_ids where provider='dartsapi' and id_type=case when item.kind='fixtures' then 'fixture' else 'result' end and external_id=item.external_id;
  if item.kind='fixtures' then
    if mapped is not null then reason:='Wedstrijd bestaat al: bronwijzigingen vereisen afzonderlijke controle';end if;
    if exists(select 1 from public.matches x where x.tournament_id=item.tournament_id
      and ((lower(btrim(x.home_name))=lower(item.payload->>'home_name') and lower(btrim(x.away_name))=lower(item.payload->>'away_name'))
        or (lower(btrim(x.home_name))=lower(item.payload->>'away_name') and lower(btrim(x.away_name))=lower(item.payload->>'home_name')))
      and (x.scheduled_start is null or (x.scheduled_start at time zone 'UTC')::date=(item.payload->>'played_on')::date)) then
      reason:='Mogelijke dubbele wedstrijd: deelnemers en speeldag bestaan al';end if;
    if p_first_to is null or p_first_to not between 1 and 99 then raise exception 'First-to vereist';end if;
    if reason is null then
      insert into public.matches(tournament_id,round_id,home_name,away_name,scheduled_start,score_unit,first_to,data_source,needs_review,review_reason,start_time_confirmed,predictions_enabled)
        values(item.tournament_id,p_round_id,item.payload->>'home_name',item.payload->>'away_name',(item.payload->>'scheduled_start')::timestamptz,p_unit,p_first_to,'dartsapi',true,'Importvoorstel: controleer starttijd en formaat vóór vrijgave',false,false) returning id into newmatch;
      insert into public.external_match_ids(match_id,provider,id_type,external_id) values(newmatch,'dartsapi','fixture',item.external_id);
      insert into public.match_audit_log(match_id,changed_by,action,old_values,new_values) values(newmatch,u,'api_fixture_review','{}'::jsonb,jsonb_build_object('proposal_id',item.id,'payload_hash',item.payload_hash,'predictions_enabled',false));
    end if;
  else
    if m.id is null or m.tournament_id<>item.tournament_id or m.round_id is distinct from p_round_id or m.score_unit is distinct from p_unit then raise exception 'Kies een wedstrijd met hetzelfde toernooi, ronde en score-eenheid';end if;
    if item.payload->>'source_status' is distinct from 'settled' then reason:='Afwijkend wedstrijdverloop: geen automatische scoreverwerking';end if;
    if (m.scheduled_start at time zone 'UTC')::date is distinct from (item.payload->>'played_on')::date then reason:='Speeldatum komt niet overeen';end if;
    if lower(btrim(m.home_name))=lower(item.payload->>'home_name') and lower(btrim(m.away_name))=lower(item.payload->>'away_name') then
      hs:=(item.payload->>'home_score')::integer;aw:=(item.payload->>'away_score')::integer;
    elsif lower(btrim(m.home_name))=lower(item.payload->>'away_name') and lower(btrim(m.away_name))=lower(item.payload->>'home_name') then
      hs:=(item.payload->>'away_score')::integer;aw:=(item.payload->>'home_score')::integer;
    else reason:='Deelnemers komen niet overeen';end if;
    if (select count(*) from public.matches x where x.tournament_id=item.tournament_id and x.round_id=p_round_id and x.score_unit=p_unit
      and (x.scheduled_start at time zone 'UTC')::date=(item.payload->>'played_on')::date
      and ((lower(btrim(x.home_name))=lower(item.payload->>'home_name') and lower(btrim(x.away_name))=lower(item.payload->>'away_name'))
        or (lower(btrim(x.home_name))=lower(item.payload->>'away_name') and lower(btrim(x.away_name))=lower(item.payload->>'home_name'))))<>1 then
      reason:='Deelnemers, ronde en speeldag leveren geen unieke wedstrijdkoppeling op';end if;
    if mapped is not null and mapped<>m.id then reason:='Resultaat-id is aan een andere wedstrijd gekoppeld';end if;
    if exists(select 1 from public.external_match_ids where match_id=m.id and provider='dartsapi' and id_type='result' and external_id<>item.external_id) then reason:='Wedstrijd heeft al een andere resultaat-id';end if;
    if m.status='finished' then
      if m.home_score is distinct from hs or m.away_score is distinct from aw then reason:='API wijkt af van bestaande uitslag; overschrijven geblokkeerd';end if;
    elsif m.status not in ('scheduled','live') then reason:='Wedstrijdstatus vereist afzonderlijke controle';end if;
    if reason is null then
      if m.status<>'finished' then perform public.admin_record_match_result(m.id,hs,aw);end if;
      insert into public.external_match_ids(match_id,provider,id_type,external_id) values(m.id,'dartsapi','result',item.external_id) on conflict(provider,id_type,external_id) do nothing;
      newmatch:=m.id;
      insert into public.match_audit_log(match_id,changed_by,action,old_values,new_values) values(m.id,u,'api_result_review',jsonb_build_object('home_score',m.home_score,'away_score',m.away_score,'status',m.status),jsonb_build_object('proposal_id',item.id,'payload_hash',item.payload_hash,'home_score',hs,'away_score',aw,'verified_existing',m.status='finished'));
    end if;
  end if;
  if reason is not null then outcome:='conflict';end if;
  update predict_private.darts_import_items set state=outcome,match_id=newmatch,reviewed_by=u,reviewed_at=clock_timestamp(),review_note=coalesce(reason,'Gecontroleerd door beheerder'),
    history=history||jsonb_build_array(jsonb_build_object('state',outcome,'actor',u,'at',clock_timestamp(),'reason',reason,'match_id',newmatch)) where id=item.id;
  return jsonb_build_object('state',outcome,'match_id',newmatch,'reason',reason);
end $$;
create function public.review_darts_import(p_item_id uuid,p_action text,p_match_id uuid default null,p_round_id uuid default null,p_unit text default null,p_first_to integer default null,p_attested boolean default false) returns jsonb language sql security invoker set search_path='' as $$ select predict_private.review_darts_import(p_item_id,p_action,p_match_id,p_round_id,p_unit,p_first_to,p_attested); $$;
revoke all on function public.review_darts_import(uuid,text,uuid,uuid,text,integer,boolean),predict_private.review_darts_import(uuid,text,uuid,uuid,text,integer,boolean) from public,anon;
grant execute on function public.review_darts_import(uuid,text,uuid,uuid,text,integer,boolean),predict_private.review_darts_import(uuid,text,uuid,uuid,text,integer,boolean) to authenticated;
