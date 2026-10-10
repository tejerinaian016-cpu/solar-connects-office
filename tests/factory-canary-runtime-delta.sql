-- SQL context test of changed registry/routing/freeze; prior JWT E2E is reused.
begin;
create temporary table canary_runtime_results(test text,passed boolean);
do $$
declare w sc_internal.e2e_window; c sc_internal.v5_commands; approval jsonb; req jsonb; r jsonb; exp timestamptz:=now()+interval '10 minutes';
begin
select * into w from sc_internal.e2e_window;
select * into c from sc_internal.v5_commands where command_id=w.command_id;
approval:=jsonb_build_object('authorized',true,'evidence_ref','fixture://runtime-delta-rollback','command_id',w.command_id,'run_id',w.run_id,'actor',w.actor,
'plan_hash',w.plan_hash,'quality_sha256',encode(extensions.digest(w.quality::text,'sha256'),'hex'),
'policy_epoch','canary-test-epoch','expires_at',exp,'max_jobs',1,'stop_at','READY');
insert into sc_internal.factory_canaries(command_id,actor,run_id,plan_hash,quality,policy_epoch,approval,expires_at,session_id,expected_plan,readback_at)
values(w.command_id,w.actor,w.run_id,w.plan_hash,w.quality,'canary-test-epoch',approval,exp,w.session_id,w.expected_plan,w.readback_at);
update auth.sessions set not_after=exp where id=w.session_id;
perform set_config('request.jwt.claims',jsonb_build_object('sub',w.actor,'role','authenticated','session_id',w.session_id)::text,true);
req:=jsonb_build_object('action','FINISH','command_id',c.command_id,'claim_token',c.claim_token,'lease_version',c.lease_version);
r:=public.sc_factory_canary_v1(req);
if r->>'state'<>'SUCCEEDED' or r->>'job_status'<>'READY' then raise exception 'TEST_ROUTING';end if;
insert into canary_runtime_results values('per-command completion replay routes to original job',true);
update sc_internal.v5_commands set status='EXECUTING',claim_expires_at=exp where command_id=w.command_id;
update sc_internal.factory_permits set revoked_at=null,expires_at=exp where command_id=w.command_id;
update sc_internal.factory_canaries set enabled=true where command_id=w.command_id;
begin
perform sc_internal.canary_assert(w.command_id,c.claim_token,c.lease_version);
raise exception 'TEST_GLOBAL_GATE';
exception when others then if sqlerrm<>'E2E_EMERGENCY_OFF' then raise;end if;end;
insert into canary_runtime_results values('global FACTORY OFF remains superior',true);
update public.sc_agent_config set config=jsonb_set(config,'{security_control_plane_v1,kill_switches,factory,allow}','true') where id='solar_connects_v1';
begin
perform sc_internal.canary_assert(w.command_id,c.claim_token,c.lease_version);
raise exception 'TEST_FREEZE';
exception when others then if sqlerrm<>'CANARY_QUALITY_FROZEN_OR_CHANGED' then raise;end if;end;
update public.sc_system_health set status='TEST_ONLY',details=details||'{"epoch":"wrong","enabled":true}'||jsonb_build_object('formats',jsonb_set(details->'formats','{image,kill_switch}','false')) where component='solar_quality_v2_production_flags';
begin
perform sc_internal.canary_assert(w.command_id,c.claim_token,c.lease_version);
raise exception 'TEST_EPOCH';
exception when others then if sqlerrm<>'CANARY_QUALITY_FROZEN_OR_CHANGED' then raise;end if;end;
insert into canary_runtime_results values('Quality freeze and changed policy epoch reject runtime work',true);
update public.sc_system_health set details=jsonb_set(details,'{epoch}','"canary-test-epoch"') where component='solar_quality_v2_production_flags';
perform sc_internal.canary_assert(w.command_id,c.claim_token,c.lease_version);
insert into canary_runtime_results values('exact live ownership/version/plan accepted in rollback fixture',true);
begin
perform sc_internal.canary_assert(w.command_id,c.claim_token,c.lease_version-1);
raise exception 'TEST_VERSION';
exception when others then if sqlerrm<>'E2E_FENCE_OR_LEASE' then raise;end if;end;
insert into canary_runtime_results values('stale version remains rejected after adaptation',true);
end $$;
select jsonb_agg(to_jsonb(t)) results from canary_runtime_results t;
rollback;
