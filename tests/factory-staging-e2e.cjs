// STAGING ONLY. Secrets/sessions stay in ignored artifacts; no production endpoint.
const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
const phase=process.argv[2],report=[];
async function request(path,body,token,extra={}){
 const r=await fetch(cfg.url+path,{method:'POST',headers:{apikey:cfg.key,'content-type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),...extra},body:JSON.stringify(body)});
 return {http:r.status,body:await r.json().catch(()=>({}))};
}
(async()=>{
 if(phase==='users'){
 const secret=JSON.parse(fs.readFileSync('artifacts/staging-bootstrap-secret.json')).token;
 const r=await request('/functions/v1/factory-staging-fixture',{},null,{'x-fixture-token':secret});
 assert.equal(r.http,200,JSON.stringify(r.body));assert.equal(r.body.sessions.length,2);
 fs.writeFileSync('artifacts/staging-test-sessions.json',JSON.stringify(r.body));console.log('Two synthetic Auth users signed in; no email sent.');return;
 }
 const sessions=JSON.parse(fs.readFileSync('artifacts/staging-test-sessions.json')).sessions;
 const operator=sessions.find(x=>x.role==='operator').access_token,viewer=sessions.find(x=>x.role==='viewer').access_token;
 let command;
 if(fs.existsSync('artifacts/staging-test-command.json'))command=JSON.parse(fs.readFileSync('artifacts/staging-test-command.json'));
 else{
 command={command_id:crypto.randomUUID(),idempotency_key:'staging_e2e_'+crypto.randomUUID().replaceAll('-',''),requested_action:'factory.start',mode:'EXECUTE',target:{agent:'FACTORY',job_id:null},payload:{creative_run_id:cfg.run,compiled_plan_sha256:cfg.hash,plan_hash_algorithm:'sha256-pg-jsonb-v1',max_jobs:1,stop_at:'READY',additional_paid_cost_usd:0},confirmation:{confirmed:true,intent:'REAL_EXECUTION'}};
 command.confirmation.token=`REAL:${command.command_id}:${command.idempotency_key}:factory.start:${cfg.run}:${cfg.hash}`;
 fs.writeFileSync('artifacts/staging-test-command.json',JSON.stringify(command));
 }
 const body={phase:'EXECUTE',command,slot:1,quality:{pages:[{argument_key:'test',decision_key:'test',angle_key:'test',hook_family:'test',layout:'test'}]}};
 const call=(b=body,t=operator)=>request('/functions/v1/factory-staging-boundary',b,t);
 if(phase==='negative'){
 assert.equal((await call(body,null)).http,401);report.push('missing JWT:401');
 assert.equal((await call(body,'invalid')).http,401);report.push('invalid JWT:401');
 assert.equal((await call(body,viewer)).http,403);report.push('viewer:403');
 const bad=structuredClone(body);bad.command.confirmation.token='wrong';const rejected=await call(bad);assert.equal(rejected.http,409);report.push('confirmation rejected');
 const frozen=await call();assert.equal(frozen.http,409,JSON.stringify(frozen));assert.match(frozen.body.error,/FACTORY_OFF/);report.push('gate OFF rejected');
 const direct=await request('/rest/v1/rpc/sc_factory_staging_v1',{p_request:body},viewer);assert.equal(direct.http>=400,true);report.push('direct RPC viewer denied');
 }else if(['freeze','rollback','revoked','grants'].includes(phase)){
 if(phase==='revoked'){
 const r=await call({...body,phase:'RECONCILE'});assert(r.http===401||r.http===409,JSON.stringify(r));if(r.http===409)assert.match(r.body.error,/SESSION_REVOKED/);report.push('expired real Auth session denied');
 }else if(phase==='grants'){
 for(const token of [null,viewer,operator]){
 const insert=await request('/rest/v1/sc_content_jobs',{content_plan:{},qa:{}},token);assert(insert.http>=400,JSON.stringify(insert));
 const legacy=await request('/rest/v1/rpc/sc_creative_materialize_job_v1',{p_run_id:cfg.run,p_mode:'SHADOW'},token);assert(legacy.http>=400,JSON.stringify(legacy));
 }report.push('anon/viewer/operator cannot insert jobs or invoke privileged legacy producer');
 }else{
 const guard=JSON.parse(fs.readFileSync('artifacts/staging-guard-config.json'));const b=structuredClone(body);
 b.command.command_id=crypto.randomUUID();b.command.idempotency_key='staging_guard_'+crypto.randomUUID().replaceAll('-','');b.command.payload.creative_run_id=guard.run;b.command.payload.compiled_plan_sha256=guard.hash;
 b.command.confirmation.token=`REAL:${b.command.command_id}:${b.command.idempotency_key}:factory.start:${guard.run}:${guard.hash}`;
 if(phase==='rollback')b.quality={pages:[]};
 const r=await call(b);assert.equal(r.http,409,JSON.stringify(r));assert.match(r.body.error,phase==='freeze'?/QUALITY_V2_FROZEN_OR_UNKNOWN/:/QUALITY_MATERIALIZATION_REJECTED/);
 report.push(phase==='freeze'?'Quality freeze rejects valid JWT even when staging Factory gate is ON':'invalid Quality input rejected inside claim/permit transaction');
 }
 }else if(phase==='execute'){
 const results=await Promise.all(Array.from({length:8},()=>call()));
 fs.writeFileSync('artifacts/staging-execute-raw.json',JSON.stringify(results,null,2));
 const jobs=results.filter(x=>x.body.job_id).map(x=>x.body.job_id);
 assert(jobs.length>0,JSON.stringify(results));assert.equal(new Set(jobs).size,1);
 assert(results.every(x=>x.http===200),JSON.stringify(results));
 report.push('8 concurrent authenticated Edge requests: one job ID');
 const replay=await call();assert.equal(replay.body.state,'DUPLICATE');report.push('replay:duplicate');
 const conflict=structuredClone(body);conflict.command.payload.compiled_plan_sha256='b'.repeat(64);conflict.command.confirmation.token=`REAL:${command.command_id}:${command.idempotency_key}:factory.start:${cfg.run}:${'b'.repeat(64)}`;
 assert.equal((await call(conflict)).http,409);report.push('hash conflict denied');
 const reconciled=await call({...body,phase:'RECONCILE'});assert.equal(reconciled.body.job_id,jobs[0]);assert.equal(reconciled.body.ready,false);report.push('reconciliation returns canonical draft, not READY');
 const closed=await call({...body,phase:'CLOSE'});assert.equal(closed.body.state,'CLOSED');report.push('permit closed');
 }else throw Error('unknown phase');
 const result={phase,passed:report,project:'cmwervbwxyqzowntnxwe',real_auth:true};
 fs.writeFileSync(`artifacts/staging-e2e-${phase}.json`,JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
