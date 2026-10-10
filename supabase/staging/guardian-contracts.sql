-- STAGING ONLY: authentic exported contracts; no production rows.
create extension if not exists pg_trgm with schema extensions;
CREATE OR REPLACE FUNCTION public.sc_quality_json_canonical_v2(p_value jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out text;
begin
 if jsonb_typeof(p_value)='object' then
  select '{'||coalesce(string_agg(to_jsonb(key)::text||':'||sc_quality_json_canonical_v2(value),',' order by key collate "C"),'')||'}' into out from jsonb_each(p_value);
 elsif jsonb_typeof(p_value)='array' then
  select '['||coalesce(string_agg(sc_quality_json_canonical_v2(value),',' order by ord),'')||']' into out from jsonb_array_elements(p_value) with ordinality x(value,ord);
 else out:=p_value::text;
 end if;
 return out;
end; $function$
;
CREATE OR REPLACE FUNCTION sc_internal.sc_creative_duplicate_check_core_v1(p_topic text, p_hook text, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_topic text:=lower(trim(coalesce(p_topic,'')));
  v_hook text:=lower(trim(coalesce(p_hook,'')));
  v record;
  v_as_of timestamptz:=coalesce(p_as_of,now());
  v_energy_pattern text:='agua caliente.*(consumo energ|plan de energ|segundo mayor consumo)|(consumo energ|segundo mayor consumo).*agua caliente';
  v_energy_topic boolean;

begin
  if v_topic='' then
    return jsonb_build_object('ok',false,'duplicate',false,'reason','TOPIC_REQUIRED');
  end if;

  -- A narrow editorial cooldown for the verified repeated hot-water energy argument.
  -- Keep legacy lexical identity checks and all completed content unchanged.
  v_energy_topic := v_topic ~ v_energy_pattern;

  with corpus as (
    select
      'POST'::text source,
      cp.id::text ref_id,
      lower(trim(coalesce(cp.topic,''))) topic,
      lower(trim(coalesce(cp.hook_type,''))) hook,
      'PUBLISHED'::text state,
      cp.published_at ts,
      lower(coalesce(cp.caption,'')) caption
    from public.sc_content_posts cp
    where cp.published_at is not null
      and (p_as_of is null or cp.published_at <= p_as_of)

    union all

    select
      'JOB',
      j.id::text,
      lower(trim(coalesce(j.topic,''))),
      lower(trim(coalesce(j.content_plan->>'hook_type',''))),
      j.status,
      j.updated_at,
      lower(coalesce(j.content_plan->>'caption',''))
    from public.sc_content_jobs j
    where j.status in ('PLANNED','RESEARCHING','RENDERING','READY','PUBLISHED')
      and coalesce((j.qa->>'do_not_publish')::boolean,false)=false
      and coalesce((j.qa->>'publish_blocked')::boolean,false)=false
      and (p_as_of is null or j.updated_at <= p_as_of)
  ),
  scored as (
    select *,
      case when topic=v_topic then 1.0 else extensions.similarity(topic,v_topic) end topic_similarity,
      case
        when v_hook='' or hook='' then 0.0
        when hook=v_hook then 1.0
        else extensions.similarity(hook,v_hook)
      end hook_similarity,
      (v_energy_topic and (topic ~ v_energy_pattern or caption ~ v_energy_pattern)
        and ts >= v_as_of - interval '14 days' and ts <= v_as_of) editorial_overlap
    from corpus
    where topic<>''
  )
  select * into v
  from scored
  order by greatest(topic_similarity,hook_similarity,case when editorial_overlap then 1.0 else 0.0 end) desc,ts desc nulls last
  limit 1;

  if v.ref_id is null then
    return jsonb_build_object('ok',true,'duplicate',false,'reason','EMPTY_CORPUS');
  end if;

  return jsonb_build_object(
    'ok',true,
    'duplicate',(v.topic_similarity>=0.78 or v.hook_similarity>=0.82 or v.editorial_overlap),
    'editorial_rule',case when v.editorial_overlap then 'HOT_WATER_ENERGY_ARGUMENT_14D' else null end,
    'editorial_cooldown_days',14,
    'thresholds',jsonb_build_object('topic',0.78,'hook',0.82),
    'nearest',jsonb_build_object(
      'source',v.source,
      'ref_id',v.ref_id,
      'topic',v.topic,
      'hook',nullif(v.hook,''),
      'state',v.state,
      'topic_similarity',round(v.topic_similarity::numeric,4),
      'hook_similarity',round(v.hook_similarity::numeric,4)
    ),
    'as_of',p_as_of
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.sc_creative_duplicate_check_v1(p_topic text, p_hook text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'sc_internal'
AS $function$
  select sc_internal.sc_creative_duplicate_check_core_v1(p_topic,p_hook,null::timestamptz)
$function$
;
CREATE OR REPLACE FUNCTION public.sc_quality_shadow_record_v2(p_job_id uuid, p_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare j sc_content_jobs; a jsonb; o record; n int; d jsonb; idx int:=0; c jsonb; s jsonb; dim text; minscore int; pagehash text; dup jsonb; weighted numeric;
begin
 select * into j from sc_content_jobs where id=p_job_id for update;
 if j.id is null or j.status not in ('QUALITY_V2_SHADOW_RENDERING','QUALITY_V2_SHADOW_COMPLETE') or j.qa->>'shadow' is distinct from 'true' or j.qa->>'do_not_publish' is distinct from 'true' or j.qa->>'publish_blocked' is distinct from 'true' then return jsonb_build_object('ok',false,'reason','SHADOW_JOB_REQUIRED'); end if;
 if p_evidence->>'guardian_state' is distinct from 'PASS_SHADOW' or p_evidence#>>'{deterministic_floors,ok}' is distinct from 'true' or p_evidence#>>'{preflight,ok}' is distinct from 'true' or p_evidence->>'production_authorization' is distinct from 'false' then return jsonb_build_object('ok',false,'reason','SHADOW_EVIDENCE_REQUIRED'); end if;
 if exists(select 1 from sc_system_health where component='solar_quality_v2_job_'||p_job_id and details ? 'sealed_package') then return jsonb_build_object('ok',false,'reason','SHADOW_ALREADY_SEALED'); end if;
 n:=case when j.format='carousel' then 5 else 1 end;
 select details into d from sc_system_health where component='solar_quality_v2_job_'||p_job_id for update;
 if d is null or d ? 'sealed_package' then return jsonb_build_object('ok',false,'reason','SHADOW_RECORD_MISSING_OR_SEALED'); end if;
 if jsonb_typeof(p_evidence#>'{deterministic_floors,items}') is distinct from 'array' or jsonb_array_length(p_evidence#>'{deterministic_floors,items}')<>n or exists(select 1 from jsonb_array_elements(p_evidence#>'{deterministic_floors,items}')f where f->>'ok' is distinct from 'true' or (j.format<>'reel' and (coalesce((f->>'geometry_count')::int,0)<1 or coalesce((f->>'min_font_px')::int,0)<32))) then return jsonb_build_object('ok',false,'reason','DETERMINISTIC_FLOORS_REQUIRED'); end if;
 dup:=sc_creative_duplicate_check_v1(j.topic,j.content_plan#>>'{quality_v2,pages,0,title}');
 if dup->>'ok' is distinct from 'true' or dup->>'duplicate' is distinct from 'false' then return jsonb_build_object('ok',false,'reason','CANONICAL_DUPLICATE_OR_UNKNOWN'); end if;
 if j.format<>'reel' then
  if jsonb_typeof(p_evidence#>'{visual_review,critiques}') is distinct from 'array' or jsonb_array_length(p_evidence#>'{visual_review,critiques}')<>n or jsonb_array_length(coalesce(p_evidence#>'{visual_review,assessments}','[]'))<>n then return jsonb_build_object('ok',false,'reason','BOUND_CRITIC_REQUIRED'); end if;
  for idx in 0..n-1 loop
   c:=p_evidence#>array['visual_review','critiques',idx::text];s:=p_evidence#>array['visual_review','assessments',idx::text];
   pagehash:=encode(extensions.digest(sc_quality_json_canonical_v2(j.content_plan#>array['quality_v2','pages',idx::text]),'sha256'),'hex');
   if c->>'plan_sha256' is distinct from pagehash or c->>'asset_sha256' is distinct from p_evidence#>>array['artifacts',idx::text,'sha256'] or s->>'state' is distinct from 'SHADOW_PASS' or coalesce((s->>'score')::numeric,0)<82 or jsonb_array_length(coalesce(s->'hard_fails','[null]'))<>0 then return jsonb_build_object('ok',false,'reason','QUALITY_CRITIC_BINDING'); end if;
   foreach dim in array array['hook','clarity','design','readability','naturalness','value','brand','variety']loop
    minscore:=case when dim in ('clarity','design','readability','value') then 4 else 3 end;
    if jsonb_typeof(c#>array['scores',dim]) is distinct from 'number' or coalesce((c#>>array['scores',dim])::numeric,0)<minscore or (c#>>array['scores',dim])::numeric>5 or length(coalesce(c#>>array['evidence',dim],''))<12 then return jsonb_build_object('ok',false,'reason','CRITIC_HARD_FLOOR'); end if;
   end loop;

   select round(sum((c#>>array['scores',k])::numeric*w/5)-coalesce((s->>'variety_penalty')::numeric,0),1) into weighted from (values ('hook',10),('clarity',15),('design',15),('readability',20),('naturalness',10),('value',15),('brand',5),('variety',10)) weights(k,w);
   if weighted<82 or weighted is distinct from (s->>'score')::numeric then return jsonb_build_object('ok',false,'reason','QUALITY_WEIGHTED_SCORE_BINDING'); end if;
   foreach dim in array array['factuality_pass','scene_match','mobile_360_pass','semantic_novelty_pass','no_clipping']loop
    if c->>dim is distinct from 'true' then return jsonb_build_object('ok',false,'reason','CRITIC_BOOLEAN_FLOOR'); end if;
   end loop;
  end loop;
 else
  if p_evidence#>>'{visual_review,sha256}' is distinct from p_evidence#>>'{artifacts,0,sha256}' or coalesce((p_evidence#>>'{visual_review,score}')::numeric,0)<82 or jsonb_array_length(coalesce(p_evidence#>'{visual_review,review_frame_indices}','[]'))<6 then return jsonb_build_object('ok',false,'reason','REEL_BOUND_REVIEW_REQUIRED'); end if;
 end if;

 if jsonb_typeof(p_evidence->'artifacts') is distinct from 'array' or jsonb_array_length(p_evidence->'artifacts')<>n then return jsonb_build_object('ok',false,'reason','ARTIFACT_COUNT'); end if;
 for a in select value from jsonb_array_elements(p_evidence->'artifacts')loop
  if a->>'sha256' !~ '^[a-f0-9]{64}$' or a->>'sha256' is distinct from a->>'snapshot_sha256' or a->>'snapshot_path' not like 'quality-v2-shadow/snapshots/%' then return jsonb_build_object('ok',false,'reason','SNAPSHOT_HASH_BINDING'); end if;
  select metadata into o from storage.objects where bucket_id='instagram-media' and name=a->>'snapshot_path';
  if not found or o.metadata->>'size' is distinct from a->>'bytes' then return jsonb_build_object('ok',false,'reason','SNAPSHOT_STORAGE_MISSING'); end if;
 end loop;
 if j.format='reel' and sc_quality_reel_technical_strict_v2(p_evidence#>'{artifacts,0,probe}')->>'ok' is distinct from 'true' then return jsonb_build_object('ok',false,'reason','MP4_TECHNICAL_REQUIRED'); end if;
 update sc_content_jobs set status='QUALITY_V2_SHADOW_COMPLETE',asset_urls=(select jsonb_agg(x.value->>'url') from jsonb_array_elements(p_evidence->'artifacts')x(value)),qa=qa||jsonb_build_object('guardian_qa','PASS_SHADOW','quality_v2_phase','PACKAGE_PENDING','quality_v2_guardian','shadow-guardian-v2.0.0'),updated_at=now() where id=p_job_id;
 select * into j from sc_content_jobs where id=p_job_id;
 update sc_system_health set status='GUARDIAN_PASS_SHADOW',details=details||p_evidence||jsonb_build_object('job_plan_sha256',encode(extensions.digest(j.content_plan::text,'sha256'),'hex'),'job_asset_set_sha256',encode(extensions.digest(j.asset_urls::text,'sha256'),'hex')),checked_at=now() where component='solar_quality_v2_job_'||p_job_id and not (details ? 'sealed_package');
 if not found then return jsonb_build_object('ok',false,'reason','SHADOW_RECORD_MISSING_OR_SEALED'); end if;
 return jsonb_build_object('ok',true,'guardian_state','PASS_SHADOW','job_id',p_job_id,'publish_blocked',true,'production_authorization',false);
end; $function$
;

revoke all on function sc_internal.sc_creative_duplicate_check_core_v1(text,text,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.sc_creative_duplicate_check_v1(text,text) from public,anon,authenticated;
grant execute on function public.sc_creative_duplicate_check_v1(text,text) to service_role;
revoke all on function public.sc_quality_shadow_record_v2(uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.sc_quality_json_canonical_v2(jsonb) from public,anon,authenticated;
grant execute on function public.sc_quality_json_canonical_v2(jsonb) to service_role;
