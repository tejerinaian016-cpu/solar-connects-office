import {Image} from "https://deno.land/x/imagescript@1.2.15/mod.ts";
import {preflight,preflightSequence,evaluate,canonical,TOKENS} from "./quality.mjs";
import {renderAction,render,sha,save} from "./quality-render.ts";
import {parseMp4,techPass} from "./parser.ts";
const BASE=Deno.env.get("SUPABASE_URL")!;
async function rpc(sb,n,b){const r=await sb.rpc(n,b);if(r.error)throw Error("RPC_"+n+"_"+r.error.code);return r.data;}
async function job(sb,id){
 if(!/^[a-f0-9-]{36}$/.test(id||""))throw Error("JOB_ID");
 const r=await sb.from("sc_content_jobs").select("*").eq("id",id).single();
 if(r.error||!r.data||!["QUALITY_V2_SHADOW_RENDERING","QUALITY_V2_SHADOW_COMPLETE"].includes(r.data.status)||r.data.qa.shadow!==true||r.data.qa.publish_blocked!==true||r.data.qa.do_not_publish!==true)throw Error("SHADOW_JOB_REQUIRED");
 const d=await sb.from("sc_system_health").select("details").eq("component","solar_quality_v2_job_"+id).single();if(d.error)throw Error("SHADOW_RECORD");return {j:r.data,d:{...d.data.details,...(r.data.qa.quality_v2_runtime||{})}};
}
function floors(r){
 const errors=[],vertical=r.height===1920,min={left:72,right:vertical?156:72,top:vertical?220:72,bottom:vertical?360:72};
 if(r.width!==1080||![1350,1920].includes(r.height))errors.push("DIMENSIONS");
 if(!Array.isArray(r.geometry)||!r.geometry.length)errors.push("MEASURED_GEOMETRY_REQUIRED");
 const g=r.geometry||[];
 for(const b of g){
  if(![b.x,b.y,b.w,b.h,b.font_px].every(Number.isFinite)||b.w<=0||b.h<=0||b.font_px<32)errors.push("FONT_OR_GEOMETRY");
  if(b.x<min.left||b.x+b.w>1080-min.right+1||b.y<min.top||b.y+b.h>r.height-min.bottom+1)errors.push("SAFE_AREA");
 }
 for(let i=0;i<g.length;i++)for(let k=i+1;k<g.length;k++){const a=g[i],b=g[k];if(a.x+a.w>b.x+1&&b.x+b.w>a.x+1&&a.y+a.h>b.y+1&&b.y+b.h>a.y+1)errors.push("TEXT_COLLISION");}
 if(r.regular_font_sha256!=="56a45233d29f11b4dfb86d248e921939d115778f87325e7ae8cc108383d6664d")errors.push("FONT_BINDING");
 return {ok:errors.length===0,errors:[...new Set(errors)],geometry_count:g.length,min_font_px:g.length?Math.min(...g.map(x=>x.font_px)):null,known_palette_contrast_floor:4.94};
}
async function bytes(sb,path){if(!path.startsWith("quality-v2-shadow/")||path.includes(".."))throw Error("SHADOW_PATH");const r=await sb.storage.from("instagram-media").download(path);if(r.error||!r.data)throw Error("ARTIFACT_MISSING");const b=new Uint8Array(await r.data.arrayBuffer());if(b.length>40*1024*1024)throw Error("ARTIFACT_SIZE");return b;}
async function updateDetails(sb,id,patch){
 const {j,d}=await job(sb,id);if(d.sealed_package)throw Error("SEALED");
 const runtime={...(j.qa.quality_v2_runtime||{})};
 if(patch.render_page){const {index,render}=patch.render_page;runtime.renders={...(runtime.renders||{}),[index]:render};}
 Object.assign(runtime,Object.fromEntries(Object.entries(patch).filter(([k])=>k!=="render_page")));
 const r=await sb.from("sc_content_jobs").update({qa:{...j.qa,quality_v2_runtime:runtime}}).eq("id",id).eq("status","QUALITY_V2_SHADOW_RENDERING");
 if(r.error)throw Error("SHADOW_PROGRESS_"+r.error.code);
}
export async function pipelineAction(p,sb){
 if(p.mode!=="SHADOW")throw Error("SHADOW_ONLY");
 if(p.operation==="adapt"){if(p.opt_in?.enabled===true)return {ok:false,state:"CONNECTOR_SQL_REQUIRED",reason:"Use existing authorized SQL connector for sc_quality_factory_from_run_v2/sc_quality_factory_adapter_v2; direct service_role INSERT is denied; permissions unchanged.",production_authorization:false};return await rpc(sb,"sc_quality_factory_adapter_v2",{p_factory:p.factory_output,p_opt_in:p.opt_in||{}});}
 const {j,d}=await job(sb,p.job_id),pages=j.content_plan.quality_v2.pages,revision=Math.max(...pages.map(x=>x.revision??0)),seq=preflightSequence(pages,j.format,revision);
 const dup=await rpc(sb,"sc_creative_duplicate_check_v1",{p_topic:j.topic,p_hook:pages[0].title});
 if(!seq.ok)return {ok:false,state:"HOLD",reason:"PREFLIGHT",preflight:seq};
 if(p.operation==="preflight")return {ok:true,preflight:seq,anti_duplicate:dup,production_authorization:false};
 if(p.operation==="render"){
  if(d.sealed_package)throw Error("ALREADY_SEALED");
  if(j.format==="reel")throw Error("REEL_USE_EXISTING_FINAL_OR_BOUNDED_MOTION");
  const idx=p.page_index??0;if(!Number.isInteger(idx)||idx<0||idx>=pages.length)throw Error("PAGE_INDEX");
  const ph=await sha(new TextEncoder().encode(canonical(pages[idx]))),old=d.renders?.[idx];
  if(old&&old.plan_sha256===ph){const b=await bytes(sb,old.path);if(await sha(b)!==old.sha256)throw Error("CACHED_HASH");return {ok:true,reused:true,render:old,production_authorization:false};}
  const dir="quality-v2-shadow/renders/"+ph,ls=await sb.storage.from("instagram-media").list(dir,{limit:2});
  const names=(ls.data||[]).filter(x=>/^[a-f0-9]{64}\.jpg$/.test(x.name));
  let r,reused=false;
  if(names.length===1){
   const path=dir+"/"+names[0].name,b=await bytes(sb,path),h=await sha(b);if(h!==names[0].name.slice(0,64))throw Error("CACHE_SHA");
   const img=await Image.decode(b),measure=await render(pages[idx],sb,1,true);
   if(img.width!==measure.width||img.height!==measure.height)throw Error("CACHE_DIMENSIONS");
   img.resize(360,Math.round(360*img.height/img.width));const jpg=await img.encodeJPEG(84);let bin="";for(const x of jpg)bin+=String.fromCharCode(x);
   r={ok:true,mode:"SHADOW",path,url:BASE+"/storage/v1/object/public/instagram-media/"+path,sha256:h,plan_sha256:ph,width:measure.width,height:measure.height,base64:btoa(bin),geometry:measure.report,safe_area:measure.safe_area,regular_font_sha256:measure.regular_font_sha256,scenes:measure.scenes,preflight:measure.preflight,geometry_method:"Text-only measurement; no full image rerender; original plan-bound JPEG readback"};reused=true;
  }else{r=await renderAction({mode:"SHADOW",plan:pages[idx]},sb);}
  const f=floors(r);if(!f.ok)return {ok:false,state:"HOLD",reason:"DETERMINISTIC_FLOORS",floors:f};
  const stored={...r};delete stored.base64;
  const patch={render_page:{index:idx,render:stored},preflight:seq};
  await updateDetails(sb,j.id,patch);
  return {ok:true,reused,render:r,floors:f,progress_patch:patch,production_authorization:false};
 }
 if(p.operation==="register_reel"){
  if(j.format!=="reel"||d.sealed_package)throw Error("UNSEALED_REEL_REQUIRED");
  const sequenceHash=await sha(new TextEncoder().encode(canonical({version:"motion-v2.1",shots:pages,poses:80,chunk:4,shot_frames:[24,24,32],renderer_revision:"2.0-shadow.2",profile:"single_flow"})));
  const h=String(p.asset_sha256||""),path="quality-v2-shadow/motion/"+sequenceHash+"/final_"+h+".mp4";
  if(!/^[a-f0-9]{64}$/.test(h)||p.path!==path||p.sequence_hash!==sequenceHash)throw Error("NATURAL_REEL_PLAN_BINDING");
  const b=await bytes(sb,path);if(await sha(b)!==h)throw Error("FRESH_MP4_SHA");
  const probe={ok:true,...parseMp4(b),bytes:b.length,mime:"video/mp4",sha256:h},tc=await rpc(sb,"sc_quality_reel_technical_strict_v2",{p_probe:probe});if(tc.ok!==true)throw Error("STRICT_MP4");
  const review=p.review,indices=[0,69,72,141,144,239],weights={hook:10,clarity:15,design:15,readability:20,naturalness:10,value:15,brand:5,variety:10};let score=0;
  if(review?.sha256!==h||review.sequence_hash!==sequenceHash||JSON.stringify(review.review_frame_indices)!==JSON.stringify(indices))throw Error("NATURAL_REEL_REVIEW_BINDING");
  for(const [dim,w] of Object.entries(weights)){const v=review.scores?.[dim];if(!Number.isFinite(v)||v>(5)||v<(["clarity","design","readability","value"].includes(dim)?4:3)||typeof review.evidence?.[dim]!=="string"||review.evidence[dim].trim().length<12)throw Error("REEL_REVIEW_FLOOR");score+=v*w/5;}
  for(const k of ["factuality_pass","scene_match","mobile_360_pass","semantic_novelty_pass","no_clipping"])if(review[k]!==true)throw Error("REEL_BOOLEAN_FLOOR");
  if(score<82)throw Error("REEL_SCORE_FLOOR");
  const artifact={path,url:BASE+"/storage/v1/object/public/instagram-media/"+path,sha256:h,bytes:b.length,mime:"video/mp4",width:1080,height:1920,probe};
  const patch={adopted_reel:artifact,archived_review:{...review,score,source:"NATURAL_V2_FINAL_MP4_REVIEW",scope:"Fresh final MP4 bound to current job pages; archived demonstration not reused"}};
  await updateDetails(sb,j.id,patch);
  return {ok:true,artifact,technical_contract:tc,progress_patch:patch,production_authorization:false};
 }
 if(p.operation==="adopt_reel"){
  if(j.format!=="reel"||d.sealed_package)throw Error("REEL_SHADOW_REQUIRED");
  const h=await sb.from("sc_system_health").select("details").eq("component","solar_quality_upgrade_v2").single(),a=h.data?.details?.quality_v2_implementation?.canary?.reel;
  if(!a||p.asset_sha256!==a.sha256||p.path!==a.path)throw Error("ARCHIVED_FINAL_BINDING");
  if(pages.some(x=>x.layout!=="process_diagram"||!x.fact_ids.includes("SC-F012")))throw Error("ARCHIVED_SEMANTIC_BINDING");
  const b=await bytes(sb,a.path);if(await sha(b)!==a.sha256)throw Error("FINAL_SHA");
  const probe={ok:true,...parseMp4(b),bytes:b.length,mime:"video/mp4",sha256:a.sha256};
  const tc=techPass(probe);if(!tc.ok)throw Error(tc.reason);
  const sqltc=await rpc(sb,"sc_quality_reel_technical_strict_v2",{p_probe:probe});if(sqltc.ok!==true)throw Error(sqltc.reason);
  const archived=h.data.details.quality_v2_implementation.canary.visual_assessments.find(x=>x.asset==="revised_final_reel");
  if(archived?.state!=="SHADOW_PASS"||archived.score<82||a.review_frame_indices?.length!==6)throw Error("ARCHIVED_REVIEW_REQUIRED");
  const artifact={path:a.path,url:a.url,sha256:a.sha256,bytes:b.length,mime:"video/mp4",width:1080,height:1920,probe};
  const patch={adopted_reel:artifact,archived_review:{source_component:"solar_quality_upgrade_v2",source_version:"2.0-shadow.1",sha256:a.sha256,score:archived.score,review_frame_indices:a.review_frame_indices,scope:"Existing MP4 visual review reused; no new render or video decode"}};
  await updateDetails(sb,j.id,patch);return {ok:true,artifact,technical_contract:sqltc,review_reused:true,progress_patch:patch,production_authorization:false};
 }
 if(p.operation==="guardian"){
  if(d.sealed_package)return {ok:true,idempotent:true,guardian_state:d.guardian_state,production_authorization:false};
  const artifacts=[],assessments=[],det=[];let review;
  if(j.format==="reel"){
   if(!d.adopted_reel||!d.archived_review)throw Error("MP4_AND_BOUND_REVIEW_REQUIRED");
   const a=d.adopted_reel,b=await bytes(sb,a.path);if(await sha(b)!==a.sha256)throw Error("FRESH_REEL_SHA");
   const probe={ok:true,...parseMp4(b),bytes:b.length,mime:"video/mp4",sha256:a.sha256},tc=await rpc(sb,"sc_quality_reel_technical_strict_v2",{p_probe:probe});if(!tc.ok)throw Error(tc.reason);
   artifacts.push({...a,probe});det.push({ok:true,kind:"MP4_TECHNICAL_AND_ARCHIVED_MOBILE_REVIEW",technical:tc});
   review=d.archived_review;
  }else{
   if(!Array.isArray(p.critiques)||p.critiques.length!==pages.length)throw Error("CRITIC_COUNT");
   for(let idx=0;idx<pages.length;idx++){
    const r=d.renders?.[idx];if(!r)throw Error("RENDER_MISSING_"+idx);
    const ph=await sha(new TextEncoder().encode(canonical(pages[idx])));if(r.plan_sha256!==ph)throw Error("PLAN_BINDING");
    const b=await bytes(sb,r.path);if(await sha(b)!==r.sha256)throw Error("FRESH_IMAGE_SHA");const im=await Image.decode(b);if(im.width!==r.width||im.height!==r.height)throw Error("FRESH_IMAGE_DIMENSIONS");
    const f=floors(r);if(!f.ok)throw Error("DETERMINISTIC_FLOOR");det.push(f);
    const c=p.critiques[idx],a=evaluate(pages[idx],c,p.history||[],{asset_sha256:r.sha256,plan_sha256:r.plan_sha256});assessments.push(a);
    if(a.state!=="SHADOW_PASS"){return {ok:false,state:a.state,assessment:a,progress_patch:{last_assessment:a,critic:p.critiques},production_authorization:false};}
    artifacts.push({path:r.path,url:r.url,sha256:r.sha256,bytes:b.length,mime:"image/jpeg",width:r.width,height:r.height,plan_sha256:r.plan_sha256});
   }
   review={critiques:p.critiques,assessments};
  }
  if(dup?.duplicate===true)return {ok:false,state:"HOLD",reason:"CANONICAL_DUPLICATE",anti_duplicate:dup};
  for(const a of artifacts){
   const ext=a.mime==="video/mp4"?"mp4":"jpg",path="quality-v2-shadow/snapshots/"+j.id+"/"+a.sha256+"."+ext,b=await bytes(sb,a.path);
   await save(sb,path,b,a.mime);const rb=await bytes(sb,path);if(await sha(rb)!==a.sha256)throw Error("SNAPSHOT_FRESH_HASH");
   Object.assign(a,{snapshot_path:path,snapshot_sha256:a.sha256,snapshot_url:BASE+"/storage/v1/object/public/instagram-media/"+path});
  }
  const evidence={guardian_state:"PASS_SHADOW",guardian_version:"shadow-guardian-v2.0.0",preflight:seq,anti_duplicate:dup,deterministic_floors:{ok:true,items:det},artifacts,visual_review:review,production_authorization:false,external_write:false};
  await updateDetails(sb,j.id,{guardian_pending_evidence:evidence});return {ok:true,guardian_state:"PASS_PENDING_DURABLE_COMMIT",evidence,production_authorization:false};
 }
 if(p.operation==="package")return await rpc(sb,"sc_quality_shadow_package_v2",{p_job_id:j.id});
 if(p.operation==="publisher_dry_run"){
  const pk=await rpc(sb,"sc_quality_shadow_package_v2",{p_job_id:j.id});if(!pk.ok)return pk;
  return {ok:true,validation:await rpc(sb,"sc_validate_publish_package_deep",{p_package:pk.package}),plan:await rpc(sb,"sc_meta_direct_plan_from_package",{p_package:pk.package}),canonical_production_get:await rpc(sb,"sc_get_publish_package",{p_job_id:j.id}),feed_budget:await rpc(sb,"sc_feed_daily_budget_v1",{}),anti_duplicate:dup,projection_only:true,external_http_calls:0,external_write_enabled:false};
 }
 throw Error("PIPELINE_OPERATION");
}
