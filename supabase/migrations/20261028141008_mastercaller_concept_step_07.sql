-- Pending concepts must never enter the existing score-polling pipeline.
do $$declare definition text;begin
 select pg_get_functiondef('public.claim_mastercaller_jobs(uuid,uuid)'::regprocedure) into definition;
 if position('where not predict_private.mc_final_finished(t.id)' in definition)=0 then raise exception 'Unexpected score-claim definition';end if;
 execute replace(definition,'where not predict_private.mc_final_finished(t.id)','where not mc.setup_pending and not predict_private.mc_final_finished(t.id)');
 select pg_get_functiondef('public.claim_mastercaller_jobs(uuid,uuid)'::regprocedure) into definition;
 execute replace(definition,'''automatic_setup'',cfg.automatic_setup','''automatic_setup'',cfg.automatic_setup,''source_layout'',cfg.source_layout');
end $$;
