-- Device endpoints/keys and delivery queue are never exposed through the Data API.
create schema predict_push;
revoke all on schema predict_push from public,anon,authenticated;
grant usage on schema predict_push to authenticated,service_role;
create table predict_push.config(singleton boolean primary key default true check(singleton),public_key text,worker_url text,enabled boolean not null default false);
insert into predict_push.config default values;
create table predict_push.subscriptions(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text not null unique,p256dh text not null,auth_key text not null,updated_at timestamptz not null default now());
create index push_subscription_user on predict_push.subscriptions(user_id);
create table predict_push.batches(
 id uuid primary key,created_by uuid references auth.users(id) on delete set null,kind text not null,
 title text not null,body text not null,tournament_id uuid references public.tournaments(id) on delete cascade,created_at timestamptz not null default now());
create table predict_push.deliveries(
 id uuid primary key default gen_random_uuid(),subscription_id uuid not null references predict_push.subscriptions(id) on delete cascade,
 dedupe_key text not null,kind text not null check(kind in('reminder','announcement','custom')),
 tournament_id uuid references public.tournaments(id) on delete cascade,batch_id uuid references predict_push.batches(id) on delete cascade,
 title text not null,body text not null,created_at timestamptz not null default now(),expires_at timestamptz not null,
 state text not null default 'pending' check(state in('pending','sent','failed','skipped')),attempts integer not null default 0,
 available_at timestamptz not null default now(),lease uuid,sent_at timestamptz,last_status integer,
 unique(subscription_id,dedupe_key));
create index push_delivery_pending on predict_push.deliveries(available_at) where state='pending';
create index push_delivery_batch on predict_push.deliveries(batch_id);
alter table predict_push.config enable row level security;
alter table predict_push.subscriptions enable row level security;
alter table predict_push.batches enable row level security;
alter table predict_push.deliveries enable row level security;
revoke all on all tables in schema predict_push from public,anon,authenticated,service_role;

-- Keep eligibility aligned with submit_match_prediction, including knockout byes/unknown slots.
create function predict_push.missing_count(p_user uuid,p_tournament uuid default null) returns bigint
language sql stable security definer set search_path='' as $$
 select count(*) from public.tournament_entries te
 join public.tournaments t on t.id=te.tournament_id and t.status in('published','active')
 join public.matches m on m.tournament_id=t.id
 left join predict_private.knockout_nodes n on n.match_id=m.id
 where te.user_id=p_user and (p_tournament is null or t.id=p_tournament)
 and m.status='scheduled' and m.predictions_enabled and m.start_time_confirmed and not m.needs_review
 and m.round_id is not null and m.actual_start is null and m.home_score is null and m.away_score is null
 and m.scheduled_start>now() and not coalesce(n.is_bye,false)
 and (n.match_id is null or (n.home_slot is not null and n.away_slot is not null))
 and ((m.score_unit in('sets','legs') and m.first_to between 1 and 99) or (m.score_unit='goals' and m.first_to is null))
 and not exists(select 1 from public.match_predictions p where p.match_id=m.id and p.user_id=p_user)
$$;

