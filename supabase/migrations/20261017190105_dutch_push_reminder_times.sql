-- Cron runs hourly in UTC; this gate selects noon and 18:00 in Europe/Amsterdam,
-- including DST, without changing the timezone of unrelated scheduled tasks.
create function predict_push.reminder_slot(p_at timestamptz) returns text
language sql stable set search_path='' as $$
 select case when extract(hour from p_at at time zone 'Europe/Amsterdam') in(12,18)
 and extract(minute from p_at at time zone 'Europe/Amsterdam')=0
 then to_char(p_at at time zone 'Europe/Amsterdam','YYYY-MM-DD:HH24') end
$$;
create function predict_push.scheduled_reminders(p_at timestamptz default now()) returns void
language plpgsql security definer set search_path='' as $$
declare slot text:=predict_push.reminder_slot(p_at);
begin
 if slot is null or not (select enabled from predict_push.config) then return;end if;
 insert into predict_push.deliveries(subscription_id,dedupe_key,kind,title,body,expires_at)
 select a.subscription_id,'nl:'||slot,'reminder','PREDICT. Voorspel nu!',
 'Je hebt nog '||a.missing||' wedstrijden te voorspellen',now()+interval '1 hour'
 from predict_push.audience('reminder',null) a on conflict(subscription_id,dedupe_key) do nothing;
end $$;
revoke all on function predict_push.reminder_slot(timestamptz),predict_push.scheduled_reminders(timestamptz) from public,anon,authenticated,service_role;
-- Retire unsent automatic hourly messages; manual messages remain queued.
update predict_push.deliveries set state='skipped',lease=null where state='pending' and kind='reminder' and dedupe_key like 'hour:%';
update predict_push.deliveries set title='PREDICT. Voorspel nu!' where state='pending' and kind='reminder';
create or replace function predict_push.api(p_action text,p_data jsonb) returns jsonb
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
 elsif kind='reminder' then title:='PREDICT. Voorspel nu!';body:='Je hebt nog wedstrijden te voorspellen';
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
 select a.subscription_id,'manual:'||bid,kind,tid,bid,title,case when kind='reminder' then 'Je hebt nog '||a.missing||' wedstrijden te voorspellen' else body end,
 now()+case when kind='reminder' then interval '1 hour' else interval '24 hours' end from predict_push.audience(kind,tid) a;
 return jsonb_build_object('devices',ct);
end $$;
create or replace function predict_push.claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not (select enabled from predict_push.config) then return '[]';end if;
 update predict_push.deliveries d set state='skipped',lease=null where state='pending' and
 (expires_at<=now() or (kind='reminder' and predict_push.missing_count((select user_id from predict_push.subscriptions where id=d.subscription_id),d.tournament_id)=0)
 or (kind='announcement' and not exists(select 1 from public.tournaments t where t.id=d.tournament_id and t.status in('announced','published','active'))));
 with chosen as(select id from predict_push.deliveries where state='pending' and available_at<=now() and attempts<5 order by available_at,id for update skip locked limit 25),
 claimed as(update predict_push.deliveries d set attempts=attempts+1,lease=gen_random_uuid(),available_at=now()+interval '5 minutes' from chosen c where d.id=c.id returning d.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'lease',d.lease,'endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth_key,
 'ttl',greatest(1,extract(epoch from d.expires_at-now())::integer),'payload',jsonb_build_object('title',d.title,'body',case when d.kind='reminder' then 'Je hebt nog '||predict_push.missing_count(s.user_id,d.tournament_id)||' wedstrijden te voorspellen' else d.body end,'tag',case when d.kind='reminder' then 'predict-reminder' else d.dedupe_key end))),'[]') into result
 from claimed d join predict_push.subscriptions s on s.id=d.subscription_id;
 -- A crashed worker's fifth lease is terminal after it expires.
 update predict_push.deliveries set state='failed',lease=null where state='pending' and attempts>=5 and available_at<=now();
 return result;
end $$;

-- Hosted scheduler
select cron.unschedule(jobid) from cron.job where jobname='predict-hourly-reminders';
-- Compatibility entry point also obeys the Dutch schedule.
create or replace function predict_push.hourly_reminders() returns void
language sql security definer set search_path='' as $$select predict_push.scheduled_reminders()$$;
select cron.schedule('predict-dutch-reminders','0 * * * *',$$select predict_push.scheduled_reminders()$$);
