const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert/strict');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const endpoints=[];
 for(const slug of ['staging-quality-job','staging-quality-renderer']){
  const r=await fetch(cfg.url+'/functions/v1/'+slug,{method:'POST',headers:{apikey:cfg.key,Authorization:'Bearer '+cfg.key,'content-type':'application/json'},body:'{}'});
  const body=await r.json();assert.equal(r.status,410);endpoints.push({slug,status:r.status,body});
 }
 const prior=JSON.parse(fs.readFileSync('docs/evidence/staging-ready-render.json')),objects=[];
 for(const name of [prior.render.path,'quality-v2-shadow/snapshots/eb5f786a-61b7-4e7c-b8af-65c7e5039d2e/'+prior.render.sha256+'.jpg']){
  const r=await fetch(cfg.url+'/storage/v1/object/public/instagram-media/'+name);assert.equal(r.status,200);
  const b=Buffer.from(await r.arrayBuffer());assert.equal(hash(b),prior.render.sha256);objects.push({name,sha256:hash(b),bytes:b.length,readback:true});
 }
 const report={observed_at:new Date().toISOString(),project:'cmwervbwxyqzowntnxwe',endpoints,objects,existing_passes_reused:true,new_render:false,publish:false};
 fs.writeFileSync('docs/evidence/staging-ready-closure.json',JSON.stringify(report,null,2));
 const fonts='artifacts/quality-fonts';fs.mkdirSync(fonts,{recursive:true});
 for(const name of ['Roboto-Regular.ttf','Roboto-Bold.ttf','LICENSE']){
  const r=await fetch(cfg.url+'/storage/v1/object/public/solar-connects-assets/fonts/'+name);assert.equal(r.status,200);
  const b=Buffer.from(await r.arrayBuffer());if(name==='Roboto-Regular.ttf')assert.equal(hash(b),'56a45233d29f11b4dfb86d248e921939d115778f87325e7ae8cc108383d6664d');
  fs.writeFileSync(path.join(fonts,name),b);
 }
 const c=await fetch('https://supabase.com/changelog.md');const txt=await c.text();fs.writeFileSync('artifacts/supabase-changelog.md',txt);
 console.log(JSON.stringify({closure:report,font_receipts:true,changelog_status:c.status}));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
