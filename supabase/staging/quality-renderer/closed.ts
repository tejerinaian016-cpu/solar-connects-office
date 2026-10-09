// Deployed at closure as staging-quality-renderer v2, verify_jwt=true.
// No database, storage or network operations.
Deno.serve(() => Response.json({error:'DIAGNOSTIC_CLOSED',ready:false},{status:410}));
