-- STAGING ONLY. Existing V5 terminal transition; never relabel the old draft as READY.
begin;
do $$ declare c sc_internal.v5_commands; p sc_internal.factory_permits; j public.sc_content_jobs; r jsonb;
begin
select * into c from sc_internal.v5_commands where command_id='aea519fc-8b80-4880-b764-6af753623a22' for update;
if c.status='FAILED' and c.error->>'code'='STAGING_INVALID_DRAFT_ABANDONED' then return;end if;
select * into p from sc_internal.factory_permits where command_id=c.command_id for update;
select * into j from public.sc_content_jobs where id=p.job_id for update;
if c.status<>'EXECUTING' or c.claim_expires_at>=clock_timestamp() or p.revoked_at is null
or j.id is distinct from '85beaf87-34d1-4684-b5ed-519c955e6637'::uuid
or j.status<>'QUALITY_V2_SHADOW_RENDERING' or j.asset_urls<>'[]'::jsonb
then raise exception 'RECONCILIATION_PRECONDITION_FAILED';end if;
r:=public.sc_v5_command_complete_v1(c.command_id,c.claim_token,false,null,
jsonb_build_object('code','STAGING_INVALID_DRAFT_ABANDONED','reason','Expired lease, revoked permit, original synthetic plan rejected by Quality preflight; no READY or rendered job artifact.',
'job_id',j.id,'job_status',j.status,'previous_result',c.result,'ready',false,'production_authorization',false,
'quality_errors',jsonb_build_array('LAYOUT_FORMAT','THEME','HOOK_FAMILY','ADDED_VALUE_REQUIRED')));
if r->>'state'<>'FAILED' then raise exception 'V5_COMPLETION_REJECTED %',r;end if;
end $$;
commit;
select command_id,status,completed_at,error from sc_internal.v5_commands where command_id='aea519fc-8b80-4880-b764-6af753623a22';
