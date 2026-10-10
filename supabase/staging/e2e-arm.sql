begin;
insert into public.sc_system_health(component,status,details) select 'staging_e2e_backup','SNAPSHOT',jsonb_build_object('config',(select config from public.sc_agent_config where id='solar_connects_v1'),'quality',(select jsonb_agg(jsonb_build_object('component',component,'status',status,'details',details)) from public.sc_system_health where component in ('solar_quality_v2_production_flags','solar_quality_v2_first_slot'))) on conflict(component) do nothing;
update sc_internal.e2e_window set enabled=true,expires_at=clock_timestamp()+interval '60 minutes';
update public.sc_agent_config set config=jsonb_set(config,'{security_control_plane_v1,kill_switches,factory,allow}','true') where id='solar_connects_v1';
update public.sc_system_health set status='STAGING_E2E_ONLY',details=details||'{"stage":1,"comparison_gate":"PASS","comparison_scope":"SYNTHETIC_TEST_POLICY_NOT_PRODUCTION_APPROVAL","epoch":"staging-e2e-002"}'||jsonb_build_object('formats',jsonb_set(details->'formats','{image,kill_switch}','false')) where component='solar_quality_v2_production_flags';
update public.sc_system_health set status='ARMED',details='{"enabled":true,"state":"ARMED","synthetic":true}' where component='solar_quality_v2_first_slot';
commit;
