-- STAGING-only fixture fence, independent of global gate configuration.
create function sc_internal.staging_no_publication() returns trigger
language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.sc_system_health where component='staging_ready_fixture' and details->>'job_id'=new.job_id::text) then
 raise exception 'SYNTHETIC_FIXTURE_PUBLICATION_FORBIDDEN';
 end if;
 return new;
end $$;
revoke all on function sc_internal.staging_no_publication() from public,anon,authenticated,service_role;
create trigger staging_fixture_no_post before insert or update on public.sc_content_posts for each row execute function sc_internal.staging_no_publication();
create trigger staging_fixture_no_publish_guard before insert or update on public.sc_publish_guard for each row execute function sc_internal.staging_no_publication();
