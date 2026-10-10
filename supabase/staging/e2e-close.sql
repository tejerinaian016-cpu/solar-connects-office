begin;
update public.sc_agent_config set config=(select details->'config' from public.sc_system_health where component='staging_e2e_backup') where id='solar_connects_v1' and exists(select 1 from public.sc_system_health where component='staging_e2e_backup');
update public.sc_system_health h set status=x->>'status',details=x->'details' from public.sc_system_health b cross join lateral jsonb_array_elements(b.details->'quality') x where b.component='staging_e2e_backup' and h.component=x->>'component';
update sc_internal.e2e_window set enabled=false,step_token=null,step_until=null;
update sc_internal.factory_permits set revoked_at=coalesce(revoked_at,clock_timestamp()) where command_id in(select command_id from sc_internal.e2e_window);
update auth.sessions set not_after=clock_timestamp() where user_id in ('82029bb8-b024-40c1-ad8a-c9393b298fbf','6ea3d73f-474b-4dcf-9373-8f175cdd8fc8');
commit;
