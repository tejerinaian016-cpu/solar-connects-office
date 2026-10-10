-- Operational rollback preserves permanent evidence and publication fences.
begin;
update sc_internal.factory_canaries set enabled=false,step_token=null,step_until=null;
update sc_internal.factory_permits set revoked_at=coalesce(revoked_at,clock_timestamp())
where command_id in(select command_id from sc_internal.factory_canaries);
revoke execute on function public.sc_factory_canary_v1(jsonb) from authenticated;
revoke execute on function public.sc_factory_canary_progress(jsonb) from service_role;
commit;
-- Disable Edge via FACTORY_CANARY_ENABLED=false/HTTP 410 and restore gate/policy snapshots.
-- Do not DROP registry/triggers: doing so would remove fences from previously created jobs.
