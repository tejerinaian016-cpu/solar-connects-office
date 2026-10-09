-- STAGING ONLY cmwervbwxyqzowntnxwe. No production data.
create schema if not exists sc_internal; create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions; set check_function_bodies=off;
create table public.sc_agent_config("id" text not null,"config" jsonb not null,"updated_at" timestamp with time zone default now() not null);
create table public.sc_content_jobs("id" uuid default gen_random_uuid() not null,"created_at" timestamp with time zone default now() not null,"updated_at" timestamp with time zone default now() not null,"status" text default 'planned'::text not null,"trigger_text" text,"topic" text,"format" text,"content_plan" jsonb default '{}'::jsonb not null,"qa" jsonb default '{}'::jsonb not null,"asset_urls" jsonb default '[]'::jsonb not null,"instagram_result" jsonb default '{}'::jsonb not null,"error" text);
create table public.sc_content_posts("id" uuid default gen_random_uuid() not null,"job_id" uuid,"instagram_media_id" text,"published_at" timestamp with time zone,"topic" text,"format" text,"hook_type" text,"script" jsonb default '{}'::jsonb not null,"caption" text,"asset_urls" jsonb default '[]'::jsonb not null,"metrics" jsonb default '{}'::jsonb not null,"learned_at" timestamp with time zone);
create table public.sc_creative_runs("id" uuid default gen_random_uuid() not null,"run_key" text not null,"idempotency_key" text not null,"status" text default 'RUNNING'::text not null,"current_stage" text default 'RADAR'::text not null,"radar_attempts" smallint default 0 not null,"editor_attempts" smallint default 0 not null,"director_attempts" smallint default 0 not null,"context_version" text default 'creative-context-v1'::text not null,"controller_version" text default 'creative-controller-v1'::text not null,"trigger" jsonb default '{}'::jsonb not null,"result" jsonb default '{}'::jsonb not null,"error" jsonb,"started_at" timestamp with time zone default now() not null,"completed_at" timestamp with time zone,"created_at" timestamp with time zone default now() not null,"updated_at" timestamp with time zone default now() not null);
create table public.sc_creative_stage_outputs("id" bigint generated always as identity not null,"run_id" uuid not null,"stage" text not null,"attempt" smallint not null,"input_hash" text not null,"schema_version" text not null,"validation_status" text not null,"output" jsonb default '{}'::jsonb not null,"validation_errors" jsonb default '[]'::jsonb not null,"created_at" timestamp with time zone default now() not null);
create table public.sc_fact_bank("fact_id" text not null,"claim" text not null,"source_url" text not null,"source_title" text,"source_kind" text not null,"confidence" text default 'MEDIUM'::text not null,"status" text default 'CANDIDATE'::text not null,"authority" text default 'RESEARCH_CANDIDATE'::text not null,"scope" text,"metadata" jsonb default '{}'::jsonb not null,"created_at" timestamp with time zone default now() not null,"approved_at" timestamp with time zone);
create table public.sc_publish_guard("job_id" uuid not null,"fingerprint" text not null,"account_id" text not null,"state" text default 'READY'::text not null,"started_at" timestamp with time zone,"last_checked_at" timestamp with time zone,"resolved_at" timestamp with time zone,"canonical_media_id" text,"duplicate_media_ids" jsonb default '[]'::jsonb not null,"details" jsonb default '{}'::jsonb not null);
create table public.sc_system_health("component" text not null,"status" text not null,"checked_at" timestamp with time zone default now() not null,"version" text,"details" jsonb default '{}'::jsonb not null);
create table sc_internal.security_mutation_audit("id" bigint generated always as identity not null,"target" text not null,"mutation_type" text not null,"old_state_hash" text,"new_state_hash" text,"actor_class" text not null,"occurred_at" timestamp with time zone default now() not null,"reason" text,"correlation_id" text,"metadata" jsonb default '{}'::jsonb not null);
create table sc_internal.v5_commands("id" uuid default extensions.gen_random_uuid() not null,"command_id" uuid not null,"actor_user_id" uuid not null,"idempotency_key" text not null,"request_hash" text not null,"command_type" text not null,"mode" text not null,"target" jsonb default '{}'::jsonb not null,"payload" jsonb default '{}'::jsonb not null,"confirmation_intent" text not null,"status" text not null,"claimed_at" timestamp with time zone,"claim_expires_at" timestamp with time zone,"claim_token" uuid,"lease_version" bigint default 0 not null,"completed_at" timestamp with time zone,"result" jsonb,"error" jsonb,"correlation_id" uuid not null,"created_at" timestamp with time zone default now() not null,"updated_at" timestamp with time zone default now() not null);
alter table public.sc_agent_config add constraint "sc_agent_config_pkey" PRIMARY KEY (id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_agent_config_pkey ON public.sc_agent_config USING btree (id);
alter table public.sc_agent_config enable row level security;
revoke all on public.sc_agent_config from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on public.sc_agent_config to "postgres";
grant truncate,references,trigger,maintain on public.sc_agent_config to "anon";
grant truncate,references,trigger,maintain on public.sc_agent_config to "authenticated";
grant select,truncate,references,trigger,maintain on public.sc_agent_config to "service_role";
alter table public.sc_content_jobs add constraint "sc_content_jobs_pkey" PRIMARY KEY (id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_content_jobs_pkey ON public.sc_content_jobs USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_content_jobs_creative_run_uq ON public.sc_content_jobs USING btree (((content_plan ->> 'creative_run_id'::text))) WHERE (content_plan ? 'creative_run_id'::text);
alter table public.sc_content_jobs enable row level security;
revoke all on public.sc_content_jobs from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on public.sc_content_jobs to "postgres";
grant maintain on public.sc_content_jobs to "anon";
grant maintain on public.sc_content_jobs to "authenticated";
grant select,update,truncate,references,trigger,maintain on public.sc_content_jobs to "service_role";
alter table public.sc_content_posts add constraint "sc_content_posts_instagram_media_id_key" UNIQUE (instagram_media_id);
alter table public.sc_content_posts add constraint "sc_content_posts_job_id_fkey" FOREIGN KEY (job_id) REFERENCES sc_content_jobs(id) ON DELETE SET NULL;
alter table public.sc_content_posts add constraint "sc_content_posts_pkey" PRIMARY KEY (id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_content_posts_pkey ON public.sc_content_posts USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_content_posts_instagram_media_id_key ON public.sc_content_posts USING btree (instagram_media_id);
alter table public.sc_content_posts enable row level security;
revoke all on public.sc_content_posts from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on public.sc_content_posts to "postgres";
grant maintain on public.sc_content_posts to "anon";
grant maintain on public.sc_content_posts to "authenticated";
grant select,truncate,references,trigger,maintain on public.sc_content_posts to "service_role";
alter table public.sc_creative_runs add constraint "sc_creative_runs_current_stage_check" CHECK ((current_stage = ANY (ARRAY['RADAR'::text, 'EDITOR'::text, 'DIRECTOR'::text, 'DONE'::text])));
alter table public.sc_creative_runs add constraint "sc_creative_runs_director_attempts_check" CHECK (((director_attempts >= 0) AND (director_attempts <= 3)));
alter table public.sc_creative_runs add constraint "sc_creative_runs_editor_attempts_check" CHECK (((editor_attempts >= 0) AND (editor_attempts <= 2)));
alter table public.sc_creative_runs add constraint "sc_creative_runs_idempotency_key_key" UNIQUE (idempotency_key);
alter table public.sc_creative_runs add constraint "sc_creative_runs_pkey" PRIMARY KEY (id);
alter table public.sc_creative_runs add constraint "sc_creative_runs_radar_attempts_check" CHECK (((radar_attempts >= 0) AND (radar_attempts <= 2)));
alter table public.sc_creative_runs add constraint "sc_creative_runs_run_key_key" UNIQUE (run_key);
alter table public.sc_creative_runs add constraint "sc_creative_runs_status_check" CHECK ((status = ANY (ARRAY['RUNNING'::text, 'APPROVED'::text, 'NO_PRODUCTION'::text, 'FAILED_STAGE'::text, 'CANCELLED'::text])));
CREATE UNIQUE INDEX IF NOT EXISTS sc_creative_runs_pkey ON public.sc_creative_runs USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_creative_runs_run_key_key ON public.sc_creative_runs USING btree (run_key);
CREATE UNIQUE INDEX IF NOT EXISTS sc_creative_runs_idempotency_key_key ON public.sc_creative_runs USING btree (idempotency_key);
alter table public.sc_creative_runs enable row level security;
revoke all on public.sc_creative_runs from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on public.sc_creative_runs to "postgres";
grant insert,select,update,truncate,references,trigger,maintain on public.sc_creative_runs to "service_role";
alter table public.sc_creative_stage_outputs add constraint "sc_creative_stage_outputs_attempt_check" CHECK (((attempt >= 1) AND (attempt <= 3)));
alter table public.sc_creative_stage_outputs add constraint "sc_creative_stage_outputs_input_hash_check" CHECK ((input_hash ~ '^[0-9a-f]{64}$'::text));
alter table public.sc_creative_stage_outputs add constraint "sc_creative_stage_outputs_pkey" PRIMARY KEY (id);
alter table public.sc_creative_stage_outputs add constraint "sc_creative_stage_outputs_run_id_fkey" FOREIGN KEY (run_id) REFERENCES sc_creative_runs(id);
alter table public.sc_creative_stage_outputs add constraint "sc_creative_stage_outputs_run_id_stage_attempt_key" UNIQUE (run_id, stage, attempt);
alter table public.sc_creative_stage_outputs add constraint "sc_creative_stage_outputs_stage_check" CHECK ((stage = ANY (ARRAY['RADAR'::text, 'EDITOR'::text, 'DIRECTOR'::text])));
alter table public.sc_creative_stage_outputs add constraint "sc_creative_stage_outputs_validation_status_check" CHECK ((validation_status = ANY (ARRAY['VALID'::text, 'INVALID'::text])));
CREATE UNIQUE INDEX IF NOT EXISTS sc_creative_stage_outputs_pkey ON public.sc_creative_stage_outputs USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_creative_stage_outputs_run_id_stage_attempt_key ON public.sc_creative_stage_outputs USING btree (run_id, stage, attempt);
alter table public.sc_creative_stage_outputs enable row level security;
revoke all on public.sc_creative_stage_outputs from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on public.sc_creative_stage_outputs to "postgres";
grant insert,select,truncate,references,trigger,maintain on public.sc_creative_stage_outputs to "service_role";
alter table public.sc_fact_bank add constraint "sc_fact_bank_authority_check" CHECK ((authority = ANY (ARRAY['BRAND_BRAIN'::text, 'HUMAN_APPROVED'::text, 'VERIFIED_OFFICIAL'::text, 'RESEARCH_CANDIDATE'::text])));
alter table public.sc_fact_bank add constraint "sc_fact_bank_confidence_check" CHECK ((confidence = ANY (ARRAY['LOW'::text, 'MEDIUM'::text, 'HIGH'::text])));
alter table public.sc_fact_bank add constraint "sc_fact_bank_pkey" PRIMARY KEY (fact_id);
alter table public.sc_fact_bank add constraint "sc_fact_bank_source_kind_check" CHECK ((source_kind = ANY (ARRAY['PRIMARY'::text, 'OFFICIAL'::text, 'SECONDARY'::text])));
alter table public.sc_fact_bank add constraint "sc_fact_bank_status_check" CHECK ((status = ANY (ARRAY['CANDIDATE'::text, 'APPROVED'::text, 'REJECTED'::text])));
CREATE UNIQUE INDEX IF NOT EXISTS sc_fact_bank_pkey ON public.sc_fact_bank USING btree (fact_id);
alter table public.sc_fact_bank enable row level security;
revoke all on public.sc_fact_bank from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on public.sc_fact_bank to "postgres";
grant insert,select,update,truncate,references,trigger,maintain on public.sc_fact_bank to "service_role";
alter table public.sc_publish_guard add constraint "sc_publish_guard_fingerprint_key" UNIQUE (fingerprint);
alter table public.sc_publish_guard add constraint "sc_publish_guard_job_id_fkey" FOREIGN KEY (job_id) REFERENCES sc_content_jobs(id) ON DELETE CASCADE;
alter table public.sc_publish_guard add constraint "sc_publish_guard_pkey" PRIMARY KEY (job_id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_publish_guard_pkey ON public.sc_publish_guard USING btree (job_id);
CREATE UNIQUE INDEX IF NOT EXISTS sc_publish_guard_fingerprint_key ON public.sc_publish_guard USING btree (fingerprint);
alter table public.sc_publish_guard enable row level security;
revoke all on public.sc_publish_guard from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on public.sc_publish_guard to "postgres";
grant maintain on public.sc_publish_guard to "anon";
grant maintain on public.sc_publish_guard to "authenticated";
grant select,truncate,references,trigger,maintain on public.sc_publish_guard to "service_role";
alter table public.sc_system_health add constraint "sc_system_health_pkey" PRIMARY KEY (component);
CREATE UNIQUE INDEX IF NOT EXISTS sc_system_health_pkey ON public.sc_system_health USING btree (component);
alter table public.sc_system_health enable row level security;
revoke all on public.sc_system_health from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on public.sc_system_health to "postgres";
grant truncate,references,trigger,maintain on public.sc_system_health to "anon";
grant truncate,references,trigger,maintain on public.sc_system_health to "authenticated";
grant select,truncate,references,trigger,maintain on public.sc_system_health to "service_role";
alter table sc_internal.security_mutation_audit add constraint "security_mutation_audit_actor_class_check" CHECK ((actor_class = ANY (ARRAY['USER_EXPLICIT'::text, 'AUTHORIZED_CONTROL_PLANE'::text, 'SAFETY_KILL_SWITCH'::text, 'SYSTEM_AUDIT'::text])));
alter table sc_internal.security_mutation_audit add constraint "security_mutation_audit_new_state_hash_check" CHECK (((new_state_hash IS NULL) OR (new_state_hash ~ '^[0-9a-f]{64}$'::text)));
alter table sc_internal.security_mutation_audit add constraint "security_mutation_audit_old_state_hash_check" CHECK (((old_state_hash IS NULL) OR (old_state_hash ~ '^[0-9a-f]{64}$'::text)));
alter table sc_internal.security_mutation_audit add constraint "security_mutation_audit_pkey" PRIMARY KEY (id);
CREATE UNIQUE INDEX IF NOT EXISTS security_mutation_audit_pkey ON sc_internal.security_mutation_audit USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS security_mutation_audit_correlation_uidx ON sc_internal.security_mutation_audit USING btree (target, mutation_type, correlation_id) WHERE (correlation_id IS NOT NULL);
revoke all on sc_internal.security_mutation_audit from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on sc_internal.security_mutation_audit to "postgres";
alter table sc_internal.v5_commands add constraint "v5_commands_actor_user_id_idempotency_key_key" UNIQUE (actor_user_id, idempotency_key);
alter table sc_internal.v5_commands add constraint "v5_commands_command_id_key" UNIQUE (command_id);
alter table sc_internal.v5_commands add constraint "v5_commands_command_type_check" CHECK (((char_length(command_type) >= 3) AND (char_length(command_type) <= 100)));
alter table sc_internal.v5_commands add constraint "v5_commands_confirmation_intent_check" CHECK (((char_length(confirmation_intent) >= 3) AND (char_length(confirmation_intent) <= 100)));
alter table sc_internal.v5_commands add constraint "v5_commands_idempotency_key_check" CHECK (((char_length(idempotency_key) >= 8) AND (char_length(idempotency_key) <= 200)));
alter table sc_internal.v5_commands add constraint "v5_commands_lease_version_check" CHECK ((lease_version >= 0));
alter table sc_internal.v5_commands add constraint "v5_commands_mode_check" CHECK ((mode = ANY (ARRAY['SIMULATE'::text, 'EXECUTE'::text])));
alter table sc_internal.v5_commands add constraint "v5_commands_pkey" PRIMARY KEY (id);
alter table sc_internal.v5_commands add constraint "v5_commands_request_hash_check" CHECK ((request_hash ~ '^[0-9a-f]{64}$'::text));
alter table sc_internal.v5_commands add constraint "v5_commands_status_check" CHECK ((status = ANY (ARRAY['PENDING'::text, 'CLAIMED'::text, 'EXECUTING'::text, 'SUCCEEDED'::text, 'FAILED'::text, 'ROLLED_BACK'::text])));
CREATE UNIQUE INDEX IF NOT EXISTS v5_commands_pkey ON sc_internal.v5_commands USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS v5_commands_command_id_key ON sc_internal.v5_commands USING btree (command_id);
CREATE UNIQUE INDEX IF NOT EXISTS v5_commands_actor_user_id_idempotency_key_key ON sc_internal.v5_commands USING btree (actor_user_id, idempotency_key);
CREATE INDEX IF NOT EXISTS v5_commands_status_lease_idx ON sc_internal.v5_commands USING btree (status, claim_expires_at) WHERE (status = ANY (ARRAY['CLAIMED'::text, 'EXECUTING'::text]));
CREATE INDEX IF NOT EXISTS v5_commands_correlation_idx ON sc_internal.v5_commands USING btree (correlation_id);
revoke all on sc_internal.v5_commands from public,anon,authenticated,service_role;
grant insert,select,update,delete,truncate,references,trigger,maintain on sc_internal.v5_commands to "postgres";
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
;
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
;
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
;
CREATE OR REPLACE FUNCTION public.sc_feed_daily_budget_v1(p_exclude_job uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare cap_text text; cap int; used int; reserved int;
begin
 select config#>>'{publishing_policy,max_feed_posts_per_day}' into cap_text from public.sc_agent_config where id='solar_connects_v1';
 if cap_text is null or cap_text !~ '^[0-9]{1,3}$' then
  return jsonb_build_object('allowed',false,'reason','DAILY_CAP_CONFIG_INVALID');
 end if;
 cap:=cap_text::int;
 select count(distinct instagram_media_id) into used from public.sc_content_posts
 where format in ('image','single_image','carousel','reel') and instagram_media_id is not null
 and timezone('America/Argentina/Buenos_Aires',published_at)::date=timezone('America/Argentina/Buenos_Aires',now())::date;
 select count(*) into reserved from public.sc_publish_guard g join public.sc_content_jobs j on j.id=g.job_id
 where j.format in ('image','single_image','carousel','reel') and g.state in ('PUBLISHING','RECONCILE_REQUIRED')
 and (p_exclude_job is null or g.job_id<>p_exclude_job)
 and not exists(select 1 from public.sc_content_posts p where p.job_id=g.job_id);
 return jsonb_build_object('allowed',cap>0 and used+reserved<cap,'reason',case when cap>0 and used+reserved<cap then 'ALLOWED' else 'DAILY_FEED_CAP_REACHED' end,
 'limit',cap,'published',used,'reserved',reserved,'source','sc_agent_config.publishing_policy.max_feed_posts_per_day','timezone','America/Argentina/Buenos_Aires');
end $function$
;
CREATE OR REPLACE FUNCTION public.sc_observability_realtime_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform realtime.send(
    jsonb_build_object(
      'table', TG_TABLE_NAME,
      'op', TG_OP,
      'occurred_at', statement_timestamp()
    ),
    'invalidate',
    'solar-connects-observability-v3',
    false
  );
  return coalesce(NEW, OLD);
exception when others then
  return coalesce(NEW, OLD);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.sc_quality_factory_adapter_v2(p_factory jsonb, p_opt_in jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare fmt text:=p_factory->>'format'; pages jsonb:=p_factory#>'{quality_v2,pages}'; jid uuid; ledger jsonb; reqhash text; key text; existing jsonb; runid uuid; claim_ids jsonb;
begin
 if coalesce(p_opt_in->>'enabled','false')<>'true' or not (coalesce(p_opt_in->'formats','[]') ? coalesce(fmt,'')) then
  return jsonb_build_object('ok',true,'route','V1','factory_output',p_factory,'default_unchanged',true,'production_authorization',false);
 end if;
 if p_opt_in->>'mode' is distinct from 'SHADOW' then return jsonb_build_object('ok',false,'reason','SHADOW_ONLY'); end if;
 if fmt not in ('image','carousel','story','reel') or jsonb_typeof(pages) is distinct from 'array' or jsonb_array_length(pages)<>(case when fmt='carousel' then 5 when fmt='reel' then 3 else 1 end) then return jsonb_build_object('ok',false,'reason','FORMAT_SEQUENCE_INVALID'); end if;
 if length(coalesce(p_factory->>'topic',''))<8 or length(coalesce(p_factory->>'caption',''))<8 then return jsonb_build_object('ok',false,'reason','TOPIC_CAPTION_REQUIRED'); end if;
 if exists(select 1 from jsonb_array_elements(pages) p where p->>'format' is distinct from fmt or coalesce(p->>'argument_key','')='' or coalesce(p->>'decision_key','')='' or coalesce(p->>'angle_key','')='' or coalesce(p->>'hook_family','')='' or coalesce(p->>'layout','')='' or jsonb_typeof(p->'fact_ids') is distinct from 'array') then return jsonb_build_object('ok',false,'reason','PAGE_IDENTITY_REQUIRED'); end if;
 if exists(select 1 from jsonb_array_elements(pages)p cross join lateral jsonb_array_elements_text(p->'fact_ids') fid where not exists(select 1 from sc_fact_bank f where f.fact_id=fid and f.status='APPROVED')) then return jsonb_build_object('ok',false,'reason','UNAPPROVED_FACT'); end if;
 if p_factory ? 'creative_run_id' then
  runid:=(p_factory->>'creative_run_id')::uuid;
  if not exists(select 1 from sc_creative_runs where id=runid and status='APPROVED') then return jsonb_build_object('ok',false,'reason','FACTORY_RUN_NOT_APPROVED'); end if;
 end if;
 key:=p_factory->>'idempotency_key';
 if key is null or key !~ '^quality-v2-shadow:[a-zA-Z0-9_-]{8,100}$' then return jsonb_build_object('ok',false,'reason','SHADOW_KEY_REQUIRED'); end if;
 reqhash:=encode(extensions.digest(p_factory::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtext(key));
 select details into existing from sc_system_health where component='solar_quality_v2_key_'||key;
 if existing is not null then
  if existing->>'request_sha256' is distinct from reqhash then return jsonb_build_object('ok',false,'reason','IDEMPOTENCY_CONFLICT'); end if;
  return existing||jsonb_build_object('idempotent',true);
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('claim_id',f.fact_id,'claim',f.claim,'scope',f.scope,'source_url',f.source_url,'fact_status',f.status)), '[]'::jsonb) into ledger
 from sc_fact_bank f where f.fact_id in(select distinct fid from jsonb_array_elements(pages)p cross join lateral jsonb_array_elements_text(p->'fact_ids')fid);
 select coalesce(jsonb_agg(x->>'claim_id'),'[]'::jsonb) into claim_ids from jsonb_array_elements(ledger)x;
 insert into sc_content_jobs(status,trigger_text,topic,format,content_plan,qa)
 values('QUALITY_V2_SHADOW_RENDERING','quality-v2-opt-in-shadow-factory',p_factory->>'topic',fmt,
 jsonb_build_object('slides',pages,'caption',p_factory->>'caption','quality_v2',p_factory->'quality_v2','materialization_mode','SHADOW','idempotency_key',key),
 jsonb_build_object('shadow',true,'quality_v2_opt_in',true,'production_candidate',false,'do_not_publish',true,'publish_blocked',true,'release_gate','HOLD','quality_v2_phase','PREFLIGHT_PENDING','renderer_version','solar-quality-v2.0.0','claims_ledger',ledger,'tags',jsonb_build_object('topic',p_factory->>'topic','angle',pages->0->>'angle_key','claim_id',claim_ids,'hook_type',pages->0->>'hook_family','layout_id',pages->0->>'layout'))) returning id into jid;
 existing:=jsonb_build_object('ok',true,'route','QUALITY_V2_SHADOW','job_id',jid,'request_sha256',reqhash,'mode','SHADOW','external_write',false,'production_authorization',false);
 insert into sc_system_health(component,version,status,details) values('solar_quality_v2_key_'||key,'2.0-shadow.2','ADAPTED',existing);
 insert into sc_system_health(component,version,status,details) values('solar_quality_v2_job_'||jid,'2.0-shadow.2','ADAPTED',jsonb_build_object('job_id',jid,'factory_output',p_factory,'request_sha256',reqhash,'claims_ledger',ledger,'mode','SHADOW','production_authorization',false));
 return existing;
end; $function$
;
CREATE OR REPLACE FUNCTION public.sc_quality_factory_from_run_v2(p_run_id uuid, p_quality jsonb, p_opt_in jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare c jsonb; factory jsonb; pages jsonb; s jsonb; outpages jsonb:='[]'; idx int:=0;
begin
 c:=sc_creative_compile_carousel_v1(p_run_id);
 if c->>'ok' is distinct from 'true' then return c; end if;
 if coalesce(p_opt_in->>'enabled','false')<>'true' or not (coalesce(p_opt_in->'formats','[]') ? (c->>'format')) then
  return jsonb_build_object('ok',true,'route','V1','legacy_entrypoint','sc_creative_materialize_job_v1','compiled',c,'mode','READ_ONLY','production_changed',false);
 end if;
 if p_opt_in->>'mode' is distinct from 'SHADOW' or jsonb_typeof(p_quality->'pages') is distinct from 'array' or jsonb_array_length(p_quality->'pages')<>jsonb_array_length(c#>'{content_plan,slides}') then return jsonb_build_object('ok',false,'reason','QUALITY_SHADOW_SEQUENCE_REQUIRED'); end if;
 for s in select value from jsonb_array_elements(c#>'{content_plan,slides}')loop
  outpages:=outpages||jsonb_build_array((p_quality->'pages'->idx)||jsonb_build_object('format',c->>'format','title',s->>'title','body',s->>'body','cta',s->>'cta','eyebrow',s->>'eyebrow','fact_ids',s->'fact_ids'));
  idx:=idx+1;
 end loop;
 factory:=jsonb_build_object('format',c->>'format','topic',c->>'topic','caption',c#>>'{content_plan,caption}','creative_run_id',p_run_id,'quality_v2',(p_quality-'pages')||jsonb_build_object('pages',outpages),'idempotency_key','quality-v2-shadow:factory_run_'||replace(p_run_id::text,'-',''),'source','EXISTING_FACTORY_COMPILER');
 return sc_quality_factory_adapter_v2(factory,p_opt_in);
end; $function$
;
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
;
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
;
CREATE OR REPLACE FUNCTION public.sc_quality_rollout_decide_v2(p_policy jsonb, p_format text, p_slot integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare n int; why text;
begin
 if p_format is null or p_slot is null or p_format not in ('image','story','carousel','reel') or p_slot not between 1 and 3 then return jsonb_build_object('ok',false,'reason','FORMAT_OR_SLOT_INVALID'); end if;
 if p_policy->>'enabled' is distinct from 'true' then why:='ROLLOUT_DISABLED';
 elsif p_policy#>>array['formats',p_format,'kill_switch'] is distinct from 'false' then why:='FORMAT_KILL_SWITCH';
 elsif p_policy->>'comparison_gate' is distinct from 'PASS' then why:='COMPARISON_GATE_REQUIRED';
 elsif p_policy->>'stage' not in ('1','2','3') then why:='STAGE_INVALID';
 else n:=(p_policy->>'stage')::int; if p_slot>n then why:='V1_SLOT'; end if;
 end if;
 return jsonb_build_object('ok',true,'route',case when why is null then 'V2' else 'V1' end,'reason',coalesce(why,'V2_SLOT'),'slot',p_slot,'format',p_format,'stage',p_policy->>'stage','policy_epoch',p_policy->>'epoch','publisher_write',false);
end $function$
;
CREATE OR REPLACE FUNCTION public.sc_quality_rollout_route_v2(p_format text, p_slot integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
select sc_quality_rollout_decide_v2(coalesce((select details from sc_system_health where component='solar_quality_v2_production_flags'),'{}'),p_format,p_slot)
$function$
;
CREATE OR REPLACE FUNCTION public.sc_record_security_mutation_v1(p_target text, p_mutation_type text, p_old_state jsonb, p_new_state jsonb, p_actor_class text, p_reason text DEFAULT NULL::text, p_correlation_id text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'sc_internal', 'extensions'
AS $function$
declare
  v_actor text:=upper(trim(coalesce(p_actor_class,'')));
  v_old_hash text;
  v_new_hash text;
  v_safe_metadata jsonb;
  v_id bigint;
begin
  if v_actor not in ('USER_EXPLICIT','AUTHORIZED_CONTROL_PLANE','SAFETY_KILL_SWITCH','SYSTEM_AUDIT') then
    return jsonb_build_object('ok',false,'reason','ACTOR_CLASS_NOT_ALLOWED');
  end if;

  if nullif(trim(coalesce(p_target,'')),'') is null
     or nullif(trim(coalesce(p_mutation_type,'')),'') is null then
    return jsonb_build_object('ok',false,'reason','TARGET_AND_MUTATION_REQUIRED');
  end if;

  v_old_hash:=case when p_old_state is null then null else public.sc_security_hash_v1(p_old_state) end;
  v_new_hash:=case when p_new_state is null then null else public.sc_security_hash_v1(p_new_state) end;

  v_safe_metadata:=coalesce(p_metadata,'{}'::jsonb)
    - 'token' - 'access_token' - 'refresh_token' - 'authorization'
    - 'secret' - 'password' - 'service_role_key' - 'api_key';

  insert into sc_internal.security_mutation_audit(
    target,mutation_type,old_state_hash,new_state_hash,actor_class,reason,correlation_id,metadata
  ) values (
    left(p_target,200),left(p_mutation_type,100),v_old_hash,v_new_hash,v_actor,
    left(coalesce(p_reason,''),500),nullif(left(coalesce(p_correlation_id,''),200),''),
    v_safe_metadata
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,
    'audit_id',v_id,
    'old_state_hash',v_old_hash,
    'new_state_hash',v_new_hash,
    'secrets_stored',false
  );
exception when unique_violation then
  return jsonb_build_object('ok',true,'idempotent_replay',true,'secrets_stored',false);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.sc_security_hash_v1(p_value jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
  select encode(extensions.digest(convert_to(coalesce(p_value,'null'::jsonb)::text,'UTF8'),'sha256'),'hex')
$function$
;
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
;
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
;
CREATE OR REPLACE FUNCTION public.sc_v5_command_complete_v1(p_command_id uuid, p_claim_token uuid, p_success boolean, p_result jsonb DEFAULT NULL::jsonb, p_error jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'sc_internal'
AS $function$
declare
  v_now timestamptz := clock_timestamp();
  v_row sc_internal.v5_commands%rowtype;
  v_status text := case when coalesce(p_success,false) then 'SUCCEEDED' else 'FAILED' end;
  v_audit jsonb;
begin
  update sc_internal.v5_commands
  set status=v_status,completed_at=v_now,
      result=case when coalesce(p_success,false) then coalesce(p_result,'{}'::jsonb) else null end,
      error=case when coalesce(p_success,false) then null else coalesce(p_error,'{}'::jsonb) end,
      updated_at=v_now
  where command_id=p_command_id and claim_token=p_claim_token and status='EXECUTING'
  returning * into v_row;

  if not found then
    return jsonb_build_object('ok',false,'state','DENIED','reason','STALE_OR_INVALID_CLAIM_OWNER');
  end if;

  v_audit := public.sc_record_security_mutation_v1(
    'v5_command:'||v_row.command_id::text,
    case when v_status='SUCCEEDED' then 'COMMAND_SUCCEEDED' else 'COMMAND_FAILED' end,
    jsonb_build_object('status','EXECUTING','lease_version',v_row.lease_version),
    jsonb_build_object('status',v_status,'lease_version',v_row.lease_version),
    'USER_EXPLICIT',
    case when v_status='SUCCEEDED' then 'durable command completed' else 'durable command failed' end,
    v_row.correlation_id::text,
    jsonb_build_object(
      'command_id',v_row.command_id,'actor_user_id',v_row.actor_user_id,
      'request_hash',v_row.request_hash,'mode',v_row.mode,'command_type',v_row.command_type,'test',false
    )
  );

  return jsonb_build_object(
    'ok',true,'state',v_status,'command_id',v_row.command_id,
    'request_hash',v_row.request_hash,'result',v_row.result,'error',v_row.error,
    'correlation_id',v_row.correlation_id,'completed_at',v_row.completed_at,'audit',v_audit
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.sc_v5_command_request_hash_v1(p_command_type text, p_target jsonb, p_payload jsonb, p_confirmation_intent text, p_mode text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select public.sc_security_hash_v1(
    jsonb_build_object(
      'command_type', trim(coalesce(p_command_type,'')),
      'target', coalesce(p_target,'{}'::jsonb),
      'payload', coalesce(p_payload,'{}'::jsonb),
      'confirmation_intent', trim(coalesce(p_confirmation_intent,'')),
      'mode', upper(trim(coalesce(p_mode,'')))
    )
  )
$function$
;
CREATE OR REPLACE FUNCTION public.sc_wrap_line_count_v1(p_text text, p_max_chars integer)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  w text;
  line text:='';
  n int:=0;
  candidate text;
begin
  if trim(coalesce(p_text,''))='' then return 0; end if;
  for w in select regexp_split_to_table(trim(regexp_replace(coalesce(p_text,''),'\s+',' ','g')),' ')
  loop
    candidate:=case when line='' then w else line||' '||w end;
    if char_length(candidate)>p_max_chars and line<>'' then
      n:=n+1;
      line:=w;
    else
      line:=candidate;
    end if;
  end loop;
  if line<>'' then n:=n+1; end if;
  return n;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.sc_observability_realtime_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform realtime.send(
    jsonb_build_object(
      'table', TG_TABLE_NAME,
      'op', TG_OP,
      'occurred_at', statement_timestamp()
    ),
    'invalidate',
    'solar-connects-observability-v3',
    false
  );
  return coalesce(NEW, OLD);
exception when others then
  return coalesce(NEW, OLD);
end;
$function$
;
CREATE TRIGGER sc_obs_rt_content_jobs AFTER INSERT OR DELETE OR UPDATE ON public.sc_content_jobs FOR EACH ROW EXECUTE FUNCTION sc_observability_realtime_notify();
CREATE OR REPLACE FUNCTION public.sc_creative_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at=now();
  return new;
end;
$function$
;
CREATE TRIGGER trg_sc_creative_runs_touch BEFORE UPDATE ON public.sc_creative_runs FOR EACH ROW EXECUTE FUNCTION sc_creative_touch_updated_at();
CREATE OR REPLACE FUNCTION public.sc_creative_stage_outputs_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  raise exception 'sc_creative_stage_outputs is append-only';
end;
$function$
;
CREATE TRIGGER trg_sc_creative_stage_outputs_append_only BEFORE DELETE OR UPDATE ON public.sc_creative_stage_outputs FOR EACH ROW EXECUTE FUNCTION sc_creative_stage_outputs_append_only();
CREATE OR REPLACE FUNCTION sc_internal.sc_enforce_feed_daily_budget_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare fmt text; budget jsonb;
begin
 if NEW.state<>'PUBLISHING' then return NEW; end if;
 if TG_OP='UPDATE' and OLD.state='PUBLISHING' then return NEW; end if;
 select format into fmt from public.sc_content_jobs where id=NEW.job_id;
 if fmt not in ('image','single_image','carousel','reel') then return NEW; end if;
 if not pg_try_advisory_xact_lock(hashtextextended('solar-feed-daily-budget:'||coalesce(NEW.account_id,''),0)) then
  raise exception 'HOLD_FEED_BUDGET_CONCURRENT_CLAIM' using errcode='P0001';
 end if;
 budget:=public.sc_feed_daily_budget_v1(NEW.job_id);
 if coalesce((budget->>'allowed')::boolean,false) is not true then
  raise exception 'HOLD_FEED_DAILY_BUDGET: %',budget using errcode='P0001';
 end if;
 return NEW;
end $function$
;
CREATE TRIGGER sc_feed_daily_budget_guard_v1 BEFORE INSERT OR UPDATE OF state ON public.sc_publish_guard FOR EACH ROW EXECUTE FUNCTION sc_internal.sc_enforce_feed_daily_budget_v1();
CREATE OR REPLACE FUNCTION public.sc_observability_realtime_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform realtime.send(
    jsonb_build_object(
      'table', TG_TABLE_NAME,
      'op', TG_OP,
      'occurred_at', statement_timestamp()
    ),
    'invalidate',
    'solar-connects-observability-v3',
    false
  );
  return coalesce(NEW, OLD);
exception when others then
  return coalesce(NEW, OLD);
end;
$function$
;
CREATE TRIGGER sc_obs_rt_publish_guard AFTER INSERT OR DELETE OR UPDATE ON public.sc_publish_guard FOR EACH ROW EXECUTE FUNCTION sc_observability_realtime_notify();
CREATE OR REPLACE FUNCTION public.sc_observability_realtime_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform realtime.send(
    jsonb_build_object(
      'table', TG_TABLE_NAME,
      'op', TG_OP,
      'occurred_at', statement_timestamp()
    ),
    'invalidate',
    'solar-connects-observability-v3',
    false
  );
  return coalesce(NEW, OLD);
exception when others then
  return coalesce(NEW, OLD);
end;
$function$
;
CREATE TRIGGER sc_obs_rt_system_health AFTER INSERT OR DELETE OR UPDATE ON public.sc_system_health FOR EACH ROW EXECUTE FUNCTION sc_observability_realtime_notify();
revoke all on function public.sc_creative_compile_carousel_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.sc_creative_compile_carousel_v1(uuid) to "postgres";
grant execute on function public.sc_creative_compile_carousel_v1(uuid) to "service_role";
revoke all on function public.sc_creative_materialize_job_v1(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.sc_creative_materialize_job_v1(uuid,text) to "postgres";
grant execute on function public.sc_creative_materialize_job_v1(uuid,text) to "service_role";
revoke all on function public.sc_creative_render_preflight_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.sc_creative_render_preflight_v1(uuid) to "postgres";
grant execute on function public.sc_creative_render_preflight_v1(uuid) to "service_role";
revoke all on function public.sc_feed_daily_budget_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.sc_feed_daily_budget_v1(uuid) to "postgres";
grant execute on function public.sc_feed_daily_budget_v1(uuid) to "service_role";
revoke all on function public.sc_observability_realtime_notify() from public,anon,authenticated,service_role;
grant execute on function public.sc_observability_realtime_notify() to "postgres";
grant execute on function public.sc_observability_realtime_notify() to "service_role";
revoke all on function public.sc_quality_factory_adapter_v2(jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.sc_quality_factory_adapter_v2(jsonb,jsonb) to public;
grant execute on function public.sc_quality_factory_adapter_v2(jsonb,jsonb) to "postgres";
grant execute on function public.sc_quality_factory_adapter_v2(jsonb,jsonb) to "service_role";
revoke all on function public.sc_quality_factory_from_run_v2(uuid,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.sc_quality_factory_from_run_v2(uuid,jsonb,jsonb) to public;
grant execute on function public.sc_quality_factory_from_run_v2(uuid,jsonb,jsonb) to "postgres";
grant execute on function public.sc_quality_factory_from_run_v2(uuid,jsonb,jsonb) to "service_role";
revoke all on function public.sc_quality_factory_hook_v2(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.sc_quality_factory_hook_v2(uuid,integer) to public;
grant execute on function public.sc_quality_factory_hook_v2(uuid,integer) to "postgres";
grant execute on function public.sc_quality_factory_hook_v2(uuid,integer) to "service_role";
revoke all on function public.sc_quality_factory_production_v2(uuid,jsonb,integer,boolean) from public,anon,authenticated,service_role;
grant execute on function public.sc_quality_factory_production_v2(uuid,jsonb,integer,boolean) to public;
grant execute on function public.sc_quality_factory_production_v2(uuid,jsonb,integer,boolean) to "postgres";
grant execute on function public.sc_quality_factory_production_v2(uuid,jsonb,integer,boolean) to "service_role";
revoke all on function public.sc_quality_rollout_decide_v2(jsonb,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.sc_quality_rollout_decide_v2(jsonb,text,integer) to public;
grant execute on function public.sc_quality_rollout_decide_v2(jsonb,text,integer) to "postgres";
grant execute on function public.sc_quality_rollout_decide_v2(jsonb,text,integer) to "service_role";
revoke all on function public.sc_quality_rollout_route_v2(text,integer) from public,anon,authenticated,service_role;
grant execute on function public.sc_quality_rollout_route_v2(text,integer) to public;
grant execute on function public.sc_quality_rollout_route_v2(text,integer) to "postgres";
grant execute on function public.sc_quality_rollout_route_v2(text,integer) to "service_role";
revoke all on function public.sc_record_security_mutation_v1(text,text,jsonb,jsonb,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.sc_record_security_mutation_v1(text,text,jsonb,jsonb,text,text,text,jsonb) to "postgres";
grant execute on function public.sc_record_security_mutation_v1(text,text,jsonb,jsonb,text,text,text,jsonb) to "service_role";
revoke all on function public.sc_security_hash_v1(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.sc_security_hash_v1(jsonb) to "postgres";
grant execute on function public.sc_security_hash_v1(jsonb) to "service_role";
revoke all on function public.sc_security_operation_gate_v1(text) from public,anon,authenticated,service_role;
grant execute on function public.sc_security_operation_gate_v1(text) to "postgres";
grant execute on function public.sc_security_operation_gate_v1(text) to "service_role";
revoke all on function public.sc_v5_command_claim_v1(uuid,uuid,text,text,jsonb,jsonb,text,text,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.sc_v5_command_claim_v1(uuid,uuid,text,text,jsonb,jsonb,text,text,uuid,integer) to "postgres";
grant execute on function public.sc_v5_command_claim_v1(uuid,uuid,text,text,jsonb,jsonb,text,text,uuid,integer) to "service_role";
revoke all on function public.sc_v5_command_complete_v1(uuid,uuid,boolean,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.sc_v5_command_complete_v1(uuid,uuid,boolean,jsonb,jsonb) to "postgres";
grant execute on function public.sc_v5_command_complete_v1(uuid,uuid,boolean,jsonb,jsonb) to "service_role";
revoke all on function public.sc_v5_command_request_hash_v1(text,jsonb,jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function public.sc_v5_command_request_hash_v1(text,jsonb,jsonb,text,text) to "postgres";
grant execute on function public.sc_v5_command_request_hash_v1(text,jsonb,jsonb,text,text) to "service_role";
revoke all on function public.sc_wrap_line_count_v1(text,integer) from public,anon,authenticated,service_role;
grant execute on function public.sc_wrap_line_count_v1(text,integer) to public;
grant execute on function public.sc_wrap_line_count_v1(text,integer) to "postgres";
grant execute on function public.sc_wrap_line_count_v1(text,integer) to "service_role";
insert into public.sc_agent_config(id,config) values('solar_connects_v1','{"security_control_plane_v1":{"kill_switches":{"factory":{"allow":false},"publisher":{"allow":false},"meta_direct":{"allow":false},"external_write":{"allow":false}}},"publishing_policy":{"max_feed_posts_per_day":1}}');
insert into public.sc_system_health(component,status,details) values('solar_quality_v2_production_flags','STAGE1_FROZEN_OBSERVATION','{"enabled":true,"formats":{"image":{"kill_switch":true},"carousel":{"kill_switch":true},"story":{"kill_switch":true},"reel":{"kill_switch":true}}}'),('solar_quality_v2_first_slot','CONFIRMED_FROZEN','{"enabled":true,"state":"CONFIRMED_FROZEN"}');