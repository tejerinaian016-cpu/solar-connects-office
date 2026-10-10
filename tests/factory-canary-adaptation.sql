-- Delta tests only, staging. Every fixture and mutation rolls back.
begin;
create temporary table canary_delta_results(test text,passed boolean);
do $$
declare cmd uuid:=extensions.gen_random_uuid(); rid uuid:=extensions.gen_random_uuid();
 actor uuid:='82029bb8-b024-40c1-ad8a-c9393b298fbf'; exp timestamptz:=now()+interval '10 minutes';
 approval jsonb; jid uuid; result jsonb;
begin
approval:=jsonb_build_object('authorized',true,'evidence_ref','fixture://candidate-delta-tests','command_id',cmd,'run_id',rid,'actor',actor,
'plan_hash',repeat('a',64),'quality_sha256',encode(extensions.digest('{}'::jsonb::text,'sha256'),'hex'),
'policy_epoch','delta-test','expires_at',exp,'max_jobs',1,'stop_at','READY');
insert into sc_internal.factory_canaries(command_id,actor,run_id,plan_hash,quality,policy_epoch,approval,expires_at)
values(cmd,actor,rid,repeat('a',64),'{}','delta-test',approval,exp);
update sc_internal.factory_canaries set enabled=true where command_id=cmd;
insert into canary_delta_results values('exact individual approval accepted',true);
begin
declare cmd2 uuid:=extensions.gen_random_uuid();rid2 uuid:=extensions.gen_random_uuid();
begin
insert into sc_internal.factory_canaries(command_id,actor,run_id,plan_hash,quality,policy_epoch,approval,expires_at,enabled)
values(cmd2,actor,rid2,repeat('a',64),'{}','delta-test',approval||jsonb_build_object('command_id',cmd2,'run_id',rid2),exp,true);
raise exception 'TEST_SECOND_ACTIVE';
end;
exception when unique_violation then null;end;
insert into canary_delta_results values('second enabled authorization rejected',true);
begin
insert into public.sc_content_jobs(status,qa) values('PLANNED','{}');
raise exception 'TEST_BYPASS';
exception when others then if sqlerrm<>'CANARY_LEGACY_ADMISSION_CLOSED' then raise;end if;end;
insert into canary_delta_results values('legacy production denied by new admission',true);
insert into public.sc_content_jobs(status,qa) values('SHADOW','{"shadow":true,"do_not_publish":true,"publish_blocked":true,"production_candidate":false,"release_gate":"HOLD"}') returning id into jid;
begin
update public.sc_content_jobs set qa=qa||'{"quality_v2_production_draft":true}' where id=jid;
raise exception 'TEST_LATE_ANNOTATION';
exception when others then if sqlerrm<>'CANARY_OTHER_PRODUCER' then raise;end if;end;
insert into canary_delta_results values('SHADOW accepted; late production denied',true);
begin
update sc_internal.factory_canaries set plan_hash=repeat('b',64) where command_id=cmd;
raise exception 'TEST_IDENTITY_CHANGE';
exception when others then if sqlerrm<>'CANARY_AUTHORIZATION_IMMUTABLE' then raise;end if;end;
begin
delete from sc_internal.factory_canaries where command_id=cmd;
raise exception 'TEST_HISTORY_DELETE';
exception when others then if sqlerrm<>'CANARY_HISTORY_PERMANENT' then raise;end if;end;
insert into canary_delta_results values('authorization immutable and undeletable',true);
begin
insert into sc_internal.factory_canaries(command_id,actor,run_id,plan_hash,quality,policy_epoch,approval,expires_at,enabled)
values(extensions.gen_random_uuid(),actor,extensions.gen_random_uuid(),repeat('a',64),'{}','delta-test',approval,exp,true);
raise exception 'TEST_APPROVAL_REUSE';
exception when others then if sqlerrm<>'CANARY_EXPLICIT_APPROVAL_REQUIRED' then raise;end if;end;
insert into canary_delta_results values('approval cannot be reused for another identity',true);
update sc_internal.factory_canaries set enabled=false,completed=true where command_id=cmd;
begin
update sc_internal.factory_canaries set enabled=true where command_id=cmd;
raise exception 'TEST_REARM';
exception when others then if sqlerrm<>'CANARY_CANNOT_REARM' then raise;end if;end;
insert into canary_delta_results values('completed authorization cannot rearm',true);
-- Archived entry still blocks publication even with NO active window.
insert into public.sc_creative_runs(id,run_key,idempotency_key,status,current_stage) values(rid,'candidate-delta','candidate-delta','APPROVED','DONE');
insert into sc_internal.v5_commands(command_id,actor_user_id,idempotency_key,request_hash,command_type,mode,target,payload,confirmation_intent,status,correlation_id)
values(cmd,actor,'candidate-delta',repeat('a',64),'factory.start','EXECUTE','{}','{}','REAL_EXECUTION','FAILED',extensions.gen_random_uuid());
insert into sc_internal.factory_permits(command_id,creative_run_id,actor_user_id,idempotency_key,request_hash,compiled_plan,plan_sha256,quality_input,quality_slot,claim_token,lease_version,expires_at,job_id,consumed_at,revoked_at)
values(cmd,rid,actor,'candidate-delta',repeat('a',64),'{}',repeat('a',64),'{}',1,extensions.gen_random_uuid(),1,exp,jid,now(),now());
begin
insert into public.sc_content_posts(job_id) values(jid);
raise exception 'TEST_ARCHIVED_PUBLICATION';
exception when others then if sqlerrm<>'CANARY_PUBLICATION_FORBIDDEN' then raise;end if;end;
insert into canary_delta_results values('archived canary publication fence persists',true);
if has_function_privilege('authenticated','sc_internal.factory_canary_start(jsonb)','EXECUTE')
or has_function_privilege('authenticated','public.sc_factory_canary_progress(jsonb)','EXECUTE')
or has_table_privilege('service_role','sc_internal.factory_canaries','INSERT,UPDATE,DELETE') then raise exception 'TEST_GRANTS';end if;
insert into canary_delta_results values('privileged routes and registry inaccessible',true);
end $$;
select jsonb_agg(to_jsonb(t)) results from canary_delta_results t;
rollback;
