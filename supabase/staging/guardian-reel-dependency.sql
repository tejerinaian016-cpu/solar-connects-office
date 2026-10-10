CREATE OR REPLACE FUNCTION public.sc_reel_technical_contract(p_probe jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare
  t jsonb;
  v_bytes bigint;
  v_fps numeric;
  v_duration numeric;
  v_video_duration numeric;
  v_video_bitrate numeric;
  v_audio_codec text;
  v_audio_rate numeric;
  v_audio_bitrate numeric;
begin
  if coalesce((p_probe->>'ok')::boolean,false) is not true then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_FRESHNESS_UNVERIFIABLE');
  end if;

  t:=public.sc_reel_normalize_probe(p_probe);
  v_bytes:=(t->>'bytes')::bigint;
  v_fps:=(t->>'fps')::numeric;
  v_duration:=(t->>'duration_seconds')::numeric;
  v_video_duration:=nullif(p_probe #>> '{video,duration_seconds}','')::numeric;
  v_video_bitrate:=nullif(t->>'video_bitrate_bps','')::numeric;
  v_audio_codec:=t->>'audio_codec';
  v_audio_rate:=nullif(t->>'audio_sample_rate_hz','')::numeric;
  v_audio_bitrate:=nullif(t->>'audio_bitrate_bps','')::numeric;

  if t->>'mime'<>'video/mp4' then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_MIME_INVALID','technical',t);
  end if;
  if t->>'container'<>'mp4' then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_CONTAINER_INVALID','technical',t);
  end if;
  if v_bytes<1024 or v_bytes>52428800 then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_FILE_SIZE_OUTSIDE_INTERNAL_CONTRACT','technical',t);
  end if;
  if t->>'video_codec'<>'h264' then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_CODEC_INVALID','technical',t);
  end if;
  if (t->>'width')::int<>1080 or (t->>'height')::int<>1920 then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_DIMENSIONS_INVALID','technical',t);
  end if;
  if v_fps<23 or v_fps>60 then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_FPS_INVALID','technical',t);
  end if;
  if v_duration<3 or v_duration>900 then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_DURATION_INVALID','technical',t);
  end if;
  if v_video_duration is null or abs(v_video_duration-v_duration)>0.25 then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_DURATION_METADATA_INCONSISTENT','technical',t);
  end if;
  if v_video_bitrate is null or v_video_bitrate<=0 or v_video_bitrate>25000000 then
    return jsonb_build_object('ok',false,'reason','HOLD_REEL_VIDEO_BITRATE_INVALID','technical',t);
  end if;
  if v_audio_codec is not null then
    if v_audio_codec<>'aac' then
      return jsonb_build_object('ok',false,'reason','HOLD_REEL_AUDIO_CODEC_INVALID','technical',t);
    end if;
    if v_audio_rate is null or abs(v_audio_rate-48000)>1 then
      return jsonb_build_object('ok',false,'reason','HOLD_REEL_AUDIO_SAMPLE_RATE_INVALID','technical',t);
    end if;
    if v_audio_bitrate is null or v_audio_bitrate<=0 or v_audio_bitrate>128000 then
      return jsonb_build_object('ok',false,'reason','HOLD_REEL_AUDIO_BITRATE_INVALID','technical',t);
    end if;
  end if;

  return jsonb_build_object('ok',true,'reason','REEL_TECHNICAL_CONTRACT_PASS','technical',t);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.sc_quality_reel_technical_strict_v2(p_probe jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare k text;
begin
 if p_probe->>'ok' is distinct from 'true' or coalesce(p_probe->>'sha256','') !~ '^[a-f0-9]{64}$' or not (p_probe ? 'audio') then return jsonb_build_object('ok',false,'reason','MP4_FRESH_PROBE_REQUIRED'); end if;
 foreach k in array array['bytes','duration_seconds']loop
  if jsonb_typeof(p_probe->k) is distinct from 'number' then return jsonb_build_object('ok',false,'reason','MP4_REQUIRED_NUMERIC:'||k); end if;
 end loop;
 foreach k in array array['width','height','fps','duration_seconds','bitrate_bps']loop
  if jsonb_typeof(p_probe#>array['video',k]) is distinct from 'number' then return jsonb_build_object('ok',false,'reason','MP4_REQUIRED_VIDEO_NUMERIC:'||k); end if;
 end loop;
 return sc_reel_technical_contract(p_probe);
end; $function$
;
revoke all on function public.sc_reel_technical_contract(jsonb),public.sc_quality_reel_technical_strict_v2(jsonb) from public,anon,authenticated,service_role;
