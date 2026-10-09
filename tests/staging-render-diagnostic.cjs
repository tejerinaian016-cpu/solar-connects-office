const fs=require('fs'),assert=require('assert/strict'),crypto=require('crypto');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
const token=JSON.parse(fs.readFileSync('artifacts/staging-render-secret.json')).token;
async function call(body,auth=token){const r=await fetch(cfg.url+'/functions/v1/staging-quality-renderer',{method:'POST',headers:{apikey:cfg.key,'content-type':'application/json','x-render-token':auth},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};}
(async()=>{
 assert.equal((await call({action:'render'},'wrong')).status,401);
 assert.equal((await call({action:'render',job_id:'85beaf87-34d1-4684-b5ed-519c955e6637'})).status,422);
 const seed=await call({action:'seed'});assert.equal(seed.status,200,JSON.stringify(seed));
 fs.writeFileSync('artifacts/staging-font-receipts.json',JSON.stringify(seed.body,null,2));
 const preflight=await call({action:'preflight'});assert.equal(preflight.body.preflight.ok,false);fs.writeFileSync('artifacts/staging-render-blocker.json',JSON.stringify(preflight.body,null,2));
 const rendered=await call({action:'render'});assert.equal(rendered.status,200,JSON.stringify(rendered));
 const {base64,...receipt}=rendered.body;assert.equal(receipt.scope,'UNBOUND_DIAGNOSTIC');assert.equal(receipt.width,1080);assert.equal(receipt.height,1350);
 const asset=await fetch(receipt.url);assert.equal(asset.status,200);const bytes=Buffer.from(await asset.arrayBuffer());assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),receipt.sha256);assert.equal(bytes.readUInt16BE(0),0xffd8);
 let dimensions;for(let i=2;i<bytes.length;){assert.equal(bytes[i++],255);while(bytes[i]===255)i++;const marker=bytes[i++];if(marker===0xda||marker===0xd9)break;const length=bytes.readUInt16BE(i);if([0xc0,0xc1,0xc2].includes(marker)){dimensions={height:bytes.readUInt16BE(i+3),width:bytes.readUInt16BE(i+5)};break;}i+=length;}
 assert.deepEqual(dimensions,{height:1350,width:1080});assert.match(asset.headers.get('content-type'),/image\/jpeg/);
 fs.writeFileSync('artifacts/staging-render-full.jpg',bytes);fs.writeFileSync('artifacts/staging-render-mobile.jpg',Buffer.from(base64,'base64'));
 const retry=await call({action:'render'});assert.equal(retry.status,200,JSON.stringify(retry));assert.equal(retry.body.sha256,receipt.sha256);assert.equal(retry.body.path,receipt.path);
 const bad=await call({action:'assess',asset_sha256:'a'.repeat(64),critique:{}});assert.equal(bad.status,422);
 const report={...receipt,bytes:bytes.length,decoded_jpeg_dimensions:dimensions,readback_sha256:receipt.sha256,retry_same_path:true,unauthorized_denied:true,job_override_denied:true,wrong_hash_denied:true,not_a_job_artifact:true};
 fs.writeFileSync('artifacts/staging-render-receipt.json',JSON.stringify(report,null,2));console.log(JSON.stringify({status:'PASS',url:receipt.url,sha256:receipt.sha256,bytes:bytes.length,original_job_preflight:preflight.body.preflight,scope:receipt.scope},null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
