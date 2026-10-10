-- STAGING ONLY. Invoker/owner-only finalization, not an exposed service RPC.
create or replace function sc_internal.staging_ready(p_job uuid) returns jsonb
language plpgsql set search_path='' as $$
declare j public.sc_content_jobs; b jsonb; d jsonb; result jsonb; op text; fact public.sc_fact_bank; total int; complete int; rb timestamptz;
begin
 select details into b from public.sc_system_health where component='staging_ready_fixture' for update;
 if b->>'job_id' is distinct from p_job::text or b->>'synthetic' is distinct from 'true' then raise exception 'STAGING_FIXTURE_REQUIRED'; end if;
 select * into j from public.sc_content_jobs where id=p_job for update;
 foreach op in array array['FACTORY','PUBLISHER','META_DIRECT','EXTERNAL_WRITE'] loop
 if public.sc_security_operation_gate_v1(op)->>'allowed' is distinct from 'false' then raise exception 'GATES_MUST_BE_OFF'; end if;end loop;
 if public.sc_creative_compile_carousel_v1((b->>'run_id')::uuid) is distinct from b->'compiled'
 or encode(extensions.digest((b->'compiled')::text,'sha256'),'hex') is distinct from b->>'compiled_sha256'
 or j.content_plan#>'{quality_v2,pages,0}' is distinct from b->'plan'
 then raise exception 'IMMUTABLE_PLAN_CONFLICT'; end if;
 if j.qa->>'do_not_publish' is distinct from 'true' or j.qa->>'publish_blocked' is distinct from 'true' or j.qa->>'production_candidate' is distinct from 'false' then raise exception 'PUBLICATION_BLOCK_REQUIRED';end if;
 if j.status='READY' then return jsonb_build_object('ok',true,'idempotent',true,'job_id',p_job,'status','READY','publication_allowed',false);end if;
 if j.status<>'QUALITY_V2_SHADOW_RENDERING' then raise exception 'SHADOW_RENDER_REQUIRED';end if;
 select * into fact from public.sc_fact_bank where fact_id='SC-STAGING-DATA-001' for share;
 select count(*),count(*) filter(where (x->>'complete')::boolean) into total,complete from jsonb_array_elements(fact.metadata#>'{dataset,records}')x;
 if fact.status is distinct from 'APPROVED' or fact.scope is distinct from 'SYNTHETIC_STAGING_ONLY' or total<>12 or complete<>9
 or fact.metadata->>'dataset_sha256' is distinct from encode(extensions.digest((fact.metadata->'dataset')::text,'sha256'),'hex')
 or j.qa#>>'{claims_ledger,0,claim}' is distinct from fact.claim then raise exception 'FIXTURE_FACT_CONFLICT';end if;
 d:=j.qa#>'{quality_v2_runtime,guardian_pending_evidence}';
 if d is null then raise exception 'GUARDIAN_EVIDENCE_REQUIRED';end if;
 rb:=(j.qa#>>'{quality_v2_runtime,staging_readback_at}')::timestamptz;
 if rb is null or rb<clock_timestamp()-interval '10 minutes' or rb>clock_timestamp() then raise exception 'FRESH_GUARDIAN_READBACK_REQUIRED';end if;
 result:=public.sc_quality_shadow_record_v2(p_job,d);
 if result->>'ok' is distinct from 'true' then raise exception 'GUARDIAN_REJECTED %',result;end if;
 select details into d from public.sc_system_health where component='solar_quality_v2_job_'||p_job;
 if d->>'guardian_state' is distinct from 'PASS_SHADOW'
 or d->>'job_plan_sha256' is distinct from encode(extensions.digest(j.content_plan::text,'sha256'),'hex')
 then raise exception 'DURABLE_GUARDIAN_REQUIRED';end if;
 update public.sc_content_jobs set status='READY',qa=qa||'{"shadow":true,"production_candidate":false,"do_not_publish":true,"publish_blocked":true,"release_gate":"HOLD","staging_only":true,"quality_v2_phase":"STAGING_READY"}',updated_at=now() where id=p_job;
 update public.sc_system_health set status='STAGING_READY_BLOCKED',details=details||jsonb_build_object('ready_at',now(),'publication_allowed',false) where component='staging_ready_fixture';
 return jsonb_build_object('ok',true,'job_id',p_job,'status','READY','guardian','PASS_SHADOW','publication_allowed',false);
end $$;
revoke all on function sc_internal.staging_ready(uuid) from public,anon,authenticated,service_role;

-- Permanently hold this fixture; normal producers and the old draft are untouched.
create function sc_internal.staging_ready_guard() returns trigger
language plpgsql set search_path='' as $$
declare b jsonb;
begin
 select details into b from public.sc_system_health where component='staging_ready_fixture';
 if new.id::text=b->>'job_id' then
 if new.content_plan is distinct from old.content_plan then raise exception 'STAGING_PLAN_IMMUTABLE';end if;
 if new.qa->>'do_not_publish' is distinct from 'true' or new.qa->>'publish_blocked' is distinct from 'true'
 or new.qa->>'production_candidate' is distinct from 'false' or new.qa->>'release_gate' is distinct from 'HOLD'
 or new.instagram_result is distinct from old.instagram_result then raise exception 'STAGING_PUBLICATION_FORBIDDEN';end if;
 if old.status='READY' and new is distinct from old then raise exception 'STAGING_READY_SEALED';end if;
 if new.status='READY' and old.status<>'READY' and not exists(select 1 from public.sc_system_health where component='solar_quality_v2_job_'||new.id and status='GUARDIAN_PASS_SHADOW' and details->>'guardian_state'='PASS_SHADOW') then raise exception 'DURABLE_GUARDIAN_REQUIRED';end if;
 end if;
 return new;
end $$;
revoke all on function sc_internal.staging_ready_guard() from public,anon,authenticated,service_role;
create trigger staging_ready_fixture_guard before update on public.sc_content_jobs for each row execute function sc_internal.staging_ready_guard();
