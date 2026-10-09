const fs=require('fs'),assert=require('assert/strict');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
(async()=>{
 const r=await fetch(cfg.url+'/functions/v1/staging-quality-renderer',{method:'POST',headers:{apikey:cfg.key,Authorization:'Bearer '+cfg.key,'content-type':'application/json'},body:JSON.stringify({action:'render'})});
 const body=await r.json();assert.equal(r.status,410);assert.equal(body.error,'DIAGNOSTIC_CLOSED');
 const report={status:r.status,body,closed:true};
 fs.writeFileSync('docs/evidence/staging-render-closure.json',JSON.stringify(report,null,2));
 console.log('PASS diagnostic endpoint closed (410)');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
