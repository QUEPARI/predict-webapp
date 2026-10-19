-- A source-owned schema is editable only by the private sync pipeline.
create table predict_private.mastercaller_write_permits(tournament_id uuid,transaction_id bigint,depth integer not null,primary key(tournament_id,transaction_id));
alter table predict_private.mastercaller_write_permits enable row level security;
revoke all on predict_private.mastercaller_write_permits from public,anon,authenticated,service_role;
create function predict_private.mc_enter(p_id uuid) returns void language sql security definer set search_path='' as $$
 insert into predict_private.mastercaller_write_permits values(p_id,txid_current(),1) on conflict(tournament_id,transaction_id) do update set depth=predict_private.mastercaller_write_permits.depth+1
$$;
create function predict_private.mc_exit(p_id uuid) returns void language plpgsql security definer set search_path='' as $$begin
 update predict_private.mastercaller_write_permits set depth=depth-1 where tournament_id=p_id and transaction_id=txid_current();
 delete from predict_private.mastercaller_write_permits where tournament_id=p_id and transaction_id=txid_current() and depth=0;
end $$;
revoke all on function predict_private.mc_enter(uuid),predict_private.mc_exit(uuid) from public,anon,authenticated,service_role;

create function predict_private.mc_schema_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare tid uuid;
begin
 if TG_TABLE_NAME='tournaments' then
  tid:=old.id;
  if new.starts_at is not distinct from old.starts_at and new.ends_at is not distinct from old.ends_at and new.competition_id is not distinct from old.competition_id then return new;end if;
 else
  if TG_OP='UPDATE' and old.tournament_id is distinct from new.tournament_id
   and exists(select 1 from predict_private.mastercaller_sources where tournament_id=old.tournament_id)
   and not exists(select 1 from predict_private.mastercaller_write_permits where tournament_id=old.tournament_id and transaction_id=txid_current() and depth>0)
   then raise exception 'Een Mastercaller-wedstrijd kan niet naar een ander toernooi worden verplaatst' using errcode='42501';end if;
  tid:=case when TG_OP='DELETE' then old.tournament_id else new.tournament_id end;
 end if;
 if exists(select 1 from predict_private.mastercaller_sources where tournament_id=tid)
 and not exists(select 1 from predict_private.mastercaller_write_permits where tournament_id=tid and transaction_id=txid_current() and depth>0)
 then raise exception 'Dit toernooi wordt door Mastercaller beheerd. Schema, deelnemers, planning en uitslagen zijn alleen-lezen.' using errcode='42501';end if;
 if TG_OP='DELETE' then return old;else return new;end if;
end $$;
revoke all on function predict_private.mc_schema_guard() from public,anon,authenticated,service_role;
create trigger mastercaller_schema_guard before insert or update or delete on public.matches for each row execute function predict_private.mc_schema_guard();
create trigger mastercaller_schema_guard before insert or update or delete on public.tournament_rounds for each row execute function predict_private.mc_schema_guard();
create trigger mastercaller_schema_guard before insert or update or delete on public.round_scoring for each row execute function predict_private.mc_schema_guard();
create trigger mastercaller_schema_guard before insert or update or delete on predict_private.knockout_tournaments for each row execute function predict_private.mc_schema_guard();
create trigger mastercaller_schema_guard before insert or update or delete on predict_private.knockout_nodes for each row execute function predict_private.mc_schema_guard();
create trigger mastercaller_schema_guard before update on public.tournaments for each row execute function predict_private.mc_schema_guard();