create function predict_push.allowed_endpoint(p_endpoint text) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(length(p_endpoint)<=2048 and p_endpoint ~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|[a-z0-9-]+[.]push[.]apple[.]com|[a-z0-9.-]+[.]notify[.]windows[.]com)/[^[:space:]#]+$',false)
$$;

create function predict_push.audience(p_kind text,p_tournament uuid)
returns table(subscription_id uuid,user_id uuid,missing bigint)
language sql stable security definer set search_path='' as $$
 select s.id,s.user_id,case when p_kind='reminder' then predict_push.missing_count(s.user_id,p_tournament) else 0 end
 from predict_push.subscriptions s
 where (p_kind='reminder' and predict_push.missing_count(s.user_id,p_tournament)>0)
 or (p_kind<>'reminder' and (p_tournament is null or p_kind='announcement' or exists(
 select 1 from public.tournament_entries e where e.tournament_id=p_tournament and e.user_id=s.user_id)))
$$;

create function predict_push.api(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();cfg predict_push.config%rowtype;ep text;kind text;tid uuid;bid uuid;title text;body text;ct bigint;uc bigint;existing predict_push.batches%rowtype;
begin
 if uid is null then raise exception 'Inloggen verplicht' using errcode='42501';end if;
 select * into cfg from predict_push.config;
 if p_action='config' then return jsonb_build_object('ready',cfg.enabled and cfg.public_key is not null,'public_key',cfg.public_key);end if;
 if p_action='subscribe' then
  if not cfg.enabled then raise exception 'Pushmeldingen zijn nog niet beschikbaar';end if;
  ep:=p_data->>'endpoint';
  if not predict_push.allowed_endpoint(ep) or coalesce(p_data->'keys'->>'p256dh','') !~ '^[A-Za-z0-9_-]{87}=?$' or coalesce(p_data->'keys'->>'auth','') !~ '^[A-Za-z0-9_-]{22}(==)?$' then raise exception 'Ongeldige telefoonkoppeling';end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
  if (select count(*) from predict_push.subscriptions where user_id=uid and endpoint<>ep)>=5 then raise exception 'Maximaal vijf apparaten per account';end if;
  -- Reassigning a shared browser removes deliveries intended for the former account.
  delete from predict_push.deliveries d using predict_push.subscriptions s where d.subscription_id=s.id and s.endpoint=ep and s.user_id<>uid;
  insert into predict_push.subscriptions(user_id,endpoint,p256dh,auth_key) values(uid,ep,p_data->'keys'->>'p256dh',p_data->'keys'->>'auth')
  on conflict(endpoint) do update set user_id=excluded.user_id,p256dh=excluded.p256dh,auth_key=excluded.auth_key,updated_at=now();
  return '{"ok":true}';
 end if;
 if p_action='unsubscribe' then delete from predict_push.subscriptions where user_id=uid and endpoint=p_data->>'endpoint';return '{"ok":true}';end if;
 if not exists(select 1 from public.user_roles where user_id=uid and role in('admin','super_admin')) then raise exception 'Alleen beheerders kunnen meldingen versturen' using errcode='42501';end if;
 if p_action='admin' then return jsonb_build_object('ready',cfg.enabled,'devices',(select count(*) from predict_push.subscriptions),
 'tournaments',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'status',status) order by name),'[]') from public.tournaments where status in('announced','published','active')),
 'history',(select coalesce(jsonb_agg(to_jsonb(h) order by created_at desc),'[]') from (
 select b.id,b.title,b.created_at,count(*) filter(where d.state='sent') sent,count(*) filter(where d.state='pending') pending,count(*) filter(where d.state='failed') failed
 from (select * from predict_push.batches order by created_at desc limit 10) b left join predict_push.deliveries d on d.batch_id=b.id group by b.id,b.title,b.created_at) h));end if;
 kind:=p_data->>'kind';tid:=nullif(p_data->>'tournament_id','')::uuid;
 if kind is null or kind not in('announcement','reminder','custom') then raise exception 'Kies een soort melding';end if;
 if tid is not null and not exists(select 1 from public.tournaments where id=tid and status in('announced','published','active')) then raise exception 'Spel niet beschikbaar';end if;
 if kind='announcement' and tid is null then raise exception 'Kies het aangekondigde spel';end if;
 if kind='announcement' then select 'Nieuw spel: '||name,'Bekijk het spel in Predict.' into title,body from public.tournaments where id=tid;
 elsif kind='reminder' then title:='Nog voorspellingen invullen';body:='Je hebt nog open wedstrijden om te voorspellen.';
 else title:=btrim(p_data->>'title');body:=btrim(p_data->>'body');end if;
 if p_action='send' and (coalesce(length(title),0) not between 1 and 160 or coalesce(length(body),0) not between 1 and 240 or (kind='custom' and length(title)>80)) then raise exception 'Vul een titel en bericht in';end if;
 select count(*),count(distinct a.user_id) into ct,uc from predict_push.audience(kind,tid) a;
 if p_action='preview' then return jsonb_build_object('devices',ct,'users',uc);end if;
 if p_action<>'send' then raise exception 'Onbekende actie';end if;
 if not cfg.enabled then raise exception 'De verzendservice is nog niet geactiveerd';end if;
 bid:=(p_data->>'request_id')::uuid;if bid is null then raise exception 'Verzendkenmerk ontbreekt';end if;
 perform pg_advisory_xact_lock(hashtextextended('push-send',0));
 select * into existing from predict_push.batches where id=bid;
 if found then
  if existing.created_by<>uid or existing.kind<>kind or existing.tournament_id is distinct from tid or existing.title<>title or existing.body<>body then raise exception 'Verzendkenmerk is al gebruikt';end if;
  return jsonb_build_object('devices',(select count(*) from predict_push.deliveries where batch_id=bid));
 end if;
 if exists(select 1 from predict_push.batches where created_by=uid and created_at>now()-interval '30 seconds') then raise exception 'Wacht 30 seconden voor je opnieuw verstuurt';end if;
 insert into predict_push.batches(id,created_by,kind,title,body,tournament_id) values(bid,uid,kind,title,body,tid);
 insert into predict_push.deliveries(subscription_id,dedupe_key,kind,tournament_id,batch_id,title,body,expires_at)
 select a.subscription_id,'manual:'||bid,kind,tid,bid,title,case when kind='reminder' then 'Je hebt nog '||a.missing||' open wedstrijden om te voorspellen.' else body end,
 now()+case when kind='reminder' then interval '1 hour' else interval '24 hours' end from predict_push.audience(kind,tid) a;
 return jsonb_build_object('devices',ct);
