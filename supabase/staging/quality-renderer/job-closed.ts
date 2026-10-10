// Actual closure deployed as staging-quality-job v3 with verify_jwt=true.
Deno.serve(() => Response.json({error:'STAGING_JOB_WORKER_CLOSED'},{status:410}));
