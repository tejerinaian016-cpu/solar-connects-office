-- Read-only source snapshot from live project. NOT a migration; do not execute.
CREATE OR REPLACE FUNCTION public.sc_creative_materialize_job_v1(p_run_id uuid, p_mode text DEFAULT 'SHADOW'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_mode,'SHADOW')));
  c jsonb;
  g jsonb;
  existing_id uuid;
  existing_status text;
  jid uuid;
  q jsonb;
begin
  if v_mode not in ('SHADOW','PRODUCTION') then
    return jsonb_build_object('ok',false,'reason','MODE_INVALID');
  end if;

  select id,status into existing_id,existing_status
  from public.sc_content_jobs
  where content_plan->>'creative_run_id'=p_run_id::text or qa->>'creative_run_id'=p_run_id::text
  order by created_at desc
  limit 1;

  if existing_id is not null then
    return jsonb_build_object('ok',true,'state','DUPLICATE','job_id',existing_id,'status',existing_status);
  end if;

  c:=public.sc_creative_compile_carousel_v1(p_run_id);
  if coalesce((c->>'ok')::boolean,false) is not true then
    return jsonb_build_object('ok',false,'reason','COMPILE_FAILED','compile',c);
  end if;

  if v_mode='PRODUCTION' and public.sc_quality_factory_hook_v2(p_run_id,null)->>'route'='V2' then
    return jsonb_build_object('ok',false,'reason','QUALITY_V2_ADAPTER_REQUIRED','factory_hook',public.sc_quality_factory_hook_v2(p_run_id,null),'external_write',false);
  end if;

  if v_mode='PRODUCTION' then
    g:=public.sc_security_operation_gate_v1('FACTORY');
    if coalesce((g->>'allowed')::boolean,false) is not true then
      return jsonb_build_object('ok',false,'reason','FACTORY_KILL_SWITCH','gate',g);
    end if;
  end if;

  q:=(c->'qa') || jsonb_build_object(
    'shadow',v_mode='SHADOW',
    'production_candidate',v_mode='PRODUCTION',
    'do_not_publish',v_mode='SHADOW',
    'publish_blocked',true,
    'guardian_qa','PENDING',
    'visual_pipeline','premium-v1.2',
    'renderer_target',case when c->>'format'='reel' then 'sc-reel-frame-renderer-2.3.5' else 'solar-render-premium-2.3.5' end,
    'materialization_mode',v_mode
  );

  insert into public.sc_content_jobs(status,trigger_text,topic,format,content_plan,qa)
  values(
    'RENDERING',
    case when v_mode='PRODUCTION' then 'creative-v2-production-materializer' else 'creative-v2-shadow-materializer' end,
    c->>'topic',
    c->>'format',
    (c->'content_plan') || jsonb_build_object('materialization_mode',v_mode),
    q
  )
  returning id into jid;

  return jsonb_build_object(
    'ok',true,'state','CREATED','job_id',jid,'mode',v_mode,
    'external_write',false
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.sc_quality_factory_production_v2(p_run_id uuid, p_quality jsonb, p_slot integer, p_execute boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare c jsonb; route jsonb; d jsonb; r jsonb; jid uuid; req text; old jsonb; firstslot jsonb;
begin
 c:=sc_creative_compile_carousel_v1(p_run_id);if c->>'ok' is distinct from 'true' then return c;end if;
 select details into d from sc_system_health where component='solar_quality_v2_production_flags' for share;
 route:=sc_quality_rollout_decide_v2(coalesce(d,'{}'),c->>'format',p_slot);
 if route->>'ok' is distinct from 'true' then return route;end if;
 if route->>'route'='V1' or p_execute is not true then return route||jsonb_build_object('compiled',c,'legacy_entrypoint','sc_creative_materialize_job_v1','mode','READ_ONLY','external_write',false);end if;
 if sc_security_operation_gate_v1('FACTORY')->>'allowed' is distinct from 'true' then return jsonb_build_object('ok',false,'reason','FACTORY_GATE');end if;
 if c->>'format'<>'story' and sc_feed_daily_budget_v1()->>'allowed' is distinct from 'true' then return jsonb_build_object('ok',false,'reason','BUDGET_HOLD_BEFORE_RENDER');end if;
 req:=encode(extensions.digest(jsonb_build_object('run',p_run_id,'quality',p_quality,'slot',p_slot)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtext('quality-prod-run:'||p_run_id::text));
 select details into old from sc_system_health where component='solar_quality_v2_prod_run_'||p_run_id;
 if old is not null then
 if old->>'request_sha256' is distinct from req then return jsonb_build_object('ok',false,'reason','IDEMPOTENCY_CONFLICT');end if;
 return old||jsonb_build_object('idempotent',true);
 end if;
 if exists(select 1 from sc_content_jobs j where j.content_plan->>'creative_run_id'=p_run_id::text or j.qa->>'creative_run_id'=p_run_id::text) or exists(select 1 from sc_system_health where details#>>'{factory_output,creative_run_id}'=p_run_id::text) then return jsonb_build_object('ok',false,'reason','EXISTING_RUN_NOT_PROMOTABLE');end if;
 select details into firstslot from sc_system_health where component='solar_quality_v2_first_slot' for update;
 if firstslot->>'enabled'='true' then
 if c->>'format'<>'image' or p_slot<>1 or (firstslot->>'run_id' is not null and firstslot->>'run_id'<>p_run_id::text) or firstslot->>'state' not in ('ARMED','DRAFT') then return jsonb_build_object('ok',false,'reason','FIRST_SLOT_ALREADY_BOUND_OR_INELIGIBLE');end if;
 end if;
 r:=sc_quality_factory_from_run_v2(p_run_id,p_quality,jsonb_build_object('enabled',true,'mode','SHADOW','formats',jsonb_build_array(c->>'format')));
 if r->>'ok' is distinct from 'true' then return r;end if;
 jid:=(r->>'job_id')::uuid;
 if firstslot->>'enabled'='true' then update sc_system_health set details=details||jsonb_build_object('run_id',p_run_id,'job_id',jid,'state','DRAFT'),status='DRAFT',checked_at=now() where component='solar_quality_v2_first_slot';end if;
 update sc_content_jobs set qa=qa||jsonb_build_object('creative_run_id',p_run_id,'quality_v2_production_draft',true),updated_at=now() where id=jid;
 d:=jsonb_build_object('ok',true,'job_id',jid,'creative_run_id',p_run_id,'slot',p_slot,'format',c->>'format','policy_epoch',route->'policy_epoch','request_sha256',req,'original_compiled',c,'state','V2_DRAFT_BLOCKED','external_write',false);
 insert into sc_system_health(component,version,status,details) values('solar_quality_v2_prod_run_'||p_run_id,'2.0-prod-prep.1','DRAFT_BLOCKED',d);
 insert into sc_system_health(component,version,status,details) values('solar_quality_v2_prod_job_'||jid,'2.0-prod-prep.1','DRAFT_BLOCKED',d);
 return d;
end $function$


CREATE OR REPLACE FUNCTION public.sc_security_operation_gate_v1(p_operation text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
with cfg as (
  select config #> '{security_control_plane_v1,kill_switches}' ks
  from public.sc_agent_config
  where id='solar_connects_v1'
),
op as (
  select upper(trim(coalesce(p_operation,''))) operation,
         coalesce(ks,'{}'::jsonb) ks
  from cfg
)
select jsonb_build_object(
  'operation',operation,
  'allowed',
    case operation
      when 'READ_OBSERVATION' then true
      when 'EXTERNAL_WRITE' then coalesce((ks #>> '{external_write,allow}')::boolean,false)
      when 'FACTORY' then coalesce((ks #>> '{factory,allow}')::boolean,false)
      when 'PUBLISHER' then coalesce((ks #>> '{publisher,allow}')::boolean,false)
      when 'META_DIRECT' then coalesce((ks #>> '{meta_direct,allow}')::boolean,false)
      when 'LEARNING_MUTATION' then coalesce((ks #>> '{learning_mutation,allow}')::boolean,false)
      else false
    end,
  'fail_closed',true,
  'source','sc_agent_config.security_control_plane_v1.kill_switches'
)
from op
union all
select jsonb_build_object(
  'operation',upper(trim(coalesce(p_operation,''))),
  'allowed',upper(trim(coalesce(p_operation,'')))='READ_OBSERVATION',
  'fail_closed',true,
  'source','MISSING_CONFIG_DEFAULT'
)
where not exists(select 1 from cfg)
limit 1
$function$


CREATE OR REPLACE FUNCTION public.sc_v5_command_claim_v1(p_command_id uuid, p_actor_user_id uuid, p_idempotency_key text, p_command_type text, p_target jsonb, p_payload jsonb, p_confirmation_intent text, p_mode text, p_correlation_id uuid DEFAULT NULL::uuid, p_lease_seconds integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'sc_internal', 'extensions'
AS $function$
declare
  v_now timestamptz := clock_timestamp();
  v_lease_seconds integer := greatest(15, least(coalesce(p_lease_seconds,90),300));
  v_key text := trim(coalesce(p_idempotency_key,''));
  v_type text := trim(coalesce(p_command_type,''));
  v_mode text := upper(trim(coalesce(p_mode,'')));
  v_intent text := trim(coalesce(p_confirmation_intent,''));
  v_target jsonb := coalesce(p_target,'{}'::jsonb);
  v_payload jsonb := coalesce(p_payload,'{}'::jsonb);
  v_hash text;
  v_corr uuid := coalesce(p_correlation_id, extensions.gen_random_uuid());
  v_token uuid;
  v_row sc_internal.v5_commands%rowtype;
  v_inserted boolean := false;
  v_reclaimed boolean := false;
  v_audit jsonb;
begin
  if p_command_id is null or p_actor_user_id is null then
    return jsonb_build_object('ok',false,'state','INVALID','reason','COMMAND_AND_ACTOR_REQUIRED');
  end if;
  if char_length(v_key) < 8 or char_length(v_key) > 200 then
    return jsonb_build_object('ok',false,'state','INVALID','reason','IDEMPOTENCY_KEY_INVALID');
  end if;
  if v_type not in ('factory.start','publisher.publish','recovery.run','learning.rebuild') then
    return jsonb_build_object('ok',false,'state','DENIED','reason','ACTION_NOT_ALLOWED');
  end if;
  if v_mode not in ('SIMULATE','EXECUTE') then
    return jsonb_build_object('ok',false,'state','INVALID','reason','MODE_INVALID');
  end if;
  if char_length(v_intent) < 3 or char_length(v_intent) > 100 then
    return jsonb_build_object('ok',false,'state','INVALID','reason','CONFIRMATION_INTENT_INVALID');
  end if;

  v_hash := public.sc_v5_command_request_hash_v1(v_type,v_target,v_payload,v_intent,v_mode);

  insert into sc_internal.v5_commands(
    command_id,actor_user_id,idempotency_key,request_hash,command_type,mode,
    target,payload,confirmation_intent,status,correlation_id,created_at,updated_at
  ) values (
    p_command_id,p_actor_user_id,v_key,v_hash,v_type,v_mode,
    v_target,v_payload,v_intent,'PENDING',v_corr,v_now,v_now
  )
  on conflict (actor_user_id,idempotency_key) do nothing
  returning * into v_row;

  if found then
    v_inserted := true;
  else
    select * into v_row
    from sc_internal.v5_commands
    where actor_user_id=p_actor_user_id and idempotency_key=v_key
    for update;

    if not found then
      return jsonb_build_object('ok',false,'state','ERROR','reason','CLAIM_ROW_MISSING_AFTER_CONFLICT');
    end if;

    if v_row.request_hash <> v_hash then
      return jsonb_build_object(
        'ok',false,'state','CONFLICT','reason','IDEMPOTENCY_KEY_REQUEST_MISMATCH',
        'command_id',v_row.command_id,'request_hash',v_row.request_hash,
        'correlation_id',v_row.correlation_id
      );
    end if;

    if v_row.status in ('SUCCEEDED','FAILED','ROLLED_BACK') then
      return jsonb_build_object(
        'ok',true,'state','DUPLICATE_TERMINAL','reason','IDEMPOTENT_REPLAY',
        'command_id',v_row.command_id,'request_hash',v_row.request_hash,
        'status',v_row.status,'result',v_row.result,'error',v_row.error,
        'correlation_id',v_row.correlation_id,'executed',false
      );
    end if;

    if v_row.status in ('CLAIMED','EXECUTING') and v_row.claim_expires_at is not null and v_row.claim_expires_at > v_now then
      return jsonb_build_object(
        'ok',true,'state','IN_PROGRESS','reason','LEASE_ACTIVE',
        'command_id',v_row.command_id,'request_hash',v_row.request_hash,
        'status',v_row.status,'lease_version',v_row.lease_version,
        'claim_expires_at',v_row.claim_expires_at,'correlation_id',v_row.correlation_id,
        'executed',false
      );
    end if;

    if v_row.status in ('CLAIMED','EXECUTING') then
      v_reclaimed := true;
    end if;
  end if;

  v_token := extensions.gen_random_uuid();

  update sc_internal.v5_commands
  set status='CLAIMED',
      claimed_at=v_now,
      claim_expires_at=v_now + make_interval(secs=>v_lease_seconds),
      claim_token=v_token,
      lease_version=lease_version+1,
      updated_at=v_now
  where id=v_row.id
  returning * into v_row;

  v_audit := public.sc_record_security_mutation_v1(
    'v5_command:'||v_row.command_id::text,
    case when v_reclaimed then 'COMMAND_RECLAIMED' else 'COMMAND_CLAIMED' end,
    null,
    jsonb_build_object('status','CLAIMED','lease_version',v_row.lease_version),
    'USER_EXPLICIT',
    case when v_reclaimed then 'expired lease safely reclaimed' else 'durable command claim' end,
    v_row.correlation_id::text,
    jsonb_build_object(
      'command_id',v_row.command_id,'actor_user_id',v_row.actor_user_id,
      'request_hash',v_row.request_hash,'mode',v_row.mode,'command_type',v_row.command_type,'test',false
    )
  );

  return jsonb_build_object(
    'ok',true,'state','CLAIMED',
    'reason',case when v_reclaimed then 'LEASE_RECLAIMED' else 'CLAIM_ACQUIRED' end,
    'command_id',v_row.command_id,'request_hash',v_row.request_hash,
    'claim_token',v_row.claim_token,'lease_version',v_row.lease_version,
    'claim_expires_at',v_row.claim_expires_at,'correlation_id',v_row.correlation_id,
    'inserted',v_inserted,'reclaimed',v_reclaimed,'audit',v_audit,'executed',false
  );
exception when unique_violation then
  return jsonb_build_object('ok',false,'state','CONFLICT','reason','COMMAND_ID_CONFLICT');
end;
$function$


CREATE OR REPLACE FUNCTION public.sc_v5_execute_learning_rebuild_v1(p_command_id uuid, p_claim_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'sc_internal'
AS $function$
declare
  v_step text := 'gate';
  v_now timestamptz := clock_timestamp();
  v_gate jsonb;
  v_cmd sc_internal.v5_commands%rowtype;
  v_exec jsonb;
  v_rebuild jsonb;
  v_done jsonb;

  b_rows int; b_actionable int; b_no_conclusion int; b_hash text;
  b_learned_posts int; b_max_learned_at timestamptz;
  b_valid_measurements int; b_latest_measurement timestamptz;

  a_rows int; a_actionable int; a_no_conclusion int; a_hash text;
  a_learned_posts int; a_max_learned_at timestamptz;
  a_valid_measurements int; a_latest_measurement timestamptz;

  v_result jsonb;

  e_state text;
  e_msg text;
  e_detail text;
  e_hint text;
  e_context text;
  e_error jsonb;
begin
  v_gate := public.sc_security_operation_gate_v1('LEARNING_MUTATION');
  if coalesce((v_gate->>'allowed')::boolean,false) is not true then
    return jsonb_build_object(
      'ok',false,'state','DISABLED','reason','LEARNING_MUTATION_KILL_SWITCH',
      'gate',v_gate,'executed',false,'external_writes',0
    );
  end if;

  v_step := 'load_command';
  select * into v_cmd
  from sc_internal.v5_commands
  where command_id=p_command_id
  for update;

  if not found then
    return jsonb_build_object('ok',false,'state','DENIED','reason','COMMAND_NOT_FOUND','executed',false);
  end if;

  v_step := 'contract';
  if v_cmd.command_type<>'learning.rebuild'
     or v_cmd.mode<>'EXECUTE'
     or v_cmd.confirmation_intent<>'REAL_EXECUTION' then
    return jsonb_build_object('ok',false,'state','DENIED','reason','COMMAND_CONTRACT_MISMATCH','executed',false);
  end if;

  if coalesce(v_cmd.target->>'agent','')<>'LEARNING'
     or nullif(v_cmd.target->>'job_id','') is not null then
    return jsonb_build_object('ok',false,'state','DENIED','reason','TARGET_NOT_ALLOWED','executed',false);
  end if;

  v_step := 'claim_validation';
  if v_cmd.status<>'CLAIMED'
     or v_cmd.claim_token is distinct from p_claim_token
     or v_cmd.claim_expires_at is null
     or v_cmd.claim_expires_at<=v_now then
    return jsonb_build_object('ok',false,'state','DENIED','reason','STALE_OR_INVALID_CLAIM_OWNER','executed',false);
  end if;

  -- Serialize this one mutation class only. Released automatically at transaction end.
  v_step := 'advisory_lock';
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('solar-connects:learning.rebuild',0)
  );

  v_step := 'before_learning_snapshot';
  select count(*)::int,
         count(*) filter(where actionable is true)::int,
         count(*) filter(where conclusion_state='NO_CONCLUSION')::int,
         public.sc_security_hash_v1(
           coalesce(jsonb_agg(
             jsonb_build_object(
               'dimension',dimension,'key',key,'score',score,'sample_count',sample_count,
               'evidence',evidence,'actionable',actionable,'confidence',confidence,
               'conclusion_state',conclusion_state,'score_status',score_status
             ) order by dimension,key
           ),'[]'::jsonb)
         )
  into b_rows,b_actionable,b_no_conclusion,b_hash
  from public.sc_content_learning;

  v_step := 'before_posts_snapshot';
  select count(*) filter(where learned_at is not null)::int,max(learned_at)
  into b_learned_posts,b_max_learned_at
  from public.sc_content_posts;

  v_step := 'before_measurements_snapshot';
  select count(*)::int,max(measured_at)
  into b_valid_measurements,b_latest_measurement
  from public.sc_post_measurements
  where valid_for_learning is true
    and measurement_status in ('VALID','LATE_VALID')
    and contract_version='measurement-contract-v2';

  begin
    v_step := 'mark_executing';
    v_exec := public.sc_v5_command_mark_executing_v1(p_command_id,p_claim_token,120);
    if coalesce((v_exec->>'ok')::boolean,false) is not true then
      return jsonb_build_object(
        'ok',false,'state','DENIED',
        'reason',coalesce(v_exec->>'reason','EXECUTING_TRANSITION_REJECTED'),
        'executed',false
      );
    end if;

    v_step := 'rebuild';
    v_rebuild := public.sc_rebuild_learning();

    v_step := 'after_learning_snapshot';
    select count(*)::int,
           count(*) filter(where actionable is true)::int,
           count(*) filter(where conclusion_state='NO_CONCLUSION')::int,
           public.sc_security_hash_v1(
             coalesce(jsonb_agg(
               jsonb_build_object(
                 'dimension',dimension,'key',key,'score',score,'sample_count',sample_count,
                 'evidence',evidence,'actionable',actionable,'confidence',confidence,
                 'conclusion_state',conclusion_state,'score_status',score_status
               ) order by dimension,key
             ),'[]'::jsonb)
           )
    into a_rows,a_actionable,a_no_conclusion,a_hash
    from public.sc_content_learning;

    v_step := 'after_posts_snapshot';
    select count(*) filter(where learned_at is not null)::int,max(learned_at)
    into a_learned_posts,a_max_learned_at
    from public.sc_content_posts;

    v_step := 'after_measurements_snapshot';
    select count(*)::int,max(measured_at)
    into a_valid_measurements,a_latest_measurement
    from public.sc_post_measurements
    where valid_for_learning is true
      and measurement_status in ('VALID','LATE_VALID')
      and contract_version='measurement-contract-v2';

    v_step := 'build_result';
    v_result := jsonb_build_object(
      'executed',true,
      'executor','sc_rebuild_learning',
      'command_type','learning.rebuild',
      'internal_write_scope',jsonb_build_array(
        'public.sc_content_learning',
        'public.sc_content_posts.learned_at'
      ),
      'external_writes',0,
      'factory_calls',0,
      'publisher_calls',0,
      'recovery_calls',0,
      'meta_calls',0,
      'rebuild_result',v_rebuild,
      'before',jsonb_build_object(
        'learning_rows',b_rows,
        'actionable_rows',b_actionable,
        'no_conclusion_rows',b_no_conclusion,
        'learning_semantic_hash',b_hash,
        'learned_posts',b_learned_posts,
        'max_learned_at',b_max_learned_at,
        'valid_learning_measurements',b_valid_measurements,
        'latest_measurement',b_latest_measurement
      ),
      'after',jsonb_build_object(
        'learning_rows',a_rows,
        'actionable_rows',a_actionable,
        'no_conclusion_rows',a_no_conclusion,
        'learning_semantic_hash',a_hash,
        'learned_posts',a_learned_posts,
        'max_learned_at',a_max_learned_at,
        'valid_learning_measurements',a_valid_measurements,
        'latest_measurement',a_latest_measurement
      ),
      'semantic_state_unchanged',(b_hash=a_hash and b_rows=a_rows),
      'input_measurement_set_unchanged',(
        b_valid_measurements=a_valid_measurements
        and b_latest_measurement is not distinct from a_latest_measurement
      )
    );

    v_step := 'complete_success';
    v_done := public.sc_v5_command_complete_v1(
      p_command_id,p_claim_token,true,v_result,null
    );

    if coalesce((v_done->>'ok')::boolean,false) is not true then
      raise exception 'durable completion rejected';
    end if;

    return jsonb_build_object(
      'ok',true,
      'state','SUCCEEDED',
      'executed',true,
      'command_id',p_command_id,
      'correlation_id',v_done->>'correlation_id',
      'result',v_result,
      'durable',v_done
    );

  exception when others then
    get stacked diagnostics
      e_state = returned_sqlstate,
      e_msg = message_text,
      e_detail = pg_exception_detail,
      e_hint = pg_exception_hint,
      e_context = pg_exception_context;

    e_error := jsonb_strip_nulls(jsonb_build_object(
      'code','LEARNING_REBUILD_FAILED',
      'step',v_step,
      'sqlstate',e_state,
      'message',e_msg,
      'detail',nullif(e_detail,''),
      'hint',nullif(e_hint,''),
      'context',nullif(e_context,'')
    ));

    -- Inner subtransaction rollback restores CLAIMED if anything above failed.
    v_exec := public.sc_v5_command_mark_executing_v1(p_command_id,p_claim_token,120);
    if coalesce((v_exec->>'ok')::boolean,false) is true then
      v_done := public.sc_v5_command_complete_v1(
        p_command_id,p_claim_token,false,null,e_error
      );
    end if;

    return jsonb_build_object(
      'ok',false,
      'state','FAILED',
      'reason','LEARNING_REBUILD_FAILED',
      'executed',false,
      'external_writes',0,
      'diagnostic',e_error,
      'durable',v_done
    );
  end;
end;
$function$


CREATE OR REPLACE FUNCTION public.sc_creative_compile_carousel_v1(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.sc_creative_runs%rowtype;
  e jsonb;
  d jsonb;
  cand jsonb;
  es jsonb;
  ds jsonb;
  slides jsonb='[]'::jsonb;
  i int;
  fmt text;
  n int;
begin
  select * into r from public.sc_creative_runs where id=p_run_id;
  if r.id is null then return jsonb_build_object('ok',false,'reason','RUN_NOT_FOUND'); end if;
  if r.status<>'APPROVED' then return jsonb_build_object('ok',false,'reason','RUN_NOT_APPROVED'); end if;

  select output into e
  from public.sc_creative_stage_outputs
  where run_id=p_run_id and stage='EDITOR' and validation_status='VALID' and schema_version='editor-v2'
  order by attempt desc limit 1;

  select output into d
  from public.sc_creative_stage_outputs
  where run_id=p_run_id and stage='DIRECTOR' and validation_status='VALID' and schema_version='director-v2'
  order by attempt desc limit 1;

  if e is null or d is null then return jsonb_build_object('ok',false,'reason','V2_STAGE_OUTPUTS_REQUIRED'); end if;

  select value into cand
  from jsonb_array_elements(e->'candidates')
  where value->>'candidate_id'=d->>'candidate_id'
  limit 1;
  if cand is null then return jsonb_build_object('ok',false,'reason','SELECTED_CANDIDATE_MISSING'); end if;

  fmt:=lower(coalesce(cand->>'format',''));
  if fmt not in ('carousel','image','story','reel') or lower(coalesce(d->>'format',''))<>fmt then return jsonb_build_object('ok',false,'reason','FORMAT_BINDING_INVALID'); end if;
  n:=case when fmt='carousel' then 5 when fmt='reel' then 3 else 1 end;
  if jsonb_array_length(cand#>'{plan,slides}')<>n or jsonb_array_length(d->'slides')<>n then return jsonb_build_object('ok',false,'reason','FORMAT_SLIDE_COUNT_INVALID'); end if;
  for i in 1..n loop
    es:=cand#>('{'||'plan,slides,'||(i-1)||'}')::text[];
    ds:=d#>('{'||'slides,'||(i-1)||'}')::text[];
    slides:=slides||jsonb_build_array(jsonb_build_object(
      'slide_index',i,
      'template',ds->>'template',
      'theme',ds->>'theme',
      'eyebrow',coalesce(es->>'eyebrow',''),
      'title',es->>'title',
      'body',coalesce(es->>'body',''),
      'cta',coalesce(es->>'cta',''),
      'scene_key',ds->>'scene_key',
      'scene_status','CLEAN_SCENE_REQUIRED',
      'fact_ids',coalesce(es->'fact_ids','[]'::jsonb)
    ));
  end loop;

  return jsonb_build_object(
    'ok',true,
    'topic',cand->>'topic',
    'format',fmt,
    'content_plan',jsonb_build_object(
      'slides',slides,
      'caption',cand->>'caption',
      'cta',cand->>'cta',
      'hypothesis',cand->>'hypothesis',
      'creative_run_id',p_run_id,
      'selected_candidate_id',d->>'candidate_id',
      'quality_target',d->>'quality_target',
      'segments',case when fmt='reel' then 3 else null end,
      'frames_per_segment',case when fmt='reel' then 1 else null end,
      'duration_seconds',case when fmt='reel' then 12 else null end
    ),
    'qa',jsonb_build_object(
      'shadow',true,
      'research_pass',true,
      'semantic_qa',true,
      'premium_visual_plan_qa',true,
      'do_not_publish',true,
      'publish_blocked',true,
      'creative_control_plane','v1',
      'creative_run_id',p_run_id,
      'additional_paid_cost_usd',0
    )
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.sc_creative_render_preflight_v1(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c jsonb;
  s jsonb;
  errs jsonb='[]'::jsonb;
  idx int:=0;
  tpl text;
  tc int; tl int; bc int; bl int; eyebrow_max int;
  title_lines int; body_lines int;
begin
  c:=public.sc_creative_compile_carousel_v1(p_run_id);
  if coalesce((c->>'ok')::boolean,false) is not true then
    return jsonb_build_object('ok',false,'errors',jsonb_build_array('COMPILE_FAILED'));
  end if;

  for s in select value from jsonb_array_elements(c#>'{content_plan,slides}')
  loop
    idx:=idx+1;
    tpl:=s->>'template';
    if tpl='hero_question' then tc:=20;tl:=2;bc:=32;bl:=2;eyebrow_max:=16;
    elsif tpl='dialogue_answer' then tc:=20;tl:=2;bc:=31;bl:=3;eyebrow_max:=18;
    elsif tpl='editorial_fact' then tc:=22;tl:=2;bc:=34;bl:=3;eyebrow_max:=20;
    elsif tpl='compare_clean' then tc:=22;tl:=2;bc:=27;bl:=4;eyebrow_max:=20;
    elsif tpl='brand_close' then tc:=21;tl:=2;bc:=32;bl:=2;eyebrow_max:=40;
    else
      errs:=errs||jsonb_build_array('UNKNOWN_TEMPLATE:'||coalesce(tpl,''));
      continue;
    end if;

    if tpl='compare_clean' and (array_length(string_to_array(coalesce(s->>'body',''),'|'),1)<>2 or btrim(split_part(coalesce(s->>'body',''),'|',1))='' or btrim(split_part(coalesce(s->>'body',''),'|',2))='') then
      errs:=errs||jsonb_build_array('COMPARE_REQUIRES_TWO_OPTIONS:'||idx);
    end if;
    title_lines:=public.sc_wrap_line_count_v1(s->>'title',tc);
    body_lines:=public.sc_wrap_line_count_v1(s->>'body',bc);
    if title_lines>tl then errs:=errs||jsonb_build_array('TITLE_WRAP_OVERFLOW:'||idx); end if;
    if body_lines>bl then errs:=errs||jsonb_build_array('BODY_WRAP_OVERFLOW:'||idx); end if;
    if char_length(coalesce(s->>'eyebrow',''))>eyebrow_max then
      errs:=errs||jsonb_build_array('EYEBROW_OVERFLOW_RISK:'||idx);
    end if;
  end loop;
  return jsonb_build_object('ok',jsonb_array_length(errs)=0,'errors',errs,'renderer_layout_version','2.3.4');
end;
$function$


CREATE OR REPLACE FUNCTION public.sc_quality_factory_hook_v2(p_run_id uuid, p_slot integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare c jsonb;policy jsonb;slot int;localhour int;route jsonb;
begin
 select details into policy from sc_system_health where component='solar_quality_v2_production_flags';
 if coalesce(policy->>'enabled','false')<>'true' or not exists(select 1 from jsonb_each(coalesce(policy->'formats','{}'))f where f.value->>'kill_switch'='false') then return jsonb_build_object('ok',true,'route','V1','reason','ROLLOUT_DISABLED','legacy_entrypoint','sc_creative_materialize_job_v1');end if;
 slot:=p_slot;
 if slot is null then select (details->>'slot')::int into slot from sc_system_health where component='solar_quality_v2_prod_run_'||p_run_id;end if;
 if slot is null then select (trigger->>'quality_slot')::int into slot from sc_creative_runs where id=p_run_id and trigger->>'quality_slot' ~ '^[1-3]$';end if;
 if slot is null then
 localhour:=extract(hour from timezone('America/Argentina/Buenos_Aires',now()));
 slot:=case when localhour<14 then 1 when localhour<19 then 2 else 3 end;
 end if;
 c:=sc_creative_compile_carousel_v1(p_run_id);
 if c->>'ok' is distinct from 'true' then return jsonb_build_object('ok',true,'route','PENDING_APPROVED_RUN','slot',slot,'default','V1','quality_contract','solar_quality_v2_contract','first_format','image');end if;
 route:=sc_quality_rollout_route_v2(c->>'format',slot);
 return route||jsonb_build_object('entrypoint','sc_quality_factory_production_v2','quality_contract','solar_quality_v2_contract','runtime_mode','SHADOW_UNTIL_CANONICAL_PACKAGE','failure_dispatch','sc_quality_factory_outcome_v2','same_job_fallback',true,'revision_limit',1,'publisher_write',false);
end $function$


CREATE OR REPLACE FUNCTION public.sc_v5_command_get_v1(p_actor_user_id uuid, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'sc_internal'
AS $function$
  select coalesce((
    select jsonb_build_object(
      'ok',true,'command_id',c.command_id,'actor_user_id',c.actor_user_id,
      'idempotency_key',c.idempotency_key,'request_hash',c.request_hash,
      'command_type',c.command_type,'mode',c.mode,'target',c.target,'status',c.status,
      'claimed_at',c.claimed_at,'claim_expires_at',c.claim_expires_at,
      'lease_version',c.lease_version,'completed_at',c.completed_at,
      'result',c.result,'error',c.error,'correlation_id',c.correlation_id,
      'created_at',c.created_at,'updated_at',c.updated_at
    )
    from sc_internal.v5_commands c
    where c.actor_user_id=p_actor_user_id and c.idempotency_key=trim(coalesce(p_idempotency_key,''))
  ), jsonb_build_object('ok',false,'reason','NOT_FOUND'))
$function$


CREATE OR REPLACE FUNCTION public.sc_v5_command_mark_executing_v1(p_command_id uuid, p_claim_token uuid, p_lease_seconds integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'sc_internal'
AS $function$
declare
  v_now timestamptz := clock_timestamp();
  v_lease_seconds integer := greatest(15, least(coalesce(p_lease_seconds,90),300));
  v_row sc_internal.v5_commands%rowtype;
begin
  update sc_internal.v5_commands
  set status='EXECUTING',
      claim_expires_at=v_now + make_interval(secs=>v_lease_seconds),
      updated_at=v_now
  where command_id=p_command_id and claim_token=p_claim_token
    and status='CLAIMED' and claim_expires_at is not null and claim_expires_at > v_now
  returning * into v_row;

  if not found then
    return jsonb_build_object('ok',false,'state','DENIED','reason','STALE_OR_INVALID_CLAIM_OWNER');
  end if;

  return jsonb_build_object(
    'ok',true,'state','EXECUTING','command_id',v_row.command_id,
    'claim_token',v_row.claim_token,'lease_version',v_row.lease_version,
    'claim_expires_at',v_row.claim_expires_at,'correlation_id',v_row.correlation_id
  );
end;
$function$
