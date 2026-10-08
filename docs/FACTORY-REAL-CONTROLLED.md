# Factory REAL CONTROLLED — blocked before production

## Recovery and scope

- Office baseline: `16e73d6ba5d23c1ad802d18ebb53f088571699c4`.
- Recovery tag: `recovery/v6.1-before-factory`.
- Work branch: `feat/factory-real-controlled`.
- Edge source recovered from LIVE `v5-command-boundary`, version 6, ACTIVE, verify_jwt true. Unmodified backup: `supabase/recovery/v5-command-boundary-v6/`.
- `supabase/recovery/factory-contracts.sql` is a read-only source snapshot, NOT a migration.

## Exact blockers observed LIVE, 2026-10-08

1. `sc_security_operation_gate_v1(text)` only reads a global boolean from `sc_agent_config.security_control_plane_v1.kill_switches`. It takes no command, creative run, hash, claim token or lease. FACTORY, PUBLISHER, META_DIRECT and EXTERNAL_WRITE all returned `allowed:false`.
2. `sc_creative_materialize_job_v1(uuid,text)` and `sc_quality_factory_production_v2(uuid,jsonb,integer,boolean)` consult that global FACTORY gate. Neither fences production authorization against a V5 command/claim/lease. V1's existing-job lookup is not a cross-entrypoint atomic uniqueness guard. V2 has its own run lock but does not bind that lock to the V5 command lease. Opening the global boolean for an asynchronous pipeline would not guarantee the authorized one-job scope.
3. Quality V2's production flags are `STAGE1_FROZEN_OBSERVATION`, with all four format kill switches true; the first slot is `CONFIRMED_FROZEN`. The hook can return V1 when rollout is disabled; that is not permission to bypass the frozen V2 controls.
4. The latest creative run `84420d0a-1128-4fba-97f7-a21b8e606942` is APPROVED and already materialized. Other recent APPROVED rows examined had no RADAR stage evidence. None was selected or reused. No new run was fabricated merely to obtain a passing state.

Per the user's explicit global-gate restriction, the REAL operation stopped before any claim, gate change, job creation, renderer invocation or approval. FACTORY remained OFF throughout; no restore mutation was necessary.

## Implemented locally; NOT deployed or execution-ready

`factory-controlled.mjs` implements fail-closed, read-only preparation inside a candidate copy of the existing V5 boundary, after the original `auth.getUser(jwt)` verification. It requires verified `app_metadata.command_center` and `v5_operator`, strict request fields, one job, READY stop and zero added paid cost. Confirmation includes command ID, idempotency key, creative run UUID and SHA-256 of the complete canonicalized compiled plan (`sha256-sorted-json-v1`). No truncation or client-supplied scope override is accepted.

The module reuses `sc_v5_command_request_hash_v1` and `sc_v5_command_get_v1`, rather than creating another ledger. It recognizes terminal duplicates, rejects hash/command conflicts, refuses active or ambiguous expired leases, rejects old/materialized runs, checks latest RADAR/EDITOR/DIRECTOR stage evidence, recompiles and compares the plan hash, and calls the existing preflight and Quality V2 hook. Even a passing preparation returns `FACTORY_SCOPE_NOT_ISOLATED` and performs zero writes. Local claim-token/lease-version validation is defensive preparation only, not a substitute for atomic database fencing.

The original simulation/learning core is byte-identical to the recovered live version. LIVE boundary remains version 6 with its original allowlist. No schema migration or Edge deployment was performed. The staged adapter does **not** yet implement materialization, rendering or Guardian completion; it must not be described as a successful REAL adapter.

## Verification and limits

- 18 local tests passed: command binding, hash changes, insufficient permissions/user_metadata rejection, duplicates, active/expired ownership, globally open gate rejection, run reuse, creative-stage evidence, preflight failures, Quality routing, timeouts and 32 concurrent blocked requests.
- The concurrency test proves the preparation performs no mutations; it does NOT prove exactly-once production execution.
- Live negative-auth tests passed: missing JWT returned HTTP 401 `AUTH_REQUIRED`; deliberately invalid JWT returned HTTP 401 `UNAUTHORIZED_INVALID_JWT_FORMAT`. No real session was used. Raw results are saved in `artifacts/factory-auth-negative-live.json`.
- Office HTML, V6 assets and V5 backup compare unchanged to the recovery tag; prior UI regressions are reused because the UI and live backend were not modified.
- Before snapshot: 84 jobs, 30 posts, 17 V5 commands, 33 jobs with nonempty instagram_result. Existing historical posts/results are not publications from this task.
- Final LIVE snapshot at 2026-10-08 16:38:15 UTC: the same 84 jobs, 30 posts, 17 commands and 33 instagram_result jobs. All four canonical gates returned `allowed:false` at 16:37:49 UTC. No production records or gates were changed by this task.
- Candidate TypeScript syntax check passed. Original boundary core is byte-identical; `git diff --check` passed.
- No canary job, generated artifact, visual approval or READY claim exists. No paid service was added or called.

## Required continuation

Implement and verify atomic command-scoped production authorization within the existing V5 ledger/materializers, with claim-token AND lease-version fencing, immutable plan binding, uniqueness shared across existing entrypoints, and explicit reconciliation after ambiguous renderer failures. Integrate the frozen Quality V2 policy through its legitimate controlled rollout; do not silently route around it. Only then select/create a fresh fully validated creative run, obtain the existing operator JWT, execute one job through the existing renderer and Guardian, inspect the actual assets, and verify canonical READY without publishing. Preserve all publication gates OFF.

Rollback of this local-only work: return to the recovery tag. No production rollback is required because no live code or configuration was changed.
