export const td=new TextDecoder("latin1");
export const four=(b:Uint8Array,o:number)=>td.decode(b.subarray(o,o+4));
export const u32=(b:Uint8Array,o:number)=>new DataView(b.buffer,b.byteOffset,b.byteLength).getUint32(o,false);
export function u64(b:Uint8Array,o:number){const d=new DataView(b.buffer,b.byteOffset,b.byteLength);return Number(d.getBigUint64(o,false))}
export const hex=(b:Uint8Array)=>Array.from(b).map(x=>x.toString(16).padStart(2,"0")).join("");
export async function sha256(bytes:Uint8Array){return hex(new Uint8Array(await crypto.subtle.digest("SHA-256",bytes)))}
export function boxes(b:Uint8Array,start=0,end=b.length){
 const out:any[]=[];let p=start;
 while(p+8<=end){let size=u32(b,p),header=8;const type=four(b,p+4);
  if(size===1){if(p+16>end)throw new Error("truncated_largesize");size=u64(b,p+8);header=16}
  else if(size===0)size=end-p;
  if(size<header||p+size>end)throw new Error("invalid_box_"+type);
  out.push({type,start:p,size,header,data:p+header,end:p+size});p+=size;
 }
 if(p!==end&&end-p>0)throw new Error("trailing_bytes_in_box");
 return out;
}
export function child(b:Uint8Array,box:any,type:string){return boxes(b,box.data,box.end).find((x:any)=>x.type===type)||null}
export function parseMvhd(b:Uint8Array,box:any){const v=b[box.data];if(v===1){const ts=u32(b,box.data+20),dur=u64(b,box.data+24);return {timescale:ts,duration_ticks:dur,duration_seconds:ts?dur/ts:null}}const ts=u32(b,box.data+12),dur=u32(b,box.data+16);return {timescale:ts,duration_ticks:dur,duration_seconds:ts?dur/ts:null}}
export function parseMdhd(b:Uint8Array,box:any){const v=b[box.data];if(v===1){const ts=u32(b,box.data+20),dur=u64(b,box.data+24);return {timescale:ts,duration_ticks:dur,duration_seconds:ts?dur/ts:null}}const ts=u32(b,box.data+12),dur=u32(b,box.data+16);return {timescale:ts,duration_ticks:dur,duration_seconds:ts?dur/ts:null}}
export function handler(b:Uint8Array,box:any){return four(b,box.data+8)}
export function parseTkhd(b:Uint8Array,box:any){const v=b[box.data],off=v===1?88:76;if(box.data+off+8>box.end)return {width:null,height:null};return {width:u32(b,box.data+off)/65536,height:u32(b,box.data+off+4)/65536}}
export function sampleEntry(b:Uint8Array,stsd:any){if(stsd.data+8>stsd.end)return null;const count=u32(b,stsd.data+4);if(count<1)return null;const p=stsd.data+8;if(p+8>stsd.end)return null;const size=u32(b,p),type=four(b,p+4);if(size<8||p+size>stsd.end)return null;return {type,start:p,data:p+8,end:p+size,size}}
export function codecName(t:string){if(["avc1","avc3"].includes(t))return "h264";if(["hvc1","hev1"].includes(t))return "hevc";if(t==="mp4a")return "aac";return t}
export function parseSttsFps(b:Uint8Array,stts:any,timescale:number){if(!stts||!timescale||stts.data+8>stts.end)return null;const n=u32(b,stts.data+4);let p=stts.data+8,samples=0,ticks=0;for(let i=0;i<n;i++){if(p+8>stts.end)return null;const c=u32(b,p),d=u32(b,p+4);samples+=c;ticks+=c*d;p+=8}return ticks>0?samples*timescale/ticks:null}
export function sampleBytes(b:Uint8Array,stbl:any){const z=stbl?child(b,stbl,"stsz"):null;if(!z||z.data+12>z.end)return null;const sampleSize=u32(b,z.data+4),count=u32(b,z.data+8);if(sampleSize>0)return sampleSize*count;let p=z.data+12,total=0;for(let i=0;i<count;i++){if(p+4>z.end)return null;total+=u32(b,p);p+=4}return total}
export function audioSampleRate(b:Uint8Array,e:any){if(!e||e.type!=="mp4a"||e.data+28>e.end)return null;return u32(b,e.data+24)/65536}
export function parseMp4(b:Uint8Array){
 const top=boxes(b),ftyp=top.find((x:any)=>x.type==="ftyp"),moov=top.find((x:any)=>x.type==="moov");
 if(!ftyp||!moov)throw new Error("missing_ftyp_or_moov");
 if(ftyp.data+8>ftyp.end)throw new Error("invalid_ftyp");
 const major=four(b,ftyp.data),minor=u32(b,ftyp.data+4),brands:string[]=[];for(let p=ftyp.data+8;p+4<=ftyp.end;p+=4)brands.push(four(b,p));
 const mvhd=child(b,moov,"mvhd");if(!mvhd)throw new Error("missing_mvhd");const movie=parseMvhd(b,mvhd);
 const tracks:any[]=[];
 for(const trak of boxes(b,moov.data,moov.end).filter((x:any)=>x.type==="trak")){
  const tkhd=child(b,trak,"tkhd"),mdia=child(b,trak,"mdia");if(!mdia)continue;
  const hdlr=child(b,mdia,"hdlr"),mdhd=child(b,mdia,"mdhd"),minf=child(b,mdia,"minf");if(!hdlr||!mdhd||!minf)continue;
  const kind=handler(b,hdlr),md=parseMdhd(b,mdhd),stbl=child(b,minf,"stbl"),stsd=stbl?child(b,stbl,"stsd"):null,stts=stbl?child(b,stbl,"stts"):null;
  const entry=stsd?sampleEntry(b,stsd):null,dims=tkhd?parseTkhd(b,tkhd):{width:null,height:null},sbytes=sampleBytes(b,stbl);
  tracks.push({handler:kind,sample_entry:entry?.type||null,codec:entry?codecName(entry.type):null,duration_seconds:md.duration_seconds,timescale:md.timescale,width:kind==="vide"?Math.round(dims.width||0)||null:null,height:kind==="vide"?Math.round(dims.height||0)||null:null,fps:kind==="vide"?parseSttsFps(b,stts,md.timescale):null,sample_rate_hz:kind==="soun"?audioSampleRate(b,entry):null,bitrate_bps:sbytes&&md.duration_seconds?Math.round((sbytes*8)/md.duration_seconds):null});
 }
 return {container:"mp4",major_brand:major,minor_version:minor,compatible_brands:brands,duration_seconds:movie.duration_seconds,video:tracks.find(x=>x.handler==="vide")||null,audio:tracks.find(x=>x.handler==="soun")||null,track_count:tracks.length};
}
export function normalizeProbe(p:any){return {bytes:Number(p.bytes),mime:String(p.mime||"").toLowerCase(),container:String(p.container||"").toLowerCase(),major_brand:String(p.major_brand||""),video_codec:String(p.video?.codec||"").toLowerCase(),video_sample_entry:String(p.video?.sample_entry||""),width:Number(p.video?.width||0)||null,height:Number(p.video?.height||0)||null,fps:p.video?.fps==null?null:Math.round(Number(p.video.fps)*1000)/1000,duration_seconds:p.duration_seconds==null?null:Math.round(Number(p.duration_seconds)*1000)/1000,video_bitrate_bps:p.video?.bitrate_bps==null?null:Math.round(Number(p.video.bitrate_bps)),audio_codec:p.audio?.codec?String(p.audio.codec).toLowerCase():null,audio_sample_rate_hz:p.audio?.sample_rate_hz==null?null:Math.round(Number(p.audio.sample_rate_hz)),audio_bitrate_bps:p.audio?.bitrate_bps==null?null:Math.round(Number(p.audio.bitrate_bps))}}
export function techPass(p:any){const t=normalizeProbe(p);if(t.mime!=="video/mp4")return {ok:false,reason:"HOLD_REEL_MIME_INVALID",technical:t};if(t.container!=="mp4")return {ok:false,reason:"HOLD_REEL_CONTAINER_INVALID",technical:t};if(t.bytes<1024||t.bytes>52428800)return {ok:false,reason:"HOLD_REEL_FILE_SIZE_OUTSIDE_INTERNAL_CONTRACT",technical:t};if(t.video_codec!=="h264")return {ok:false,reason:"HOLD_REEL_CODEC_INVALID",technical:t};if(t.width!==1080||t.height!==1920)return {ok:false,reason:"HOLD_REEL_DIMENSIONS_INVALID",technical:t};if(t.fps==null||t.fps<23||t.fps>60)return {ok:false,reason:"HOLD_REEL_FPS_INVALID",technical:t};if(t.duration_seconds==null||t.duration_seconds<3||t.duration_seconds>900)return {ok:false,reason:"HOLD_REEL_DURATION_INVALID",technical:t};if(t.video_bitrate_bps==null||t.video_bitrate_bps<=0||t.video_bitrate_bps>25000000)return {ok:false,reason:"HOLD_REEL_VIDEO_BITRATE_INVALID",technical:t};if(t.audio_codec!==null&&(t.audio_codec!=="aac"||t.audio_sample_rate_hz!==48000||t.audio_bitrate_bps==null||t.audio_bitrate_bps<=0||t.audio_bitrate_bps>128000))return {ok:false,reason:t.audio_codec!=="aac"?"HOLD_REEL_AUDIO_CODEC_INVALID":t.audio_sample_rate_hz!==48000?"HOLD_REEL_AUDIO_SAMPLE_RATE_INVALID":"HOLD_REEL_AUDIO_BITRATE_INVALID",technical:t};return {ok:true,reason:"REEL_TECHNICAL_CONTRACT_PASS",technical:t}}
