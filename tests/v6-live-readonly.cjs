const fs=require('node:fs'),path=require('node:path');
const {chromium}=require(path.resolve(path.dirname(process.execPath),'../node_modules/playwright'));
(async()=>{
 const executablePath=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',chromium.executablePath()].find(fs.existsSync);
 const browser=await chromium.launch({executablePath,headless:true});
 const context=await browser.newContext({viewport:{width:1440,height:1080}});
 const externalMutations=[],errors=[],responses=[];
 await context.route('**/*',route=>{const r=route.request();if(!['GET','HEAD','OPTIONS'].includes(r.method())){externalMutations.push({url:r.url(),method:r.method()});return route.abort()}return route.continue()});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.url().includes('supabase.co/functions'))responses.push({url:r.url(),status:r.status()})});
 const target=process.argv[2]||'http://127.0.0.1:4174/';
 const label=process.argv[3]||'live';
 try{
 await page.goto(target,{waitUntil:'domcontentloaded',timeout:45000});
 await page.waitForFunction(()=>window.__V6_OFFICE__&&Object.keys(__V6_OFFICE__.snapshot()).length===10,{},{timeout:45000});
 await page.waitForTimeout(2500);
 const diagnostics=await page.evaluate(()=>({v6:__V6_OFFICE__.version,agents:__V6_OFFICE__.snapshot(),realtime:__V3_DIAGNOSTICS__()?.status,jobFlow:{status:__V4_DIAGNOSTICS__()?.provider.status,jobs:__V4_DIAGNOSTICS__()?.provider.jobs.length,freshness:__V4_DIAGNOSTICS__()?.provider.freshness},gates:{local_general_execution_policy:__V5_AUTH_READY__.general_execution_enabled,canonical:Object.fromEntries([...document.querySelectorAll('#v6-safety output[data-gate]')].map(el=>[el.dataset.gate,el.dataset.state]))},horizontalOverflow:document.documentElement.scrollWidth>innerWidth,roomCount:document.querySelectorAll('[data-v6-room]').length}));
 fs.mkdirSync(path.resolve(__dirname,'../artifacts'),{recursive:true});
 await page.screenshot({path:path.resolve(__dirname,`../artifacts/v6-${label}-desktop.png`),fullPage:true});
 await page.setViewportSize({width:390,height:844});
 await page.screenshot({path:path.resolve(__dirname,`../artifacts/v6-${label}-mobile.png`),fullPage:true});
 const report={target,checked_at:new Date().toISOString(),...diagnostics,externalMutations,errors,responses};
 fs.writeFileSync(path.resolve(__dirname,`../artifacts/v6-${label}-read.json`),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 if(errors.length||externalMutations.length||diagnostics.roomCount!==10||diagnostics.horizontalOverflow)process.exitCode=1;
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