alter function predict_private.sync_mastercaller_schema(uuid,jsonb) rename to sync_mastercaller_schema_internal;
create function predict_private.sync_mastercaller_schema(p_tournament uuid,p_snapshot jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 perform predict_private.mc_enter(p_tournament);
 perform predict_private.sync_mastercaller_schema_internal(p_tournament,p_snapshot);
 perform predict_private.mc_exit(p_tournament);
end $$;
revoke all on function predict_private.sync_mastercaller_schema(uuid,jsonb) from public,anon,authenticated,service_role;
alter function predict_private.finish_mastercaller(uuid,uuid,jsonb,text,jsonb) rename to finish_mastercaller_internal;
revoke all on function predict_private.finish_mastercaller_internal(uuid,uuid,jsonb,text,jsonb) from public,anon,authenticated,service_role;
create function predict_private.finish_mastercaller(p_tournament uuid,p_lease uuid,p_records jsonb,p_error text,p_snapshot jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform predict_private.mc_enter(p_tournament);
 result:=predict_private.finish_mastercaller_internal(p_tournament,p_lease,p_records,p_error,p_snapshot);
 perform predict_private.mc_exit(p_tournament);return result;
end $$;
revoke all on function predict_private.finish_mastercaller(uuid,uuid,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function predict_private.finish_mastercaller(uuid,uuid,jsonb,text,jsonb) to service_role;

-- Preserve explicit lifecycle controls, without granting manual schema access.
alter function predict_private.manage_tournament(uuid,text,jsonb) rename to manage_tournament_internal;
revoke all on function predict_private.manage_tournament_internal(uuid,text,jsonb) from public,anon,authenticated,service_role;
create function predict_private.manage_tournament(p_id uuid,p_action text,p_values jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare result boolean;source_owned boolean;
begin
 perform predict_private.ko_admin();
 select exists(select 1 from predict_private.mastercaller_sources where tournament_id=p_id) into source_owned;
 if source_owned and p_action in('draft','announce','points','champion_result') then raise exception 'Deze wijziging is alleen beschikbaar bij handmatige toernooien' using errcode='42501';end if;
 if source_owned and p_action in('pause','resume','delete') then perform predict_private.mc_enter(p_id);end if;
 result:=predict_private.manage_tournament_internal(p_id,p_action,p_values);
 if source_owned and p_action in('pause','resume','delete') then perform predict_private.mc_exit(p_id);end if;
 return result;
end $$;
revoke all on function predict_private.manage_tournament(uuid,text,jsonb) from public,anon;
grant execute on function predict_private.manage_tournament(uuid,text,jsonb) to authenticated;

alter function predict_private.set_score_source(uuid,text,text) rename to set_score_source_internal;
revoke all on function predict_private.set_score_source_internal(uuid,text,text) from public,anon,authenticated,service_role;
create function predict_private.set_score_source(p_tournament uuid,p_source text,p_url text) returns boolean language plpgsql security definer set search_path='' as $$
declare cfg predict_private.mastercaller_sources%rowtype;
begin
 perform predict_private.ko_admin();
 perform 1 from public.tournaments where id=p_tournament for update;
 select * into cfg from predict_private.mastercaller_sources where tournament_id=p_tournament for update;
 if cfg.automatic_setup then
  if p_source is distinct from 'mastercaller_test' or predict_private.mastercaller_url(p_url) is distinct from cfg.url then raise exception 'De Mastercaller-bron staat vast bij een automatisch aangemaakt toernooi' using errcode='42501';end if;
  return true;
 end if;
 return predict_private.set_score_source_internal(p_tournament,p_source,p_url);
end $$;
revoke all on function predict_private.set_score_source(uuid,text,text) from public,anon;
grant execute on function predict_private.set_score_source(uuid,text,text) to authenticated;

create function predict_private.mc_final_finished(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.matches m join public.tournament_rounds r on r.id=m.round_id where m.tournament_id=p_id and r.round_order=(select max(round_order) from public.tournament_rounds where tournament_id=p_id) and m.status='finished' and m.home_score is not null and m.away_score is not null)
$$;
revoke all on function predict_private.mc_final_finished(uuid) from public,anon,authenticated;
grant execute on function predict_private.mc_final_finished(uuid) to service_role;
create function predict_private.mc_source_info(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('locked',exists(select 1 from predict_private.mastercaller_sources where tournament_id=p_id),'automatic_setup',coalesce((select automatic_setup from predict_private.mastercaller_sources where tournament_id=p_id),false),'stopped',predict_private.mc_final_finished(p_id))
$$;
revoke all on function predict_private.mc_source_info(uuid) from public,anon,authenticated,service_role;

alter function predict_private.ko_schema(uuid) rename to ko_schema_internal;
revoke all on function predict_private.ko_schema_internal(uuid) from public,anon,authenticated,service_role;
create function predict_private.ko_schema(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 result:=predict_private.ko_schema_internal(p_id);
 return result||jsonb_build_object('score_source',predict_private.mc_source_info(p_id));
end $$;
revoke all on function predict_private.ko_schema(uuid) from public,anon;
grant execute on function predict_private.ko_schema(uuid) to authenticated;
alter function predict_private.management_catalog() rename to management_catalog_internal;
revoke all on function predict_private.management_catalog_internal() from public,anon,authenticated,service_role;
create function predict_private.management_catalog() returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform predict_private.ko_admin();
 return (select coalesce(jsonb_agg(x||jsonb_build_object('score_source',predict_private.mc_source_info((x->>'id')::uuid))),'[]') from jsonb_array_elements(predict_private.management_catalog_internal())x);
end $$;
revoke all on function predict_private.management_catalog() from public,anon;
grant execute on function predict_private.management_catalog() to authenticated;
alter function predict_private.get_score_source(uuid) rename to get_score_source_internal;
revoke all on function predict_private.get_score_source_internal(uuid) from public,anon,authenticated,service_role;
create function predict_private.get_score_source(p_tournament uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 return predict_private.get_score_source_internal(p_tournament)||predict_private.mc_source_info(p_tournament);
end $$;
revoke all on function predict_private.get_score_source(uuid) from public,anon;
grant execute on function predict_private.get_score_source(uuid) to authenticated;

create or replace function public.claim_mastercaller_jobs(p_tournament uuid default null,p_actor uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare cfg record;items jsonb:='[]';newlease uuid;
begin
 if p_tournament is not null and (p_actor is null or not exists(select 1 from public.user_roles where user_id=p_actor and role in('admin','super_admin'))) then raise exception 'Geen beheerdersrechten';end if;
 for cfg in select mc.* from predict_private.mastercaller_sources mc join public.tournaments t on t.id=mc.tournament_id
 where not predict_private.mc_final_finished(t.id)
 and (p_tournament is not null and t.id=p_tournament or p_tournament is null and t.status in('published','active')
  and (t.ends_at is null or t.ends_at>now()-interval '1 day') and exists(select 1 from public.matches m where m.tournament_id=t.id and m.home_score is null and m.status in('scheduled','live')))
 and (mc.last_attempt is null or mc.last_attempt<now()-case when p_tournament is not null then interval '1 minute' else predict_private.mastercaller_interval(t.id) end)
 order by mc.last_attempt nulls first limit 3 for update of mc skip locked loop
  newlease:=gen_random_uuid();update predict_private.mastercaller_sources set lease=newlease,last_attempt=now() where tournament_id=cfg.tournament_id;
  items:=items||jsonb_build_array(jsonb_build_object('tournament_id',cfg.tournament_id,'url',cfg.url,'lease',newlease,'automatic_setup',cfg.automatic_setup));
 end loop;return items;
end $$;
-- Hosted dispatcher; the same final check prevents even an unnecessary worker call.
create or replace function predict_private.dispatch_mastercaller() returns void language plpgsql security definer set search_path='' as $$
declare token text;
begin
 if not exists(select 1 from predict_private.mastercaller_sources mc join public.tournaments t on t.id=mc.tournament_id where not predict_private.mc_final_finished(t.id) and t.status in('published','active') and (t.ends_at is null or t.ends_at>now()-interval '1 day') and (mc.last_attempt is null or mc.last_attempt<now()-predict_private.mastercaller_interval(t.id)) and exists(select 1 from public.matches m where m.tournament_id=t.id and m.status in('scheduled','live') and m.home_score is null)) then return;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='predict_mastercaller_worker';
 if token is null then return;end if;
 perform net.http_post(url:='https://sfcozzjcuppfypetbbzn.supabase.co/functions/v1/sync-mastercaller',headers:=jsonb_build_object('Content-Type','application/json','x-mastercaller-worker',token),body:='{}',timeout_milliseconds:=55000);
end $$;
