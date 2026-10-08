# Factory isolation candidate — freeze preserved

## Delivery boundary

Based on `25812a51bad3e73b6fba4c2da439281a64cf93ca`, backed up remotely as `backup/factory-pre-isolation`. Work stays on `feat/factory-real-controlled`. No migration, Edge deployment, main update, live permit, gate update, production job, renderer, Guardian or publication was performed.

`supabase/candidate/factory-isolation.sql` is executable **candidate SQL tested locally**, deliberately outside migrations. It reuses V5 commands and calls the existing Quality V2 production materializer. The private permit table extends authorization; it is not another job ledger.

## Implemented invariants

- Command/actor/idempotency/request hash/run/compiled plan/claim token/lease version are bound together. Plan, Quality input and slot cannot be substituted. Explicit confirmation contains the command, idempotency key, run and plan hash.
- One permit per command and per creative run, consumed in the transaction that inserts the job. One active permit per transaction; direct legacy inserts cannot use a caller-controlled setting to impersonate it.
- Advisory run lock, ledger/permit row locks, clock-based lease checks after waits and after materialization. Exceptions roll back the job, permit consumption and ledger changes. No lease renewal or ambiguous retry.
- Live operator metadata and session existence are checked in the database. Functions have no API execute grants; no client/service role can issue a permit directly. Existing JWT boundary is unchanged and remains read-only for Factory.
- Compiler/stages are rechecked under locks. Plan changes fail closed. The job records command/hash and remains publish-blocked. Returning a draft is not READY or command success.
- Existing Quality V2 inserts before annotating creative_run_id. The guard binds that insert using its exact existing `quality-v2-shadow:factory_run_<uuid>` key and the private transaction permit, then annotates it before insertion. Subsequent reassignment of the run is rejected.

## Emergency closure and Quality

**No exception to FACTORY OFF exists.** Both permit issuance and consumption require canonical FACTORY ON, all publication gates OFF, Quality V2 unfrozen, its selected format kill switch false and an actual V2 route. No V1 fallback is called.

The config/policy rows are locked during the short DB transaction. An emergency OFF committed before execution wins; an OFF concurrent with an already locked transaction waits for that transaction to commit/roll back. It does not retroactively cancel a committed job. No render/network request is inside this transaction. The permit can independently be revoked, and a reclaimed/expired lease cannot reuse it. Future renderer dispatch must recheck closure separately.

## Verified and still pending

The native test runner starts PostgreSQL 18.4 on an ephemeral loopback port, tests actual SQL with synthetic fixtures, and shuts it down. It tests 32 independent connections, duplicate authorization, revocation/closure/expiry while blocked on locks, failures after insertion and outer rollback. Results: `docs/evidence/factory-isolation-results.json`. Earlier 18 JS tests also pass.

Quality/compiler/Auth tables in these tests are **fixtures**, not a full Supabase clone. The existing production insert contract was inspected read-only. Full integration with Quality's validators, security mutation audit, current table triggers/RLS and Supabase JWT sessions still needs an isolated staging database. Nothing here proves a real canary can reach READY.

The insert guard intentionally denies **all new jobs without an authorized creative run**, including old/shadow entrypoints. Deployment would change those write flows. This broad closure must be explicitly reviewed and regression-tested on staging; do not deploy it blindly. Existing rows, Office HTML, V6 assets, V5 backup, Auth/Realtime/Job Flow implementation and live backend remain unchanged.

Hash algorithm is explicitly `sha256-pg-jsonb-v1`, computed server-side from canonical PostgreSQL jsonb text. It is not interchangeable with the preparatory JS `sha256-sorted-json-v1`; old confirmations must fail. The public preparation endpoint, Edge-to-private-RPC bridge, grants, deployment migration and read-only reconciliation endpoint remain intentionally unwired. No UI change was made.

## Reproduce on Windows

Copy `tests/factory-db-runtime/package.json` and `pnpm-lock.yaml` to `artifacts/factory-db-test/`, then run `pnpm install --dir artifacts/factory-db-test --frozen-lockfile --ignore-scripts`. The downloaded PostgreSQL binary worked without postinstall. No paid service is used.

Run `node tests/factory-isolation-native.cjs` and `node --test tests/factory-controlled.test.mjs`. Dependencies are test-only; no runtime dependency was added to Office. Clusters and raw outputs remain in ignored artifacts. No real credential is read by the test harness.

## Exact authorization needed for a future canary

First finish staging integration and review the write-flow impact above; this is a technical prerequisite, not a request to lift freeze now. Then a separate explicit authorization must name:

1. Deployment of the reviewed isolation/Edge bridge, with no broad grants or legacy bypass.
2. One fresh approved run, command ID, idempotency key, server plan hash, Quality input/slot and operator session; a current claim token and lease version bind the resulting one-use permit.
3. Legitimate unfreeze/first-slot transition and enablement of only the selected Quality V2 format; FACTORY temporarily ON with emergency OFF available. PUBLISHER, META_DIRECT and EXTERNAL_WRITE stay OFF.
4. Exactly one materialization, then existing renderer and evidence-based Guardian; stop at canonical READY, USD 0 added cost, restore FACTORY OFF on every exit. No publication authorization.

At 2026-10-08 17:02:34 UTC, read-only LIVE verification showed all four gates OFF; `STAGE1_FROZEN_OBSERVATION`, all four format kill switches true, first slot `CONFIRMED_FROZEN`; 84 jobs, 30 historical posts, 17 commands unchanged.

Rollback now: return to the backed-up commit/branch; no production rollback is necessary. Future deployed rollback must close FACTORY before removing authorization enforcement; never remove the guard while FACTORY is ON.
