const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
(async()=>{
const closures=[];
for(const name of ['factory-staging-e2e','factory-staging-fixture']){
 const r=await fetch(cfg.url+'/functions/v1/'+name,{method:'POST',headers:{apikey:cfg.key,Authorization:'Bearer '+cfg.key,'content-type':'application/json'},body:'{}'});
 assert.equal(r.status,410);closures.push({name,status:r.status,body:await r.json()});
}
const a=JSON.parse(fs.readFileSync('docs/evidence/factory-full-guardian.json')).body.evidence.artifacts[0];
const r=await fetch(a.snapshot_url),bytes=Buffer.from(await r.arrayBuffer());assert.equal(r.status,200);
assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),a.snapshot_sha256);assert.equal(bytes.length,a.bytes);
const evidence={closed:closures,snapshot_sha256:a.snapshot_sha256,snapshot_url:a.snapshot_url,bytes:bytes.length,readback:true};
fs.writeFileSync('docs/evidence/factory-full-closure.json',JSON.stringify(evidence,null,2));console.log(JSON.stringify(evidence));
})().catch(e=>{console.error(e.message);process.exitCode=1});
