create function sc_internal.canary_admission_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare active sc_internal.factory_canaries; bound sc_internal.factory_canaries; permit_row sc_internal.factory_permits; safe_shadow boolean;
begin
 -- Activation takes the exclusive counterpart: no insert can cross an activation race.
 perform pg_catalog.pg_advisory_xact_lock_shared(701628340);
 select * into active from sc_internal.factory_canaries where enabled for share;
 if tg_table_name<>'sc_content_jobs' then
 if exists(select 1 from sc_internal.factory_canaries w join sc_internal.factory_permits p using(command_id) where p.job_id=new.job_id) then raise exception 'CANARY_PUBLICATION_FORBIDDEN';end if;
 return new;end if;
 select w.* into bound from sc_internal.factory_canaries w left join sc_internal.factory_permits p using(command_id)
 where p.job_id=new.id or w.run_id in(
 sc_internal.factory_run_uuid(new.qa->>'creative_run_id'),
 sc_internal.factory_run_uuid(new.content_plan->>'creative_run_id'),
 sc_internal.factory_run_uuid(substring(new.content_plan->>'idempotency_key' from '^quality-v2-shadow:factory_run_([0-9a-f]{32})$')))
 limit 1 for share of w;
 safe_shadow:=coalesce(new.qa->>'shadow'='true' and new.qa->>'do_not_publish'='true'
 and new.qa->>'publish_blocked'='true' and new.qa->>'production_candidate'='false'
 and new.qa->>'release_gate'='HOLD' and upper(new.status) not in ('PUBLISHING','PUBLISHED')
 and new.instagram_result='{}'::jsonb,false);
 if active.command_id is not null then
 if not safe_shadow then raise exception 'CANARY_LEGACY_ADMISSION_CLOSED';end if;
 if (new.qa ? 'factory_command_id' or new.qa->>'quality_v2_production_draft'='true')
 and bound.command_id is distinct from active.command_id then raise exception 'CANARY_OTHER_PRODUCER';end if;
 end if;
 if bound.command_id is not null then
 if not safe_shadow then raise exception 'CANARY_PUBLICATION_FORBIDDEN';end if;
 select * into permit_row from sc_internal.factory_permits where command_id=bound.command_id;
 if tg_op='INSERT' and (permit_row.active_xid is distinct from txid_current() or permit_row.job_id is distinct from new.id) then raise exception 'CANARY_TRANSACTION_PERMIT';end if;
 if tg_op='UPDATE' then
 if old.content_plan is distinct from new.content_plan then raise exception 'CANARY_PLAN_IMMUTABLE';end if;
 if old.status='READY' and new is distinct from old then raise exception 'CANARY_READY_SEALED';end if;
 if new.status='READY' and current_setting('sc.canary_finalize',true) is distinct from bound.command_id::text then raise exception 'CANARY_FINALIZER_REQUIRED';end if;
 end if;
 end if;
 return new;
end $$;
