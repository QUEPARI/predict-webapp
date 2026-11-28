create or replace function predict_private.prediction_time_open(p_tournament uuid,p_start timestamptz,p_confirmed boolean)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(case when p_start is not null then p_confirmed and p_start>clock_timestamp()
 else exists(select 1 from predict_private.mastercaller_sources s join public.tournaments t on t.id=s.tournament_id
 where t.id=p_tournament and s.automatic_setup
 and (t.starts_at>clock_timestamp() or (s.source_layout='generic' and s.setup_snapshot->>'format'='knockout' and t.status in ('published','active')))) end,false)
$$;

create function predict_private.advance_source_knockout(p_match uuid) returns void
language plpgsql security definer set search_path='' as $$
declare src record; dest public.matches%rowtype; winner text; h text; a text; ready boolean; valid_pair boolean;
begin
 select m.tournament_id,m.status,m.home_score,m.away_score,m.home_name,m.away_name,r.round_order,map.position into src
 from public.matches m join public.tournament_rounds r on r.id=m.round_id
 join predict_private.mastercaller_match_map map on map.match_id=m.id and map.tournament_id=m.tournament_id
 join predict_private.mastercaller_sources s on s.tournament_id=m.tournament_id
 join public.tournaments t on t.id=m.tournament_id
 where m.id=p_match and not m.needs_review and map.group_name is null and s.source_layout='generic'
 and s.automatic_setup and not s.setup_pending and s.setup_snapshot->>'format'='knockout'
 and t.status in ('published','active');
 if not found or src.status<>'finished' or src.home_score is null or src.away_score is null or src.home_score=src.away_score then return;end if;
 winner:=case when src.home_score>src.away_score then src.home_name else src.away_name end;
 if winner is null or winner in ('','NNB') then return;end if;
 -- Only use adjacent rounds with contiguous position ranges and the expected 2:1 size.
 select count(*) filter(where r.round_order=src.round_order)=2*count(*) filter(where r.round_order=src.round_order+1)
 and bool_and(map.group_name is null and map.position>0)
 and count(distinct (r.round_order,map.position))=count(*)
 and max(map.position) filter(where r.round_order=src.round_order)=count(*) filter(where r.round_order=src.round_order)
 and max(map.position) filter(where r.round_order=src.round_order+1)=count(*) filter(where r.round_order=src.round_order+1)
 into valid_pair from predict_private.mastercaller_match_map map join public.matches m on m.id=map.match_id
 join public.tournament_rounds r on r.id=m.round_id
 where map.tournament_id=src.tournament_id and r.round_order in (src.round_order,src.round_order+1);
 if valid_pair is not true then return;end if;
 select m.* into dest from public.matches m join public.tournament_rounds r on r.id=m.round_id
 join predict_private.mastercaller_match_map map on map.match_id=m.id
 where m.tournament_id=src.tournament_id and r.round_order=src.round_order+1 and map.position=(src.position+1)/2 for update of m;
 if not found or dest.status<>'scheduled' or dest.actual_start is not null or dest.home_score is not null
 or dest.away_score is not null or dest.predictions_enabled or dest.prediction_window_closed
 or coalesce(dest.scheduled_start<=clock_timestamp(),false) then return;end if;
 h:=dest.home_name; a:=dest.away_name;
 if src.position%2=1 and coalesce(h,'') in ('','NNB') then h:=winner;
 elsif src.position%2=0 and coalesce(a,'') in ('','NNB') then a:=winner;
 else return;end if;
 if predict_private.score_name(h)=predict_private.score_name(a) then return;end if;
 ready:=coalesce(h,'') not in ('','NNB') and coalesce(a,'') not in ('','NNB');
 perform predict_private.mc_enter(src.tournament_id);
 update public.matches set home_name=h,away_name=a,needs_review=not ready,
 predictions_enabled=ready and first_to is not null
 and predict_private.prediction_time_open(tournament_id,scheduled_start,start_time_confirmed),updated_at=now()
 where id=dest.id;
 perform predict_private.mc_exit(src.tournament_id);
end $$;
revoke all on function predict_private.advance_source_knockout(uuid) from public,anon,authenticated,service_role;

create function predict_private.advance_source_knockout_on_result() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.status='finished' and (old.status,old.home_score,old.away_score) is distinct from (new.status,new.home_score,new.away_score)
 then perform predict_private.advance_source_knockout(new.id);end if;
 return new;
end $$;
revoke all on function predict_private.advance_source_knockout_on_result() from public,anon,authenticated,service_role;
create trigger advance_source_knockout_on_result after update of status,home_score,away_score on public.matches
for each row execute function predict_private.advance_source_knockout_on_result();
