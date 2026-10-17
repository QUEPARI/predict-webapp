-- Keep deployment secrets in Vault. Only the authenticated server worker can read them.
create function predict_push.worker_configuration() returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object('enabled',c.enabled,'public_key',c.public_key,
 'private_key',(select decrypted_secret from vault.decrypted_secrets where name='predict_push_vapid_private_key' limit 1),
 'worker_token',(select decrypted_secret from vault.decrypted_secrets where name='predict_push_worker_token' limit 1))
 from predict_push.config c where singleton
$$;
create function public.push_worker_configuration() returns jsonb
language sql security invoker set search_path='' as $$select predict_push.worker_configuration()$$;
revoke all on function predict_push.worker_configuration(),public.push_worker_configuration() from public,anon,authenticated,service_role;
grant execute on function predict_push.worker_configuration(),public.push_worker_configuration() to service_role;
