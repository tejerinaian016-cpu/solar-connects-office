# Live staging integration — 2026-10-09

Target: `cmwervbwxyqzowntnxwe` (PostgreSQL 17.11). Production was read-only. No main merge, visual Office change, paid integration, renderer invocation or publication.

## Implemented and deployed ONLY to staging

1. `factory_staging_contracts`: bootstrap generated from saved schema/function/ACL export, with no production rows or credentials. Existing Supabase Auth and Realtime services are real, not placeholders.
2. `factory_staging_isolation`: reviewed candidate and private one-use permits.
3. `factory_staging_authenticated_bridge`: narrow authenticated RPC, verified current app_metadata/session, existing V5 claim/audit, atomic authorize/materialize transaction, read-only reconciliation and permit closure. No claims are reclaimed automatically after ambiguity.
4. `factory-staging-boundary` Edge v1: staging-host-only adapter forwarding the caller JWT to PostgREST after `auth.getUser`. Gateway JWT verification is disabled deliberately because the function itself verifies the real JWT with Auth; missing/invalid tokens receive 401. It never substitutes service-role identity for the caller.
5. Temporary `factory-staging-fixture` created two synthetic confirmed accounts without sending email, guarded by a random 256-bit credential. It was immediately redeployed as a disabled endpoint (v2, JWT required, always 410). Fixture sessions were expired at completion. No passwords/service keys/tokens are committed.

This staging-specific Edge endpoint reuses V5 ledger and the existing Quality materializer. It does not replace/deploy the production V5 boundary. Its future integration into the production command dispatch remains a separate reviewed change.

## Actual remote test results

All executed assertions passed:

- Real Auth sign-in/JWT, missing/invalid JWT 401, insufficient role 403, invalid confirmation denied, direct RPC viewer denied.
- Anonymous/viewer/operator direct jobs INSERT and privileged legacy RPC calls denied.
- FACTORY OFF denies execution. Independently, frozen Quality denies execution while ONLY staging FACTORY is temporarily ON.
- Eight concurrent authenticated Edge requests produce **one** job ID; replay returns DUPLICATE. Changed hash is rejected.
- Canonical reconciliation reports the draft and `ready:false`; CLOSE revokes its permit. CLOSED is permit closure, not successful completion of a READY command. Ledger remains EXECUTING pending the unimplemented renderer/Guardian continuation.
- Invalid Quality input rolls back the new claim, audit and authorization; final count remains one command/permit/audit.
- Existing V1 SHADOW and Quality V2 SHADOW functions run on staging with the real schema, triggers and privileges. Their deliberate transaction rollbacks leave no extra job; late run annotation succeeds.
- Actual Supabase Realtime WebSocket receives the existing trigger's `invalidate` broadcast. This proves transport/trigger delivery, not Office's connection to staging.
- Expired real Auth session cannot reconcile/execute.

The prior 33 SQL/18 JS tests are reused for ownership fencing, lease timing and additional races; they are **not** relabelled as remote E2E tests. Export replay evidence also remains separate. Test inputs, comparison PASS and Quality slot authorization used during staging positive tests were explicitly synthetic, never production evidence.

## Canonical retained evidence

Synthetic job: `85beaf87-34d1-4684-b5ed-519c955e6637`.
Command: `aea519fc-8b80-4880-b764-6af753623a22`.
Run: `297cb9f7-6dcf-478c-bb79-902b4feaf801`.
Status: `QUALITY_V2_SHADOW_RENDERING`, `production_candidate:false`, `release_gate:HOLD`, `publish_blocked:true`, `do_not_publish:true`, Quality phase `PREFLIGHT_PENDING`. There is no rendered asset or Guardian approval.

At closure: staging has one synthetic job, one command, one consumed/revoked permit and zero posts. Four gates OFF; Quality `STAGE1_FROZEN_OBSERVATION`, all four format kill switches true, first slot `CONFIRMED_FROZEN`. Synthetic comparison/slot enablement was removed. See `docs/evidence/staging-live-state.json` and the separate `staging-e2e-*.json` reports. Production's final read-only snapshot is separate and unchanged.

Security advisor: no errors; deny-by-default RLS reports are expected. The [authenticated SECURITY DEFINER warning](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) corresponds to the deliberately narrow RPC with internal identity/role/session checks. [Leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) is disabled on the lab; only randomly generated synthetic account passwords were used, with sessions now expired. No paid Auth setting was enabled.

## Decision and next minimum step

**Auth → Edge → PostgREST → ledger → isolated Quality materialization: PASS in staging. Full Factory REAL → Renderer → Guardian → READY: NO-GO, not tested yet.**

Next, port the existing renderer/Guardian contracts and required storage/approved scene assets to this same staging project using synthetic or approved nonpersonal assets. Resolve the actual Quality V2 draft-to-renderer/promotion contract; do not send a SHADOW draft directly to the premium renderer or synthesize READY. Then run a new staging canary through rendering, inspect real generated files/hashes/branding/semantics, and require canonical Guardian evidence and READY with publishing blocked. No paid calls and no production connections. Only after that passes should production deployment/unfreeze be considered under separate explicit authorization.

Recovery: all changes remain on `feat/factory-real-controlled`; the previous commit is `ee9edcd869d09e5661812e3402d5208d40ccebd8`. Reverting Git alone does not undo the three staging migrations. Safe operational closure is already applied: gates OFF, Quality frozen, permit closed, test sessions expired, fixture disabled. No production rollback is needed.
