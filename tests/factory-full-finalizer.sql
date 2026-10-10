-- SQL transaction tests; real JWT transport is exercised separately through Edge.
begin;
do $$ declare w sc_internal.e2e_window; c sc_internal.v5_commands; j uuid; req jsonb; r jsonb;
begin
select * into w from sc_internal.e2e_window;
select * into c from sc_internal.v5_commands where command_id=w.command_id;
select job_id into j from sc_internal.factory_permits where command_id=w.command_id;
perform set_config('request.jwt.claims',jsonb_build_object('sub',w.actor,'role','authenticated','session_id',w.session_id)::text,true);
req:=jsonb_build_object('action','FINISH','command_id',w.command_id,'claim_token',c.claim_token,'lease_version',c.lease_version);
begin
update sc_internal.factory_permits set revoked_at=now() where command_id=w.command_id;
perform public.sc_factory_e2e_v1(req);
raise exception 'TEST_REVOCATION';
exception when others then if sqlerrm<>'E2E_FENCE_OR_LEASE' then raise;end if;end;
begin
insert into public.sc_creative_stage_outputs(run_id,stage,attempt,input_hash,schema_version,validation_status,output)
select run_id,stage,2,input_hash,schema_version,validation_status,jsonb_set(output,'{candidate_id}','"tampered"')
from public.sc_creative_stage_outputs where run_id=w.run_id and stage='DIRECTOR' and attempt=1;
perform public.sc_factory_e2e_v1(req);
raise exception 'TEST_SOURCE_HASH';
exception when others then if sqlerrm<>'E2E_SOURCE_CONFLICT' then raise;end if;end;
begin
update public.sc_content_jobs set qa=jsonb_set(qa,'{quality_v2_runtime,guardian_pending_evidence,visual_review,critiques,0,asset_sha256}',to_jsonb(repeat('a',64))) where id=j;
perform public.sc_factory_e2e_v1(req);
raise exception 'TEST_GUARDIAN_HASH';
exception when others then if sqlerrm not like '%QUALITY_CRITIC_BINDING%' then raise;end if;end;
r:=public.sc_factory_e2e_v1(req);
if r->>'state'<>'SUCCEEDED' or r->>'job_status'<>'READY' then raise exception 'TEST_COMPLETION';end if;
end $$;
rollback;
select c.status ledger_after_rollback,j.status job_after_rollback from sc_internal.v5_commands c
join sc_internal.e2e_window w using(command_id) join sc_internal.factory_permits p using(command_id)
join public.sc_content_jobs j on j.id=p.job_id;
