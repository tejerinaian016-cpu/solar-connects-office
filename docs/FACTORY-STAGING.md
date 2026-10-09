# Factory staging closure — SQL validated, E2E BLOCKED / NO-GO

Continues `fdaaf44a3cd96e9266162212f23c3475aa95cdc9` on `feat/factory-real-controlled`. Supersedes the broad-trigger limitation in FACTORY-ISOLATION.md. No live deployment or main merge.

## Correction

The insert guard now protects reserved creative runs and controlled command/hash markers. Unreserved legacy inserts retain their existing permissions, RLS and producer gates. It recognizes Quality V2's original idempotency key before creative_run_id annotations. Every supplied run identity is locked in sorted order, preventing a second identity in qa/key from racing a reservation. Permit issuance rejects already-materialized runs. Late legacy annotations remain allowed; controlled identities remain immutable. No exception to FACTORY OFF or Quality freeze was added.

## Evidence and scope

- `supabase/staging/real-contracts.json`: read-only production catalog export of 10 relevant tables, columns, constraints, indexes, RLS settings, policies and triggers, plus 18 function definitions. Trigger function bodies are also included.
- `real-privileges.json`: real role capability flags and function ACLs. No passwords, keys, user rows, sessions or business content exported.
- `tests/factory-real-contracts.mjs`: restores those definitions in isolated loopback PostgreSQL and compares the original V1 SHADOW materializer and Quality V2 SHADOW adapter before/after the candidate. It uses synthetic creative rows but **does not replace those SQL functions with fixtures**.
- Nine integration groups pass: baseline and after-change legacy behavior, forged markers, reserved-run bypass across real entrypoints, V5 claim/audit, transaction rollback, RLS/private grants, secondary-identity bypass, and 16 independent connections denied on a reserved run. Detailed checks are in `docs/evidence/factory-real-contracts-results.json`.
- The existing 33 local SQL tests were rerun after narrowing the trigger; the former blanket-denial expectation was corrected to assert legacy compatibility. These tests still use partial fixtures and remain labelled separately. Their 32-connection single-use test passes. The prior 18 JS tests are reused; the boundary module was not edited.
- V6.1 HTML/assets and V5 backup compare byte-unchanged to `16e73d6ba5d23c1ad802d18ebb53f088571699c4`. No Auth, Realtime or Job Flow application code was edited.

Reproduce with `node tests/factory-isolation-native.cjs --real-contracts`, then `node tests/factory-isolation-native.cjs`. Both runners stop their isolated PostgreSQL server even on failure. Dependencies/lockfile are already preserved in `tests/factory-db-runtime/`.

## Deliberate limitations — not PASS

The local database is PostgreSQL 18.4; production reports PostgreSQL 17.6. It is not a full Supabase clone. Auth tables/functions in the replay are explicit load-only placeholders, never proof of real JWT/session validation. The original Realtime trigger is restored, but catches missing realtime.send; delivery is **not** validated. Autonomous orchestration and its external runtime are **not** tested end to end; only the stated legacy SQL producers/privileges are covered.

Only the production project `akwqkymjrovqiijnhrqs` was accessible in the project listing, with no development branches. Docker, Supabase CLI and Deno were unavailable locally. No isolated Supabase staging endpoint or staging credentials were supplied. No paid branch/project was created. Therefore a full authenticated Edge/PostgREST/Auth/Realtime test cannot be performed here at confirmed USD 0. Production was never used as its substitute.

The Edge bridge, narrow public RPC grants, real-session permit issuance/consumption, closure and reconciliation are still not wired/tested. Candidate private routines remain inaccessible to anon/authenticated/service_role. Do not deploy this branch as a completed REAL adapter.

## Minimal remaining path, no repeated SQL audit

1. Provide a local Docker-compatible runtime with sufficient resources for a free local Supabase stack, or an already available isolated Supabase staging project confirmed to add USD 0. Use staging-only keys/users; no production credentials/data are needed.
2. Restore the saved SQL export and scoped candidate there, matching PostgreSQL 17 where possible. Supply the actual Auth/PostgREST/Edge/Realtime services rather than the two Auth placeholders. Keep all four gates OFF and Quality frozen.
3. Wire the existing JWT boundary to narrow staging RPCs using the caller identity, not a service-role substitution. Implement read-only plan preparation/reconciliation plus explicit permit closure. Verify real JWT expiry/revocation/app_metadata, exact grants, RLS, freeze denial, and Realtime events on synthetic SHADOW transactions.
4. Run only the remaining E2E cases and any regressions they expose; reuse the saved SQL suites. This still does not authorize a productive canary, unfreeze, renderer, Guardian or publication.

Decision: **NO-GO for deployment/canary** until those E2E prerequisites pass. Production remains read-only; FACTORY/PUBLISHER/META_DIRECT/EXTERNAL_WRITE OFF, Quality V2 frozen. No production jobs, renders, external writes or publications were created.

Final read-only LIVE check: 2026-10-09 01:48:31 UTC. Four gates false; Quality `STAGE1_FROZEN_OBSERVATION`, all four format kill switches true, first slot `CONFIRMED_FROZEN`. Counts remain 84 jobs, 30 historical posts and 17 V5 commands.
