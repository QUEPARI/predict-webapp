-- Rollback-only regression against an existing automatic source.
begin;
do $test$
declare tid uuid; snap jsonb; mid uuid; known timestamptz:=now()+interval '2 days'; before_hash text; after_hash text;
begin
 select tournament_id,snapshot into tid,snap from predict_private.mastercaller_sources where automatic_setup limit 1;
 if tid is null then raise exception 'Test requires an automatic source';end if;
 select md5(string_agg(row_to_json(p)::text,'' order by p.id)) into before_hash from public.match_predictions p join public.matches m on m.id=p.match_id where m.tournament_id=tid;
 select match_id into mid from predict_private.knockout_nodes where tournament_id=tid and round_no=1 and position=1;
 snap:=jsonb_set(snap,'{bracket,0,start}',to_jsonb(known::text));
 perform predict_private.sync_mastercaller_schema(tid,snap);
 snap:=jsonb_set(snap,'{bracket,0,start}','null');
 perform predict_private.sync_mastercaller_schema(tid,snap);
 if (select scheduled_start is distinct from known from public.matches where id=mid) then raise exception 'FAIL null erased known time';end if;
 snap:=jsonb_set(snap,'{bracket,0,start}',to_jsonb((now()-interval '1 hour')::text));
 perform predict_private.sync_mastercaller_schema(tid,snap);
 snap:=jsonb_set(snap,'{bracket,0,start}',to_jsonb(known::text));
 perform predict_private.sync_mastercaller_schema(tid,snap);
 if (select predictions_enabled or not prediction_window_closed from public.matches where id=mid) then raise exception 'FAIL reopened elapsed deadline';end if;
 select md5(string_agg(row_to_json(p)::text,'' order by p.id)) into after_hash from public.match_predictions p join public.matches m on m.id=p.match_id where m.tournament_id=tid;
 if before_hash is distinct from after_hash then raise exception 'FAIL predictions changed';end if;
end $test$;
rollback;