end $$;
create function public.push_notifications(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select predict_push.api(p_action,p_data)$$;

create function predict_push.announced() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='announced' and (tg_op='INSERT' or old.status is distinct from 'announced') and (select enabled from predict_push.config) then
  insert into predict_push.deliveries(subscription_id,dedupe_key,kind,tournament_id,title,body,expires_at)
  select id,'announced:'||new.id,'announcement',new.id,'Nieuw spel: '||new.name,'Bekijk het nieuwe spel in Predict.',now()+interval '24 hours' from predict_push.subscriptions
  on conflict(subscription_id,dedupe_key) do nothing;
 end if;return new;
end $$;
create trigger push_new_announcement after insert or update of status on public.tournaments for each row execute function predict_push.announced();

create function predict_push.hourly_reminders() returns void language plpgsql security definer set search_path='' as $$
begin
 if not (select enabled from predict_push.config) then return;end if;
 insert into predict_push.deliveries(subscription_id,dedupe_key,kind,title,body,expires_at)
 select a.subscription_id,'hour:'||floor(extract(epoch from now())/3600)::bigint,'reminder','Nog voorspellingen invullen',
 'Je hebt nog '||a.missing||' open wedstrijden om te voorspellen.',now()+interval '1 hour'
 from predict_push.audience('reminder',null) a on conflict(subscription_id,dedupe_key) do nothing;
end $$;

-- Only the service role can claim deliveries. Short leases avoid concurrent duplicate sends.
create function predict_push.claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not (select enabled from predict_push.config) then return '[]';end if;
 update predict_push.deliveries d set state='skipped',lease=null where state='pending' and
 (expires_at<=now() or (kind='reminder' and predict_push.missing_count((select user_id from predict_push.subscriptions where id=d.subscription_id),d.tournament_id)=0)
 or (kind='announcement' and not exists(select 1 from public.tournaments t where t.id=d.tournament_id and t.status in('announced','published','active'))));
 with chosen as(select id from predict_push.deliveries where state='pending' and available_at<=now() and attempts<5 order by available_at,id for update skip locked limit 25),
 claimed as(update predict_push.deliveries d set attempts=attempts+1,lease=gen_random_uuid(),available_at=now()+interval '5 minutes' from chosen c where d.id=c.id returning d.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'lease',d.lease,'endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth_key,
 'ttl',greatest(1,extract(epoch from d.expires_at-now())::integer),'payload',jsonb_build_object('title',d.title,'body',case when d.kind='reminder' then 'Je hebt nog '||predict_push.missing_count(s.user_id,d.tournament_id)||' open wedstrijden om te voorspellen.' else d.body end,'tag',case when d.kind='reminder' then 'predict-reminder' else d.dedupe_key end))),'[]') into result
 from claimed d join predict_push.subscriptions s on s.id=d.subscription_id;
 -- A crashed worker's fifth lease is terminal after it expires.
 update predict_push.deliveries set state='failed',lease=null where state='pending' and attempts>=5 and available_at<=now();
 return result;
