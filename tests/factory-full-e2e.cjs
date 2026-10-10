const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
async function http(slug,body,token,extra={}){
 const r=await fetch(cfg.url+'/functions/v1/'+slug,{method:'POST',headers:{apikey:cfg.key,'content-type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),...extra},body:JSON.stringify(body)});
 const text=await r.text();let value;try{value=JSON.parse(text)}catch{value={raw:text}}return {status:r.status,body:value};
}
(async()=>{
const phase=process.argv[2];
if(phase==='users'){
 const secret=JSON.parse(fs.readFileSync('artifacts/e2e-auth-secret.json')).token;
 const r=await http('factory-staging-fixture',{},null,{'x-fixture-token':secret});assert.equal(r.status,200);
 fs.writeFileSync('artifacts/e2e-sessions.json',JSON.stringify(r.body));
 console.log(JSON.stringify(r.body.sessions.map(x=>({role:x.role,user_id:x.user_id}))));return;
}
const sessions=JSON.parse(fs.readFileSync('artifacts/e2e-sessions.json')).sessions;
const token=sessions.find(x=>x.role==='operator').access_token;
const input=JSON.parse(fs.readFileSync('artifacts/e2e-input.json'));
const lease=fs.existsSync('artifacts/e2e-lease.json')?JSON.parse(fs.readFileSync('artifacts/e2e-lease.json')):{};
const base={command_id:input.command.command_id,claim_token:lease.claim_token,lease_version:lease.lease_version};
const call=b=>http('factory-staging-e2e',{...base,...b},token);
if(phase==='start'){
 const results=await Promise.all(Array.from({length:4},()=>call({action:'START',request:input})));
 for(const r of results)assert.equal(r.status,200,JSON.stringify(r));
 assert.equal(new Set(results.map(r=>r.body.job_id)).size,1);
 fs.writeFileSync('artifacts/e2e-lease.json',JSON.stringify(results[0].body));
 fs.writeFileSync('docs/evidence/factory-full-start.json',JSON.stringify({concurrent_requests:4,command_id:base.command_id,job_id:results[0].body.job_id,state:results[0].body.state},null,2));console.log('PASS 4 starts -> same job');return;
}
if(phase==='negative'){
 const cases=[];
 const no=await http('factory-staging-e2e',{...base,action:'RECONCILE'},null);assert.equal(no.status,401);cases.push('missing JWT denied');
 const bad=await http('factory-staging-e2e',{...base,action:'RECONCILE'},'bad');assert.equal(bad.status,401);cases.push('invalid JWT denied');
 const viewer=await http('factory-staging-e2e',{...base,action:'RECONCILE'},sessions.find(x=>x.role==='viewer').access_token);assert.equal(viewer.status,403);cases.push('viewer denied');
 for(const patch of [{claim_token:crypto.randomUUID()},{lease_version:base.lease_version+1}]){
 const r=await call({...patch,action:'FINISH'});assert.equal(r.status,409);assert.match(r.body.error,/FENCE_OR_LEASE/);
 }cases.push('wrong token and version denied');
 const missing=await call({action:'FINISH'});assert.equal(missing.status,409);assert.match(missing.body.error,/FRESH_GUARDIAN/);cases.push('premature completion denied');
 fs.writeFileSync('docs/evidence/factory-full-negative.json',JSON.stringify(cases,null,2));console.log('PASS new boundary negatives');return;
}
if(phase==='expect-off'||phase==='expect-expired'){
 const r=await call({action:'STEP',operation:'render'});assert.equal(r.status,409);
 assert.match(r.body.error,phase==='expect-off'?/EMERGENCY_OFF/:/FENCE_OR_LEASE/);
 fs.writeFileSync('docs/evidence/factory-full-'+phase+'.json',JSON.stringify(r,null,2));console.log('PASS '+phase);return;
}
if(['renew','recover','reconcile','finish'].includes(phase)){
 if(phase==='recover')fs.writeFileSync('artifacts/e2e-old-lease.json',JSON.stringify(lease));
 const r=await call({action:phase.toUpperCase()});assert.equal(r.status,200,JSON.stringify(r));
 fs.writeFileSync('artifacts/e2e-lease.json',JSON.stringify(r.body));
 const {claim_token,step_token,...safe}=r.body;
 fs.writeFileSync('docs/evidence/factory-full-'+phase+'.json',JSON.stringify(safe,null,2));console.log(JSON.stringify(safe));return;
}
if(phase==='stale'){
 const old=JSON.parse(fs.readFileSync('artifacts/e2e-old-lease.json'));
 const r=await call({action:'FINISH',claim_token:old.claim_token,lease_version:old.lease_version});
 assert.equal(r.status,409);assert.match(r.body.error,/FENCE_OR_LEASE/);
 fs.writeFileSync('docs/evidence/factory-full-stale.json',JSON.stringify({rejected:true,old_version:old.lease_version,current_version:base.lease_version},null,2));console.log('PASS stale owner fenced');return;
}
if(phase==='render'){
 for(const operation of ['preflight','render']){
 const r=await call({action:'STEP',operation});assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.body.ok,true,JSON.stringify(r));
 if(operation==='render'){
 const {base64,...render}=r.body.render;
 const rb=await fetch(render.url),bytes=Buffer.from(await rb.arrayBuffer());assert.equal(rb.status,200);
 assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),render.sha256);
 fs.writeFileSync('docs/evidence/factory-full-image.jpg',bytes);
 if(base64)fs.writeFileSync('docs/evidence/factory-full-mobile.jpg',Buffer.from(base64,'base64'));
 fs.writeFileSync('docs/evidence/factory-full-render.json',JSON.stringify({...r.body,render},null,2));
 }else fs.writeFileSync('docs/evidence/factory-full-preflight.json',JSON.stringify(r.body,null,2));
 }console.log('PASS bound render');return;
}
if(phase==='guardian'){
 const r=await call({action:'STEP',operation:'guardian',critiques:[JSON.parse(fs.readFileSync('tests/fixtures/factory-full-critique.json'))]});
 fs.writeFileSync('docs/evidence/factory-full-guardian.json',JSON.stringify(r,null,2));
 assert.equal(r.body.guardian_state,'PASS_PENDING_DURABLE_COMMIT',JSON.stringify(r));console.log('PASS Guardian pending fenced completion');return;
}
if(phase==='completion-race'){
 const results=await Promise.all(Array.from({length:3},()=>call({action:'FINISH'})));
 for(const r of results){assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.body.state,'SUCCEEDED');assert.equal(r.body.job_id,lease.job_id);}
 fs.writeFileSync('docs/evidence/factory-full-completion-race.json',JSON.stringify({replays:3,state:'SUCCEEDED',same_job:true},null,2));console.log('PASS concurrent completion replays');return;
}
throw Error('phase');
})().catch(e=>{console.error(e.message);process.exitCode=1});
