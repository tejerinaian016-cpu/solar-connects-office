const fs=require('fs'),assert=require('assert/strict');
const cfg=JSON.parse(fs.readFileSync('artifacts/staging-e2e-config.json')),r=JSON.parse(fs.readFileSync('artifacts/staging-render-receipt.json'));
assert.equal(cfg.url,'https://cmwervbwxyqzowntnxwe.supabase.co');
// Written only after inspecting full-size and 360px actual JPEGs. Not an automatic PASS.
const critique={asset_sha256:r.sha256,plan_sha256:r.plan_sha256,
 scores:{hook:3,clarity:5,design:4,readability:5,naturalness:4,value:3,brand:5,variety:3},
 evidence:{hook:'El título plantea una decisión, pero no ofrece un gancho específico del servicio.',clarity:'Título, cuerpo y CTA coinciden en solicitar alcance y condiciones antes de decidir.',design:'Alineación y jerarquía coherentes; queda mucho espacio vacío sin información adicional.',readability:'JPEG completo y preview de 360 píxeles legibles; ningún texto recortado.',naturalness:'Español rioplatense natural: revisá, pedí, consultá; sin promesas artificiales.',value:'Consejo genérico: no explica qué condiciones concretas debe revisar la persona.',brand:'Wordmark SOLAR CONNECTS una vez; Roboto y paleta oficial del motor verificados.',variety:'No hay corpus editorial aprobado para verificar novedad; evaluación conservadora.'},
 factuality_pass:true,scene_match:true,mobile_360_pass:true,semantic_novelty_pass:false,no_clipping:true,
 fixes:['Agregar condiciones concretas sustentadas por un claim aprobado y vinculado al plan.'],expected_gain:5};
(async()=>{
 const token=JSON.parse(fs.readFileSync('artifacts/staging-render-secret.json')).token;
 const response=await fetch(cfg.url+'/functions/v1/staging-quality-renderer',{method:'POST',headers:{apikey:cfg.key,'content-type':'application/json','x-render-token':token},body:JSON.stringify({action:'assess',asset_sha256:r.sha256,critique})});
 const evaluation=await response.json();assert.equal(response.status,200);assert.notEqual(evaluation.assessment.state,'SHADOW_PASS');assert.equal(evaluation.ready,false);
 const out={scope:'UNBOUND_DIAGNOSTIC',review_method:'assistant inspected actual 1080x1350 and 360px JPEGs',critique,evaluation};
 fs.writeFileSync('artifacts/staging-render-review.json',JSON.stringify(out,null,2));console.log(JSON.stringify(evaluation,null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
