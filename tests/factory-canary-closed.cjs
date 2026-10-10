const fs=require('fs'),assert=require('assert/strict');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
(async()=>{
 const r=await fetch(cfg.url+'/functions/v1/factory-canary-candidate',{method:'POST',headers:{apikey:cfg.key,Authorization:'Bearer '+cfg.key,'content-type':'application/json'},body:'{}'});
 const body=await r.json();assert.equal(r.status,410);assert.equal(body.error,'CANARY_DISABLED');
 const evidence={project:'cmwervbwxyqzowntnxwe',status:r.status,body,pass:true,observed_at:new Date().toISOString()};
 fs.writeFileSync('docs/evidence/canary-adaptation-edge-closed.json',JSON.stringify(evidence,null,2)+'\n');console.log(evidence);
})().catch(e=>{console.error(e.message);process.exitCode=1});
