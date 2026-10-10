create unique index factory_one_enabled_canary on sc_internal.factory_canaries(enabled) where enabled;

create function sc_internal.canary_registry_lock() returns trigger
language plpgsql set search_path='' as $$
begin perform pg_catalog.pg_advisory_xact_lock(701628340);return null;end $$;
revoke all on function sc_internal.canary_registry_lock() from public,anon,authenticated,service_role;
create trigger canary_registry_lock before insert or update or delete on sc_internal.factory_canaries
for each statement execute function sc_internal.canary_registry_lock();

create function sc_internal.canary_registry_guard() returns trigger
language plpgsql set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(701628340);
 if tg_op='DELETE' then raise exception 'CANARY_HISTORY_PERMANENT';end if;
 if tg_op='UPDATE' then
 if row(new.command_id,new.actor,new.run_id,new.plan_hash,new.quality,new.policy_epoch,new.approval,new.expires_at)
 is distinct from row(old.command_id,old.actor,old.run_id,old.plan_hash,old.quality,old.policy_epoch,old.approval,old.expires_at)
 then raise exception 'CANARY_AUTHORIZATION_IMMUTABLE';end if;
 if old.expected_plan is not null and new.expected_plan is distinct from old.expected_plan then raise exception 'CANARY_PLAN_IMMUTABLE';end if;
 end if;
 if new.enabled and (new.completed or exists(select 1 from sc_internal.factory_permits where command_id=new.command_id and revoked_at is not null)) then raise exception 'CANARY_CANNOT_REARM';end if;
 if new.enabled and (new.expires_at<=clock_timestamp() or new.approval->>'authorized' is distinct from 'true'
 or coalesce(new.approval->>'evidence_ref','')='' or new.approval->>'command_id' is distinct from new.command_id::text
 or new.approval->>'plan_hash' is distinct from new.plan_hash
 or new.approval->>'run_id' is distinct from new.run_id::text
 or new.approval->>'actor' is distinct from new.actor::text
 or new.approval->>'quality_sha256' is distinct from encode(extensions.digest(new.quality::text,'sha256'),'hex')
 or new.approval->>'policy_epoch' is distinct from new.policy_epoch
 or (new.approval->>'expires_at')::timestamptz is distinct from new.expires_at
 or new.approval->>'max_jobs' is distinct from '1' or new.approval->>'stop_at' is distinct from 'READY')
 then raise exception 'CANARY_EXPLICIT_APPROVAL_REQUIRED';end if;
 return new;
end $$;
revoke all on function sc_internal.canary_registry_guard() from public,anon,authenticated,service_role;
create trigger canary_registry_immutable before insert or update or delete on sc_internal.factory_canaries
for each row execute function sc_internal.canary_registry_guard();

-- No public provisioning, activation or expiry extension API. DBA approval transaction only.
