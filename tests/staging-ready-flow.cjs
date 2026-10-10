const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
const token=JSON.parse(fs.readFileSync('artifacts/staging-render-secret.json')).token;
const job_id='eb5f786a-61b7-4e7c-b8af-65c7e5039d2e';
async function call(operation,extra={}) {
 const r=await fetch(cfg.url+'/functions/v1/staging-quality-job',{method:'POST',headers:{apikey:cfg.key,'content-type':'application/json','x-render-token':token},body:JSON.stringify({mode:'SHADOW',operation,job_id,...extra})});
 return {status:r.status,body:await r.json()};
}
(async()=>{
 const mode=process.argv[2]||'render';
 if(mode==='render'){
  const pre=await call('preflight');assert.equal(pre.body.ok,true,JSON.stringify(pre));
  fs.writeFileSync('docs/evidence/staging-ready-preflight.json',JSON.stringify(pre.body,null,2));
  const r=await call('render');assert.equal(r.body.ok,true,JSON.stringify(r));
  const {base64,...render}=r.body.render;
  const resp=await fetch(render.url),bytes=Buffer.from(await resp.arrayBuffer());
  assert.equal(resp.status,200);assert.match(resp.headers.get('content-type'),/image\/jpeg/);
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),render.sha256);
  fs.writeFileSync('artifacts/staging-ready-full.jpg',bytes);
  if(base64)fs.writeFileSync('docs/evidence/staging-ready-mobile.jpg',Buffer.from(base64,'base64'));
  fs.writeFileSync('docs/evidence/staging-ready-render.json',JSON.stringify({...r.body,render,readback_bytes:bytes.length},null,2));
  console.log(JSON.stringify({job_id,hash:render.sha256,floors:r.body.floors}));
 }else if(mode==='negative'){
  const before=await call('guardian',{critiques:[]});assert.equal(before.status,422);
  assert.equal((await call('publisher_dry_run')).status,422);
  assert.equal((await call('render',{job_id:'85beaf87-34d1-4684-b5ed-519c955e6637'})).status,422);
  const retry=await call('render');assert.equal(retry.body.reused,true,JSON.stringify(retry));
  const saved=JSON.parse(fs.readFileSync('docs/evidence/staging-ready-render.json'));
  assert.equal(retry.body.render.sha256,saved.render.sha256);
  fs.writeFileSync('docs/evidence/staging-ready-worker-tests.json',JSON.stringify({missing_critic_denied:true,publisher_operation_denied:true,other_job_denied:true,render_retry_same_hash:true},null,2));
  console.log('PASS worker rejection and retry tests');
 }else if(mode==='guardian'){
  const critique=JSON.parse(fs.readFileSync('tests/fixtures/staging-ready-critique.json'));
  const r=await call('guardian',{critiques:[critique]});
  fs.writeFileSync('docs/evidence/staging-ready-guardian.json',JSON.stringify(r,null,2));
  assert.equal(r.body.guardian_state,'PASS_PENDING_DURABLE_COMMIT',JSON.stringify(r));
  console.log('PASS original worker Guardian: pending durable SQL commit');
 }
})().catch(e=>{console.error(e.message);process.exitCode=1;});
