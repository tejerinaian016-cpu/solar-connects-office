const fs=require('fs'),assert=require('assert/strict');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
const token=JSON.parse(fs.readFileSync('artifacts/staging-test-sessions.json')).sessions.find(x=>x.role==='operator').access_token;
const ws=new WebSocket(cfg.url.replace('https:','wss:')+'/realtime/v1/websocket?apikey='+encodeURIComponent(cfg.key)+'&vsn=1.0.0');
const timeout=setTimeout(()=>{console.error('Realtime timeout');ws.close();process.exitCode=1;},30000);
ws.onopen=()=>ws.send(JSON.stringify({topic:'realtime:solar-connects-observability-v3',event:'phx_join',payload:{config:{broadcast:{ack:false,self:false},presence:{key:''},postgres_changes:[],private:false},access_token:token},ref:'1'}));
ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.event==='phx_reply'&&m.ref==='1'){assert.equal(m.payload.status,'ok');console.log('SUBSCRIBED');}
if(m.event==='broadcast'&&m.payload.event==='invalidate'&&m.payload.payload.table==='sc_system_health'){
 const result={status:'PASS',project:'cmwervbwxyqzowntnxwe',transport:'Supabase Realtime WebSocket',event:m.payload};
 fs.writeFileSync('artifacts/staging-realtime-result.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));clearTimeout(timeout);ws.close();}
};
ws.onerror=()=>{clearTimeout(timeout);console.error('Realtime error');process.exitCode=1;};
