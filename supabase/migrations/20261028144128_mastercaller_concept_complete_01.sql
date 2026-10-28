create or replace function predict_private.request_mastercaller_game(p_url text,p_name text,p_winner integer,p_exact integer,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=predict_private.ko_admin();u text:=predict_private.mastercaller_url(p_url);tid uuid;cid uuid;sid uuid;title text:=btrim(coalesce(p_name,''));
begin
 if length(title) not between 1 and 120 or p_winner is null or p_winner not between 0 and 1000 or p_exact is null or p_exact not between 0 and 1000 or p_mode is null or p_mode not in('replacement','additive') then raise exception 'Vul een naam en geldige punten in';end if;
 perform pg_advisory_xact_lock(hashtextextended('mastercaller-draft:'||u,0));
 select s.tournament_id into tid from predict_private.mastercaller_sources s join public.tournaments t on t.id=s.tournament_id where s.url=u and t.results_archived_at is null order by t.created_at limit 1;
 if tid is not null then return jsonb_build_object('status','done','id',tid,'name',(select name from public.tournaments where id=tid),'participants',0,'matches',0,'existing',true,'message','Dit Mastercaller-toernooi bestaat al.');end if;
 select id into sid from public.sports where slug='darts';
 insert into public.competitions(sport_id,name) values(sid,title) returning id into cid;
 insert into public.tournaments(competition_id,name,status) values(cid,title,'draft') returning id into tid;
 insert into public.tournament_scoring(tournament_id,scoring_mode) values(tid,p_mode);
 insert into predict_private.mastercaller_sources(tournament_id,url,automatic_setup,setup_pending,setup_state,setup_next_check_at,setup_actor,setup_winner,setup_exact,source_layout)
 values(tid,u,true,true,'queued',now(),actor,p_winner,p_exact,'generic');
 insert into predict_private.tournament_management_audit(tournament_id,actor,action,reason,details) values(tid,actor,'source_draft_created','Concept aangemaakt met gekoppelde Mastercaller-bron',jsonb_build_object('url',u));
 return jsonb_build_object('status','done','id',tid,'name',title,'participants',0,'matches',0,'message','Concept aangemaakt. De eerste broncontrole staat klaar; daarna wordt elke 24 uur gecontroleerd.');
end $$;
