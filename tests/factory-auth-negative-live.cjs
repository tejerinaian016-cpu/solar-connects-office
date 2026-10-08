/* Only missing/invalid JWT requests. Never uses a real session or a service key. */
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
 const key=html.match(/sb_publishable_[A-Za-z0-9_-]+/)?.[0];assert(key);
 const report={target:'v5-command-boundary',tests:[],real_session_used:false};
 for(const authorization of [null,'Bearer invalid-not-a-jwt']){
  const headers={'content-type':'application/json',apikey:key};if(authorization)headers.authorization=authorization;
  const response=await fetch('https://akwqkymjrovqiijnhrqs.supabase.co/functions/v1/v5-command-boundary',{method:'POST',headers,body:JSON.stringify({requested_action:'factory.start',mode:'EXECUTE'})});
  const result=await response.json();report.tests.push({case:authorization?'invalid JWT':'missing JWT',http:response.status,response:result});assert.equal(response.status,401);
 }
 const dir=path.join(__dirname,'../artifacts');fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(path.join(dir,'factory-auth-negative-live.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1});
