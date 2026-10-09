export const VERSION="solar-quality-v2.0.0";
export const TOKENS={
 colors:{cream:"#F4F0E3",ink:"#111517",muted:"#4B5153",sun:"#FFD500",ember:"#D34A00",text_accent:"#B83E00",line:"#D4D0C4"},
 typography:{family:"Roboto",headline:84,headline_min:72,body:44,body_min:42,label:36,brand:32,line_height:1.18},
 spacing:[12,24,36,48,72,96],feed:{w:1080,h:1350,margin:72},
 vertical:{w:1080,h:1920,left:72,right:156,top:220,bottom:360},
 brand:{once_per_frame:true,wordmark:"SOLAR CONNECTS",no_permanent_footer:true},
 tato:{rule:"Only in human consultation scene; no sticker duplication; maximum2 of5carouselpages; preserve locked artwork"},
};
export const LIBRARY={
 statement:{intent:["question","decision","myth"],scenes:["none","document_focus"],formats:["image","carousel","story"]},
 editorial_scene:{intent:["consultation","assessment"],scenes:["backup_duo","backup_installation"],formats:["image","carousel","story"]},
 process_diagram:{intent:["mechanism"],scenes:["thermosiphon_concept"],formats:["image","carousel","story","reel"]},
 document_focus:{intent:["decision","checklist"],scenes:["document_focus"],formats:["image","carousel","story","reel"]},
 paired_factors:{intent:["checklist","assessment"],scenes:["none"],formats:["image","carousel","story"]},
 action_close:{intent:["action","consultation"],scenes:["none","backup_duo"],formats:["image","carousel","story","reel"]}
};
export const WEIGHTS={hook:10,clarity:15,design:15,readability:20,naturalness:10,value:15,brand:5,variety:10};
export const norm=s=>String(s??"").normalize("NFKC").replace(/\s+/gu," ").trim();
export const wc=s=>norm(s)?norm(s).split(" ").length:0;
export function canonical(value){if(Array.isArray(value))return "["+value.map(canonical).join(",")+"]";if(value&&typeof value==="object")return "{"+Object.keys(value).sort().map(k=>JSON.stringify(k)+":"+canonical(value[k])).join(",")+"}";return JSON.stringify(value);}
export function identity(p){return [p.argument_key,p.decision_key,p.angle_key].map(norm).join("|");}
export function preflight(p,history=[]){
 const errors=[],warnings=[];
 if(!p||typeof p!=="object"||Array.isArray(p)||JSON.stringify(p).length>16000)return {ok:false,errors:["PLAN_INVALID"]};
 const l=LIBRARY[p.layout];
 if(!l||!l.formats.includes(p.format))errors.push("LAYOUT_FORMAT");
 if(l&&!l.intent.includes(p.intent))errors.push("LAYOUT_INTENT");
 if(l&&!l.scenes.includes(p.scene))errors.push("SCENE_INTENT_MISMATCH");
 if(!["cream","dark"].includes(p.theme))errors.push("THEME");
 if(norm(p.title).length>100||norm(p.body).length>200||norm(p.cta).length>56||norm(p.eyebrow).length>32)errors.push("TEXT_CHAR_BUDGET");
 if([p.body,p.cta,p.eyebrow].some(s=>norm(s).split(" ").some(w=>w.length>32)))errors.push("UNBREAKABLE_TEXT");
 if(!norm(p.title)||wc(p.title)>8)errors.push("TITLE_WORDS");
 const bodyLimit=p.format==="reel"?12:20;
 if(wc(p.body)>bodyLimit)errors.push("BODY_WORDS");
 if(wc(p.cta)>6)errors.push("CTA_WORDS");
 if(wc(p.eyebrow)>4)errors.push("EYEBROW_WORDS");
 if(norm(p.title).split(" ").some(x=>x.length>22))errors.push("UNBREAKABLE_TITLE");
 if(!Number.isInteger(p.revision??0)||(p.revision??0)<0||(p.revision??0)>1)errors.push("REVISION_BUDGET");
 if(![p.argument_key,p.decision_key,p.angle_key].every(x=>/^[a-z0-9_]{3,64}$/.test(x||"")))errors.push("EDITORIAL_IDENTITY");
 if(!["question","contrast","mechanism","checklist","observation","action"].includes(p.hook_family))errors.push("HOOK_FAMILY");
 if(!norm(p.added_value))errors.push("ADDED_VALUE_REQUIRED");
 if(p.layout==="paired_factors"&&(!Array.isArray(p.items)||p.items.length!==2||p.items.some(x=>!norm(x.title)||!norm(x.body)||wc(x.title)>4||wc(x.body)>10||norm(x.title).length>36||norm(x.body).length>96)))errors.push("TWO_FACTORS_REQUIRED");
 if(p.section_titles&&(!Array.isArray(p.section_titles)||p.section_titles.length<2||p.section_titles.length>5||p.section_titles.some(x=>!norm(x))))errors.push("SECTION_COUNT");
 if(p.document_label&&!["FICHA","PROPUESTA"].includes(p.document_label))errors.push("DOCUMENT_LABEL");
 if(p.layout==="process_diagram"&&!(p.fact_ids||[]).includes("SC-F012"))errors.push("THERMOSIPHON_FACT_REQUIRED");
 if(/(siempre agua caliente|agua caliente siempre|ahorro garantizado|agua gratis|nunca te falta)/i.test([p.title,p.body,p.cta].join(" ")))errors.push("UNSUPPORTED_ABSOLUTE");
 if(/descubr[ií] el poder|revolucion[aá]|transform[aá] tu vida|soluci[oó]n perfecta|lleva.{0,20}al siguiente nivel/i.test([p.title,p.body].join(" ")))warnings.push("GENERIC_PROMISE");
 if(!Array.isArray(history)||history.length>100)return {ok:false,errors:[...errors,"HISTORY_INVALID"]};
 let penalty=0;
 history.forEach((h,i)=>{
  if(h.editorial_signature===identity(p))errors.push("SAME_ARGUMENT_DECISION_ANGLE");
  if(h.argument_key===p.argument_key&&h.decision_key===p.decision_key&&h.angle_key!==p.angle_key)warnings.push("SAME_ARGUMENT_REQUIRES_DISTINCT_VALUE");
  if(i<3&&h.layout===p.layout)penalty+=i===0?8:4;
  if(i<3&&h.scene===p.scene&&p.scene!=="none")penalty+=4;
  if(i<3&&h.hook_family===p.hook_family)penalty+=3;
  if(i<3&&h.structure_key===p.structure_key&&p.structure_key)penalty+=3;
 });
 if(history[0]?.layout===p.layout&&history[1]?.layout===p.layout)warnings.push("THIRD_CONSECUTIVE_LAYOUT");
 return {ok:errors.length===0,errors:[...new Set(errors)],warnings:[...new Set(warnings)],word_counts:{title:wc(p.title),body:wc(p.body),cta:wc(p.cta)},editorial_signature:identity(p),variety_penalty:Math.min(penalty,25),requires_critic:true,production_authorization:false};
}
export function evaluate(p,c,history=[],binding={}){
 const pre=preflight(p,history),hard=[...pre.errors],missing=[],weighted=[];
 if(!c||typeof c!=="object")return {state:"NEEDS_CRITIC",score:null,hard_fails:hard,production_authorization:false};
 for(const [k,w] of Object.entries(WEIGHTS)){const v=c.scores?.[k],e=c.evidence?.[k];if(!Number.isFinite(v)||v<0||v>5||typeof e!=="string"||norm(e).length<12)missing.push(k);else{weighted.push(v/5*w);if(v<(["clarity","design","readability","value"].includes(k)?4:3))hard.push("FLOOR_"+k);}}
 if(c.factuality_pass!==true)hard.push("FACTUALITY");
 if(c.scene_match!==true)hard.push("SCENE_MATCH");
 if(c.mobile_360_pass!==true)hard.push("MOBILE_READ");
 if(c.semantic_novelty_pass!==true)hard.push("SEMANTIC_REPEAT");
 if(c.no_clipping!==true)hard.push("CLIPPING");
 if(!/^[a-f0-9]{64}$/.test(binding.asset_sha256||"")||c.asset_sha256!==binding.asset_sha256)hard.push("ASSET_BINDING");
 if(!/^[a-f0-9]{64}$/.test(binding.plan_sha256||"")||c.plan_sha256!==binding.plan_sha256)hard.push("PLAN_BINDING");
 if(missing.length)return {state:"NEEDS_CRITIC",score:null,missing,hard_fails:hard,production_authorization:false};
 const score=Math.round((weighted.reduce((a,b)=>a+b,0)-(pre.variety_penalty||0))*10)/10;
 const pass=hard.length===0&&score>=82;
 const fixes=Array.isArray(c.fixes)?c.fixes.filter(x=>norm(x).length>8).slice(0,3):[];
 const eligible=!pass&&(p.revision??0)===0&&fixes.length>0&&Number.isFinite(c.expected_gain)&&c.expected_gain>=5;
 return {state:pass?"SHADOW_PASS":eligible?"REVISE_ONCE":"HOLD",score,variety_penalty:pre.variety_penalty||0,hard_fails:[...new Set(hard)],fixes:eligible?fixes:[],revision_budget_remaining:Math.max(0,1-(p.revision??0)),production_authorization:false,requires_existing_guardian:true};
}
export function selectCandidate(plans,history=[]){return plans.map((p,index)=>({index,plan:p,preflight:preflight(p,history)})).filter(x=>x.preflight.ok).sort((a,b)=>a.preflight.variety_penalty-b.preflight.variety_penalty||a.index-b.index)[0]||null;}

