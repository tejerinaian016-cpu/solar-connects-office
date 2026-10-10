-- Structural rollback allowed only BEFORE any authorization record exists.
-- Once used, apply operational rollback and retain permanent publication fences.
begin;
select pg_advisory_xact_lock(701628340);
do $$ begin if exists(select 1 from sc_internal.factory_canaries) then raise exception 'USED_CANARY_REQUIRES_PERMANENT_FENCES';end if;end $$;
drop trigger zz_canary_admission on public.sc_content_jobs;
drop trigger canary_no_post on public.sc_content_posts;
drop trigger canary_no_publish_guard on public.sc_publish_guard;
drop trigger canary_fenced_completion on sc_internal.v5_commands;
drop function public.sc_factory_canary_v1(jsonb);
drop function public.sc_factory_canary_progress(jsonb);
drop function sc_internal.factory_canary_start(jsonb);
drop function sc_internal.canary_assert(uuid,uuid,bigint);
drop function sc_internal.canary_admission_guard();
drop function sc_internal.canary_completion_guard();
drop trigger canary_registry_immutable on sc_internal.factory_canaries;
drop trigger canary_registry_lock on sc_internal.factory_canaries;
drop function sc_internal.canary_registry_guard();
drop function sc_internal.canary_registry_lock();
drop table sc_internal.factory_canaries;
commit;
