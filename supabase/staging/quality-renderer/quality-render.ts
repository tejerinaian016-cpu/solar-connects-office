import {Image} from "https://deno.land/x/imagescript@1.2.15/mod.ts";
import {TOKENS,VERSION,preflight,norm,canonical} from "./quality.mjs";
const BASE=Deno.env.get("SUPABASE_URL")!;
const BOLD=BASE+"/storage/v1/object/public/solar-connects-assets/fonts/Roboto-Bold.ttf";
const REGULAR=BASE+"/storage/v1/object/public/solar-connects-assets/fonts/Roboto-Regular.ttf";
const LICENSE=BASE+"/storage/v1/object/public/solar-connects-assets/fonts/LICENSE";
const SCENES={}; // No production scenes permitted in this isolated diagnostic.
const hex=s=>Number.parseInt(s.slice(1)+"ff",16);
const C=Object.fromEntries(Object.entries(TOKENS.colors).map(([k,v])=>[k,hex(v)]));
let fonts;
const textCache=new Map();
export async function sha(b){return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",b))).map(x=>x.toString(16).padStart(2,"0")).join("");}
async function bytes(url){const r=await fetch(url,{signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error("ASSET_FETCH_"+r.status);const b=new Uint8Array(await r.arrayBuffer());if(b.length>10*1024*1024)throw Error("ASSET_SIZE");return b;}
export async function fontPair(sb){
 if(!fonts)fonts=(async()=>{const [b,reg]=await Promise.all([bytes(BOLD),bytes(REGULAR)]);const hash=await sha(reg);if(hash!=="56a45233d29f11b4dfb86d248e921939d115778f87325e7ae8cc108383d6664d")throw Error("REGULAR_FONT_HASH");return {bold:b,regular:reg,regular_sha256:hash};})();
 return fonts;
}
export async function save(sb,path,b,mime){
 if(!path.startsWith("quality-v2-shadow/")||path.includes(".."))throw Error("SHADOW_PATH_REQUIRED");
 const old=await sb.storage.from("instagram-media").download(path);
 const hash=await sha(b);
 if(!old.error&&old.data){if(await sha(new Uint8Array(await old.data.arrayBuffer()))!==hash)throw Error("IMMUTABLE_SHADOW_CONFLICT");return;}
 const u=await sb.storage.from("instagram-media").upload(path,b,{contentType:mime,upsert:false,cacheControl:"3600"});if(u.error){const chk=await sb.storage.from("instagram-media").download(path);if(chk.error||!chk.data||await sha(new Uint8Array(await chk.data.arrayBuffer()))!==hash)throw Error("SHADOW_UPLOAD_"+u.error.message);}
}
function box(im,x,y,w,h,color){im.drawBox(Math.round(x),Math.round(y),Math.round(w),Math.round(h),color);}
function circle(im,x,y,r,color){im.drawCircle(Math.round(x),Math.round(y),Math.round(r),color);}
function rr(im,x,y,w,h,r,color){box(im,x+r,y,w-2*r,h,color);box(im,x,y+r,w,h-2*r,color);for(const [xx,yy] of [[x+r,y+r],[x+w-r,y+r],[x+r,y+h-r],[x+w-r,y+h-r]])circle(im,xx,yy,r,color);}
async function glyph(f,size,s,color,weight){const key=weight+"|"+size+"|"+s+"|"+color;if(!textCache.has(key)){if(textCache.size>=96)textCache.delete(textCache.keys().next().value);textCache.set(key,await Image.renderText(f,size,s,color));}return textCache.get(key);}
async function text(im,f,s,x,y,w,size,color,weight,report,maxLines=3){
 s=norm(s);if(!s)return y;
 const lines=[];let line="";
 for(const word of s.split(" ")){const trial=line?line+" "+word:word;const g=await glyph(f,size,trial,color,weight);if(g.width>w&&line){lines.push(line);line=word;}else line=trial;}
 if(line)lines.push(line);if(lines.length>maxLines)throw Error("TEXT_LINES_"+s.slice(0,30));
 let yy=y;for(const l of lines){const g=await glyph(f,size,l,color,weight);if(g.width>w)throw Error("TEXT_WIDTH");im.composite(g,x,Math.round(yy));report.push({kind:"text",text:l,x,y:Math.round(yy),w:g.width,h:g.height,font_px:size,weight});yy+=Math.max(size*1.18,g.height+8);}
 return yy;
}
async function logo(im,f,x,y,color,report){circle(im,x+18,y+18,18,C.sun);circle(im,x+18,y+18,9,C.ember);return text(im,f,"SOLAR CONNECTS",x+52,y,520,32,color,"bold",report,1);}
async function scene(im,key,x,y,w,h){
 const s=SCENES[key];if(!s)throw Error("SCENE_NOT_APPROVED");
 const b=await bytes(s.public_url);if(await sha(b)!==s.sha256)throw Error("SCENE_HASH");
 const a=await Image.decode(b);const k=Math.min(w/a.width,h/a.height);a.resize(Math.round(a.width*k),Math.round(a.height*k));im.composite(a,Math.round(x+(w-a.width)/2),Math.round(y+(h-a.height)/2));
 return {key,sha256:s.sha256,x:Math.round(x+(w-a.width)/2),y:Math.round(y+(h-a.height)/2),w:a.width,h:a.height,no_crop:true};
}
async function document(im,f,x,y,w,h,palette,report,label="FICHA"){
 rr(im,x,y,w,h,24,palette.panel);box(im,x+36,y+40,90,10,C.ember);
 await text(im,f.bold,label,x+36,y+84,w-72,48,palette.ink,"bold",report,1);
 await text(im,f.bold,"TÉCNICA",x+36,y+143,w-72,48,palette.ink,"bold",report,1);
 for(let i=0;i<3;i++)box(im,x+36,y+242+i*40,w-72-(i===2?70:0),7,C.line);
}
async function diagram(im,f,x,y,w,h,P,report,phase=1){
 // Conceptual two-node diagram, not an installation schematic.
 const m=typeof phase==="number"?{flow:phase,heat:0,pulse:0}:phase;
 const cy=y+h*.78,tx=x+w*.60,ty=y+h*.12;
 rr(im,x,cy-105,w*.42,150,22,P.panel);
 await text(im,f.bold,"COLECTOR",x+24,cy-62,w*.4,36,P.ink,"bold",report,1);
 rr(im,tx,ty,w*.4,135,24,P.panel);
 await text(im,f.bold,"DEPÓSITO",tx+20,ty+43,w*.37,36,P.ink,"bold",report,1);
 // Orange directional path; it explains the claim without fake plumbing detail.
 const ax=x+w*.5,start=cy-20,end=ty+70;
 box(im,ax-5,end,10,start-end,C.ember);
 for(let i=0;i<20;i++)box(im,ax-i,end+i,2*i+1,3,C.ember);
 const py=start-(start-end)*Math.max(0,Math.min(1,m.flow));
 if(m.heat>0){circle(im,x+44,cy-154,20+Math.round(8*m.heat),C.ember);circle(im,x+44,cy-154,12+Math.round(5*m.heat),C.sun);}
 if(m.pulse>0)circle(im,ax,py,20+Math.round(7*m.pulse),C.ember);
 circle(im,ax,py,18,C.sun);
 circle(im,ax,py,8,C.ember);
 await text(im,f.regular,"El agua calentada asciende",x,y+h-34,w,36,P.text,"regular",report,1);
}
export async function render(p,sb,pose=1,measureOnly=false){
 const pf=preflight(p,p.history||[]);if(!pf.ok)throw Error("PREFLIGHT_"+pf.errors.join(","));
 if(p.job_id)throw Error("SHADOW_ONLY_NO_JOB_ID");
 if(p.fact_ids?.length){const {data,error}=await sb.from("sc_fact_bank").select("fact_id,status").in("fact_id",p.fact_ids);if(error||data?.length!==p.fact_ids.length||data.some(x=>x.status!=="APPROVED"))throw Error("FACTS_NOT_APPROVED");}
 const f=await fontPair(sb),vertical=["story","reel"].includes(p.format),H=vertical?1920:1350,im=measureOnly?{fill(){},drawBox(){},drawCircle(){},composite(){}}:new Image(1080,H),dark=p.theme==="dark";
 const P={bg:dark?C.ink:C.cream,text:dark?C.cream:C.ink,ink:C.ink,panel:dark?C.cream:0xffffffff,muted:dark?C.cream:C.muted};
 const report=[],scenes=[];im.fill(P.bg);
 const x=72,w=vertical?852:936,top=vertical?220:72,bottom=vertical?1560:1278;
 await logo(im,f.bold,x,top,P.text,report);
 const ey=top+104;
 if(p.eyebrow)await text(im,f.bold,p.eyebrow.toUpperCase(),x,ey,w,36,dark?C.sun:C.text_accent,"bold",report,1);
 let titleY=ey+72;let titleSize=p.layout==="statement"?96:84;
 const titleEnd=await text(im,f.bold,p.title,x,titleY,w,titleSize,P.text,"bold",report,3);
 let bodyY=titleEnd+36,bodyEnd=await text(im,f.regular,p.body,x,bodyY,w,44,P.muted,"regular",report,3);
 const contentTop=bodyEnd+48,ctaY=bottom-60;
 if(p.layout==="editorial_scene"){
  const maxH=ctaY-contentTop-44;if(maxH<250)throw Error("SCENE_SPACE");
  scenes.push(await scene(im,p.scene,x,contentTop,w,maxH));
 }else if(p.layout==="process_diagram"){
  const dy=p.format==="reel"?844:contentTop,hh=p.format==="reel"?566:ctaY-contentTop-48;if(hh<310||contentTop>dy)throw Error("DIAGRAM_SPACE");
  await diagram(im,f,x,dy,w,hh,P,report,pose);
 }else if(p.layout==="document_focus"||(p.layout==="statement"&&p.scene==="document_focus")){
  const hh=Math.min(420,ctaY-contentTop-44);
  if(hh<320)throw Error("DOCUMENT_SPACE");
  circle(im,x+w*.78,contentTop+hh*.6,Math.min(125,hh*.32),C.sun);
  await document(im,f,x+18,contentTop,Math.min(500,w*.60),hh,P,report,p.document_label||"FICHA");
 }else if(p.layout==="paired_factors"){
  const hh=Math.min(280,Math.floor((ctaY-contentTop-68)/2));
  if(hh<170)throw Error("FACTORS_SPACE");
  for(let i=0;i<2;i++){const yy=contentTop+i*(hh+24);rr(im,x,yy,w,hh,24,P.panel);await text(im,f.bold,p.items[i].title,x+32,yy+30,w-64,48,P.ink,"bold",report,1);await text(im,f.regular,p.items[i].body,x+32,yy+100,w-64,42,C.muted,"regular",report,2);}
 }else{
  if(p.layout==="statement"&&p.section_titles?.length){await text(im,f.bold,String(p.section_titles.length),x,contentTop,w,280,dark?C.sun:C.ink,"bold",report,1);await text(im,f.regular,"ASPECTOS",x+250,contentTop+236,w-250,42,P.text,"regular",report,1);}else box(im,x,contentTop,144,12,C.sun);
  if(p.scene==="backup_duo")scenes.push(await scene(im,p.scene,x,contentTop+40,w,ctaY-contentTop-84));
 }
 if(p.cta){box(im,x,ctaY-28,w,3,dark?C.muted:C.line);await text(im,f.bold,p.cta,x,ctaY,w,42,dark?C.sun:C.ink,"bold",report,1);}
 for(const b of report)if(b.x<x||b.x+b.w>1080-(vertical?156:72)+1||b.y<top||b.y+b.h>bottom+1)throw Error("SAFE_AREA_"+b.text);
 for(let i=0;i<report.length;i++)for(let j=i+1;j<report.length;j++){const a=report[i],b=report[j];if(a.x+a.w>b.x+1&&b.x+b.w>a.x+1&&a.y+a.h>b.y+1&&b.y+b.h>a.y+1)throw Error("TEXT_COLLISION_"+a.text+"_"+b.text);}
 return {im,report,scenes,width:1080,height:H,preflight:pf,regular_font_sha256:f.regular_sha256,safe_area:{left:72,right:vertical?156:72,top,bottom_inset:H-bottom},theme:p.theme};
}
export async function renderAction(p,sb){
 const t=performance.now(),plan=p.plan;if(!plan||p.mode!=="SHADOW")throw Error("SHADOW_MODE_REQUIRED");
 const r=await render(plan,sb,p.pose??1),jpg=await r.im.encodeJPEG(90),hash=await sha(jpg),ph=await sha(new TextEncoder().encode(canonical(plan)));
 const path="quality-v2-shadow/renders/"+ph+"/"+hash+".jpg";await save(sb,path,jpg,"image/jpeg");
 r.im.resize(360,Math.round(360*r.height/r.width));const preview=await r.im.encodeJPEG(84);let bin="";for(const b of preview)bin+=String.fromCharCode(b);
 return {ok:true,mode:"SHADOW",version:VERSION,production_authorization:false,external_write:false,storage_write:true,path,url:BASE+"/storage/v1/object/public/instagram-media/"+path,sha256:hash,plan_sha256:ph,width:r.width,height:r.height,mime:"image/jpeg",base64:btoa(bin),geometry:r.report,scenes:r.scenes,preflight:r.preflight,safe_area:r.safe_area,regular_font_sha256:r.regular_font_sha256,elapsed_ms:Math.round(performance.now()-t)};
}
