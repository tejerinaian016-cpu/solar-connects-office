# Solar Connects AI Agent Office V6.1

V6 is a reversible presentation adapter over the existing V5 product. The original approved image was not available; implementation follows the written visual contract. Exact image parity has not been claimed.

## Scope and rollback

- `index.html`: only adds the V6/V6.1 stylesheets and V6 script references.
- `v6/office-v6.js`: moves existing station buttons into ten rooms, adds navigation shortcuts and reads the existing provider for visual evidence.
- `v6/office-v6.css`: styles apply only with `html[data-office-version="6"]`.
- `v6/sprites/`: ten original, independent pixel characters and Guardian's sleeping cat, ~21 KB total. Generated from integer rectangles by `tools/build-sprites.cjs`; no paid assets, fonts or application dependencies.
- `?v6=0`: restores the previous layout and handlers without changing data or operational configuration.
- `AI_AGENT_OFFICE_V5_FIRST_USEFUL_PRODUCT.html`: untouched backup, SHA-256 `aa65680d4d0eccfd994cab41921678c0d0074b6551687e0d0f668153d6e5abd3`.

## Binding inventory and preservation

| Contract | Existing selectors / interfaces | V6 treatment |
| --- | --- | --- |
| Agent selection | `#office`, `.department`, `.stations`, `.station`, `data-agent`, `onclick → select()` | Moves original buttons; preserves handlers and canonical agent identifiers, including `MEASUREMENT` for Analytics |
| Selected agent | `#detail`, `.detailTop`, `.portrait`, `.worker`, `.gridkv`, `#cycle` | Existing renderer retained; local sprite backgrounds and source annotation added; mock cycle remains explicitly MOCK and static |
| Activity | `#feed`, `.feedItem`, `.feedDot` | Original feed retained; provenance labels read from its original activity array |
| Realtime | `#rt-box`, `#rt-status`, `#rt-summary`, `#rt-diagnostic`, `v3-realtime-status` | Existing listeners and diagnostic rendering retained |
| Provider | `AgentStateProvider`, `MockAgentStateProvider`, `SupabaseAgentStateProvider`, `HybridAgentStateProvider`, `provider.subscribeToChanges()` | All original code byte-identical; adapter subscribes read-only |
| Job Flow | `#v4-flow-panel`, `#v4-flow-status`, `#v4-freshness`, `#v4-real-count`, `#v4-unknown-count`, `#v4-move-count`, `#v4-last-move` | Original panel moved to bottom; horizontal counts read from `__V4_DIAGNOSTICS__().provider` |
| Job anchors | `.v4-job-bay`, `.v4-job-token`, `data-agent`, `data-job-id`, `#v4-unknown-lane`, `.v4-unknown-jobs`, `#v4-motion-layer` | Original selectors and evidence-gated transition runtime preserved |
| Office / Command navigation | `#office-nav`, `#nav-office`, `#nav-command`, `#office-main`, `#command-view`, `footer`, `aria-selected`, `hidden` | Original click listeners preserved; shortcuts invoke existing navigation buttons |
| Auth | `#email`, `#magic`, `#refresh`, `#logout`, `#session`, local session key, JWT verification | Original code and IDs byte-identical |
| Command and canary | `#action`, `#agent`, `#job`, `#simulate`, `#out`, `#realLearning`, `#realStatus` | Original code and controls retained; not invoked in live verification |
| Safety | Existing Safety card, `__V5_AUTH_READY__` | V5 local execution policy is unchanged. V6.1 shows four UNKNOWN outputs: current canonical providers expose no gate snapshot; local policy and agent activity cannot prove remote OFF |

All four original inline scripts are compared byte-for-byte to V5 by the regression test. No ledger, backend, Supabase, Auth/JWT, Factory, Publisher, Recovery or Command logic changes were made.

## Canonical evidence

- MOCK retains its source label and never animates.
- Missing or insufficient evidence renders UNKNOWN and never animates.
- REAL animation additionally requires WORKING, a current-job description, a valid timestamp within 90 seconds, supported source and confidence. Future or stale evidence does not animate.
- Job movement continues through the existing canonical Job Flow transition logic. No synthetic jobs or movements are added.
- Reduced-motion preferences and the local presentation setting suppress animation.

## V6 verification before V6.1 (2026-10-08)

`node tests/v6-regression.cjs`: 17 checks passed. Includes original script / backup identity, all static IDs, ten agent handlers across rerenders, desktop 3×3 grid, 390 px responsive layout, evidence modes and animation restrictions, navigation, Auth operator and unprivileged claims using intercepted test responses, Realtime refetch, Job Flow transition and duplicate suppression, boundary-failure UNKNOWN, Safety controls, reduced motion and V5 rollback. Zero browser JS errors; zero external mutation requests.

`node tools/preview.cjs` followed by `node tests/v6-live-readonly.cjs`: live read-only verification. Both existing observability endpoints HTTP 200, Realtime CONNECTED, Job Flow READY / FRESH with 84 records at verification time, ten rooms, no horizontal overflow, general execution false, four disabled gate controls, zero JS errors and zero mutation requests. Existing historical agent evidence remains static. No live commands, publications or gate changes were performed.

Screenshots and machine-readable reports are in ignored `artifacts/`; fixture captures are explicitly named `fixtures`. Live captures are separate. Auth login using Ian's actual magic link was not performed; the preserved Auth path was tested with isolated fixtures.

The tests use the existing Codex runtime's Playwright installation and installed Chrome; the deployed application itself has no new framework or dependency.

## V6.1 visual correction (2026-10-08)

Built on V6 commit `d59596731e8c875d62de6049ad70cccc2eee4ff7`. The scoped `office-v6.1.css` restores navy surfaces, stronger agent accents and a warm sunset. Existing SVG sprites are enlarged from 72 to 96 px wide (Astra: 82 to 120 px), with larger status and panel text. Room structure and identities are retained. Astra's presentation shortcut invokes the existing Command navigation handler.

Safety no longer asserts OFF or DISABLED for operational gates. All four read-only outputs show UNKNOWN because the existing canonical contracts contain no gate-state evidence. No backend query contract, gate or operational action was added or changed.

All 19 regression checks pass, including byte-identical V4/V5 scripts and backup, existing IDs and handlers, Auth authorization, Realtime refetch, Job Flow transitions, UNKNOWN during failures, static MOCK, reduced motion, mobile overflow, V5 rollback, new Astra navigation, sprite sizes, typography and Safety UNKNOWN independent of REAL agent activity. Zero browser JS errors and zero external mutations in the controlled run. Desktop and 390 px mobile captures visually inspected. The original approved reference image remains unavailable for exact comparison.
