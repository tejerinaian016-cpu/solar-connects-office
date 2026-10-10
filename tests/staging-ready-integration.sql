-- Execute only in cmwervbwxyqzowntnxwe. All deliberate writes roll back.
begin;
do $$
declare jid uuid:='eb5f786a-61b7-4e7c-b8af-65c7e5039d2e'; result jsonb; before_qa jsonb; after_qa jsonb;
begin
select qa into before_qa from public.sc_content_jobs where id=jid;
begin
update public.sc_content_jobs set content_plan=jsonb_set(content_plan,'{quality_v2,pages,0,title}','"Tampered"') where id=jid;
raise exception 'TEST_EXPECTED_PLAN_REJECTION';
exception when others then if sqlerrm<>'STAGING_PLAN_IMMUTABLE' then raise;end if;end;
begin
update public.sc_content_jobs set qa=jsonb_set(qa,'{publish_blocked}','false') where id=jid;
raise exception 'TEST_EXPECTED_PUBLICATION_REJECTION';
exception when others then if sqlerrm<>'STAGING_PUBLICATION_FORBIDDEN' then raise;end if;end;
begin
update public.sc_content_jobs set qa=jsonb_set(qa,'{quality_v2_runtime,guardian_pending_evidence,visual_review,critiques,0,asset_sha256}',to_jsonb(repeat('a',64))) where id=jid;
perform sc_internal.staging_ready(jid);
raise exception 'TEST_EXPECTED_HASH_REJECTION';
exception when others then if sqlerrm not like '%QUALITY_CRITIC_BINDING%' then raise;end if;end;
begin
update public.sc_content_jobs set qa=qa#-'{quality_v2_runtime,guardian_pending_evidence}' where id=jid;
perform sc_internal.staging_ready(jid);
raise exception 'TEST_EXPECTED_EVIDENCE_REJECTION';
exception when others then if sqlerrm<>'GUARDIAN_EVIDENCE_REQUIRED' then raise;end if;end;
begin
insert into public.sc_content_posts(job_id) values(jid);
raise exception 'TEST_EXPECTED_POST_REJECTION';
exception when others then if sqlerrm<>'SYNTHETIC_FIXTURE_PUBLICATION_FORBIDDEN' then raise;end if;end;
begin
update public.sc_content_jobs set qa=jsonb_set(qa,'{quality_v2_runtime,staging_readback_at}',to_jsonb((now()-interval '11 minutes')::text)) where id=jid;
perform sc_internal.staging_ready(jid);
raise exception 'TEST_EXPECTED_STALE_READBACK_REJECTION';
exception when others then if sqlerrm<>'FRESH_GUARDIAN_READBACK_REQUIRED' then raise;end if;end;
begin
insert into public.sc_publish_guard(job_id,fingerprint,account_id) values(jid,'test','synthetic');
raise exception 'TEST_EXPECTED_PUBLISH_GUARD_REJECTION';
exception when others then if sqlerrm<>'SYNTHETIC_FIXTURE_PUBLICATION_FORBIDDEN' then raise;end if;end;
select qa into after_qa from public.sc_content_jobs where id=jid;
if before_qa is distinct from after_qa then raise exception 'SUBTRANSACTION_ROLLBACK_FAILED';end if;
if has_function_privilege('anon','sc_internal.staging_ready(uuid)','EXECUTE')
or has_function_privilege('authenticated','sc_internal.staging_ready(uuid)','EXECUTE')
or has_function_privilege('service_role','sc_internal.staging_ready(uuid)','EXECUTE') then raise exception 'FINALIZATION_GRANT_LEAK';end if;
result:=sc_internal.staging_ready(jid);
if result->>'status'<>'READY' then raise exception 'READY_FAILED';end if;
result:=sc_internal.staging_ready(jid);
if result->>'idempotent'<>'true' then raise exception 'RETRY_FAILED';end if;
begin
update public.sc_content_jobs set qa=qa||'{"tampered":true}' where id=jid;
raise exception 'TEST_EXPECTED_SEAL_REJECTION';
exception when others then if sqlerrm<>'STAGING_READY_SEALED' then raise;end if;end;
end $$;
rollback;
select status='QUALITY_V2_SHADOW_RENDERING' rollback_restored_draft,
qa->>'guardian_qa' is null rollback_removed_guardian_transition
from public.sc_content_jobs where id='eb5f786a-61b7-4e7c-b8af-65c7e5039d2e';
