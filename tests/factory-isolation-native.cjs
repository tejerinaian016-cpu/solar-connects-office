// Launch ONLY a disposable loopback cluster; always stop it, including failures.
const {execFileSync,spawnSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path'),net=require('node:net');
(async()=>{
 const root=path.resolve('artifacts/factory-db-test');
 const bin=path.join(root,'node_modules/@embedded-postgres/windows-x64/native/bin');
 const data=fs.mkdtempSync(path.join(root,'cluster-'));
 const server=net.createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const port=server.address().port;await new Promise(r=>server.close(r));
 const run=(name,args)=>execFileSync(path.join(bin,name+'.exe'),args,{windowsHide:true,stdio:'ignore',timeout:60000});
 let started=false;
 try{
 run('initdb',['-D',data,'-U','factory_test','--auth=trust','--encoding=UTF8','--locale=C']);
 fs.appendFileSync(path.join(data,'postgresql.conf'),`\nlisten_addresses='127.0.0.1'\nport=${port}\nmax_connections=48\n`);
 run('pg_ctl',['-D',data,'-l',path.join(data,'server.log'),'-w','start']);started=true;
 const test=process.argv.includes('--real-contracts')?'tests/factory-real-contracts.mjs':'tests/factory-isolation-db.mjs';
 const result=spawnSync(process.execPath,[test],{windowsHide:true,stdio:'inherit',env:{...process.env,FACTORY_TEST_NATIVE:'1',FACTORY_TEST_PORT:String(port)},timeout:90000});
 process.exitCode=result.status??1;
 }finally{if(started||fs.existsSync(path.join(data,'postmaster.pid')))run('pg_ctl',['-D',data,'-m','fast','-w','stop']);}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
