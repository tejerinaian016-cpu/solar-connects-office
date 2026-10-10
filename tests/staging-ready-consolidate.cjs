const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
(async()=>{
 const r=await fetch(cfg.url+'/functions/v1/staging-quality-job',{method:'POST',headers:{apikey:cfg.key,Authorization:'Bearer '+cfg.key,'content-type':'application/json'},body:'{}'});
 assert.equal(r.status,410);assert.equal((await r.json()).error,'STAGING_JOB_WORKER_CLOSED');
 const evidence=JSON.parse(fs.readFileSync('docs/evidence/staging-ready-guardian.json'));
 const a=evidence.body.evidence.artifacts[0];
 const image=await fetch(a.snapshot_url);assert.equal(image.status,200);
 const bytes=Buffer.from(await image.arrayBuffer());
 assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),a.snapshot_sha256);
 assert.equal(bytes.length,a.bytes);
 fs.writeFileSync('docs/evidence/staging-ready-full.jpg',bytes);
 const report={observed_at:new Date().toISOString(),worker_closed_410:true,snapshot_sha256:a.snapshot_sha256,bytes:bytes.length,snapshot_url:a.snapshot_url};
 fs.writeFileSync('docs/evidence/staging-ready-consolidated.json',JSON.stringify(report,null,2));
 console.log(JSON.stringify(report));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
