// STAGING-only temporary RPC. Random credential stays ignored. No retained job.
const fs=require('fs'),assert=require('assert/strict');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
const secret=JSON.parse(fs.readFileSync('artifacts/canary-probe-secret.json')).token;
async function call(mode){
 const r=await fetch(cfg.url+'/rest/v1/rpc/sc_canary_lock_probe',{method:'POST',headers:{apikey:cfg.key,Authorization:'Bearer '+cfg.key,'content-type':'application/json'},body:JSON.stringify({p_key:secret,p_mode:mode})});
 const value=await r.json();assert.equal(r.status,200,JSON.stringify(value));return value;
}
(async()=>{
 const holder=call('holder');await new Promise(r=>setTimeout(r,150));const producer=call('producer');
 const [a,b]=await Promise.all([holder,producer]);
 assert.notEqual(a.pid,b.pid);assert(b.wait_seconds>0.5,JSON.stringify({a,b}));
 assert(Date.parse(b.acquired)>=Date.parse(a.finished));
 fs.writeFileSync('docs/evidence/canary-adaptation-concurrency.json',JSON.stringify({holder:a,producer:b,pass:true},null,2));
 console.log(JSON.stringify({pass:true,producer_wait_seconds:b.wait_seconds,separate_backends:true}));
})().catch(e=>{console.error(e.message);process.exitCode=1});