end $$;
create function predict_push.finish(p_id uuid,p_lease uuid,p_status integer) returns void language plpgsql security definer set search_path='' as $$
declare d predict_push.deliveries%rowtype;
begin
 select * into d from predict_push.deliveries where id=p_id and lease=p_lease and state='pending' for update;if not found then return;end if;
 if p_status in(404,410) then delete from predict_push.subscriptions where id=d.subscription_id;return;end if;
 update predict_push.deliveries set state=case when p_status between 200 and 299 then 'sent' when attempts>=5 or (p_status between 400 and 499 and p_status not in(408,429)) then 'failed' else 'pending' end,
 sent_at=case when p_status between 200 and 299 then now() end,last_status=p_status,lease=null,available_at=now()+make_interval(secs=>least(3600,60*(2^attempts)::integer)) where id=p_id;
end $$;
create function public.claim_push_deliveries() returns jsonb language sql security invoker set search_path='' as $$select predict_push.claim()$$;
create function public.finish_push_delivery(p_id uuid,p_lease uuid,p_status integer) returns void language sql security invoker set search_path='' as $$select predict_push.finish(p_id,p_lease,p_status)$$;

-- Every private function denies PUBLIC by default; only explicitly listed entry points are granted.
revoke all on all functions in schema predict_push from public,anon,authenticated,service_role;
revoke all on function public.push_notifications(text,jsonb),public.claim_push_deliveries(),public.finish_push_delivery(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function predict_push.api(text,jsonb),public.push_notifications(text,jsonb) to authenticated;
grant execute on function predict_push.claim(),predict_push.finish(uuid,uuid,integer),public.claim_push_deliveries(),public.finish_push_delivery(uuid,uuid,integer) to service_role;

-- Hosted scheduler
create extension if not exists pg_cron;
create extension if not exists pg_net;
create function predict_push.dispatch() returns void language plpgsql security definer set search_path='' as $$
declare cfg predict_push.config%rowtype;token text;
begin
 select * into cfg from predict_push.config;if not cfg.enabled or cfg.worker_url is null then return;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='predict_push_worker_token' limit 1;
 if token is null then return;end if;
 perform net.http_post(url:=cfg.worker_url,headers:=jsonb_build_object('Content-Type','application/json','x-push-worker',token),body:='{}',timeout_milliseconds:=55000);
 -- Bound storage without deleting current retry/deduplication windows.
 delete from predict_push.deliveries where created_at<now()-interval '30 days';
 delete from predict_push.batches where created_at<now()-interval '30 days';
end $$;
revoke all on function predict_push.dispatch() from public,anon,authenticated,service_role;
select cron.schedule('predict-hourly-reminders','0 * * * *',$$select predict_push.hourly_reminders()$$);
select cron.schedule('predict-push-dispatch','* * * * *',$$select predict_push.dispatch()$$);