export function preflightSequence(pages,format,revision=0){
 const errors=[],warnings=[];
 if(!Array.isArray(pages)||pages.length!==(format==="carousel"?5:format==="reel"?3:1))return {ok:false,errors:["SEQUENCE_COUNT"],production_authorization:false};
 if(![0,1].includes(revision))errors.push("REVISION_BUDGET");
 let tato=0;const titles=new Set(),values=new Set(),layouts=[];
 for(const p of pages){const r=preflight(p);errors.push(...r.errors);if(p.format!==format)errors.push("SEQUENCE_FORMAT");if((p.revision??0)>revision)errors.push("REVISION_MISMATCH");if(titles.has(norm(p.title).toLowerCase()))errors.push("REPEATED_TITLE");titles.add(norm(p.title).toLowerCase());values.add(norm(p.added_value));layouts.push(p.layout);if(["backup_duo","backup_installation"].includes(p.scene))tato++;}
 if(format==="carousel"){if(tato>2)errors.push("TATO_OVERUSE");if(new Set(layouts).size<3)errors.push("LAYOUT_MONOTONY");if(values.size<3)warnings.push("CHECK_INFORMATION_PROGRESSION");}
 return {ok:errors.length===0,errors:[...new Set(errors)],warnings,production_authorization:false};
}
export function hookBrief(fact,decision,recentFamilies=[]){
 return {max_candidates:3,max_words:8,required:{approved_fact:fact,user_decision:decision},
 preferred_families:["question","contrast","mechanism","checklist","observation"].filter(x=>!recentFamilies.slice(0,2).includes(x)).slice(0,3),
 output_fields:["text","family","payoff"],reject:["claim not supported by approved fact","promise absent from content","vague benefit","fear or invented urgency"],
 instructions:"Write Argentine Spanish. Concrete everyday nouns and verbs. One question or claim. Payoff must be delivered in the piece. Never add facts to improve a hook."};
}
