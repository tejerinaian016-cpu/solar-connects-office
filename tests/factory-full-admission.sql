begin;
do $$ declare jid uuid; r jsonb; p jsonb;
begin
begin
insert into public.sc_content_jobs(status,qa) values('PLANNED','{}');
raise exception 'TEST_LEGACY_NOT_BLOCKED';
exception when others then if sqlerrm<>'E2E_ADMISSION_CLOSED_TO_LEGACY_PRODUCTION' then raise;end if;end;
-- Authentic prior SHADOW producer, fully rolled back.
select jsonb_build_object('format','image','topic','Legacy staging shadow compatibility','caption','Synthetic compatibility; never publish','quality_v2',quality,'idempotency_key','quality-v2-shadow:legacy_e2e_compat') into p from sc_internal.e2e_window;
r:=public.sc_quality_factory_adapter_v2(p,'{"enabled":true,"mode":"SHADOW","formats":["image"]}');
if r->>'ok' is distinct from 'true' then raise exception 'LEGACY_SHADOW_FAILED %',r;end if;
jid:=(r->>'job_id')::uuid;
begin
update public.sc_content_jobs set qa=qa||'{"quality_v2_production_draft":true}' where id=jid;
raise exception 'TEST_LATE_ANNOTATION_BYPASS';
exception when others then if sqlerrm<>'E2E_OTHER_CONTROLLED_PRODUCER' then raise;end if;end;
begin
update public.sc_content_jobs set qa=qa||'{"production_candidate":true,"publish_blocked":false}' where id=jid;
raise exception 'TEST_SHADOW_PROMOTION_BYPASS';
exception when others then if sqlerrm<>'E2E_ADMISSION_CLOSED_TO_LEGACY_PRODUCTION' then raise;end if;end;
begin
perform public.sc_v5_command_complete_v1(c.command_id,c.claim_token,true,'{}',null) from sc_internal.v5_commands c join sc_internal.e2e_window w using(command_id);
raise exception 'TEST_UNFENCED_COMPLETION';
exception when others then if sqlerrm<>'E2E_FENCED_COMPLETION_REQUIRED' then raise;end if;end;
begin
insert into public.sc_content_posts(job_id) select p.job_id from sc_internal.factory_permits p join sc_internal.e2e_window w using(command_id);
raise exception 'TEST_PUBLICATION_BYPASS';
exception when others then if sqlerrm<>'E2E_PUBLICATION_FORBIDDEN' then raise;end if;end;
end $$;
rollback;
select count(*) jobs_after_rollback from public.sc_content_jobs;
