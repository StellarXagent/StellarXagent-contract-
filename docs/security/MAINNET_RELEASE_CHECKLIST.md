# Mainnet Release Gate — Checklist

Tracks readiness for the first real-value Mainnet deployment of `MyToken` +
`PromptMarketplace` (Market V1). This is the release gate for
[#26](https://github.com/Stellargent/Smart-contracts/issues/26) and
must be fully green — no unresolved `[ ]` items — before running
`scripts/deploy-mainnet.sh` against `--network mainnet` with real funds.

A green CI run or a successful script execution is **not** evidence of
Mainnet safety by itself. This checklist exists so that claim is never made
implicitly.

## Status legend

- `[x]` — done, with evidence linked.
- `[ ]` — not done. Requires a human action outside this repository (an
  external audit, a funded multisig, a real Mainnet transaction) and cannot
  be marked done by a code change alone.

## 1. Dependency provenance (blocking prerequisite)

- [ ] [#9 — Security: define dependency provenance and reproducible audit
  policy](https://github.com/Stellargent/Smart-contracts/issues/9) is
  closed and the locked dependency graph is reproducible.

This item is **out of scope for this PR** — it is tracked and resolved in
#9, not duplicated here. This checklist will not be marked ready for
Mainnet while #9 is open, per the acceptance criteria of #26.

## 2. Freeze: commit, toolchain, WASM hashes, interfaces, migration plan

- [x] Release commit is the tip of `main` at the moment `deploy-mainnet.sh`
  is run; the script fails closed if the working tree does not build.
- [x] Toolchain is pinned and documented: Soroban SDK `25.3.0`, Stellar CLI
  `26.1.0`+, target `wasm32v1-none`,
  `SOROBAN_SDK_BUILD_SYSTEM_SUPPORTS_SPEC_SHAKING_V2=1` (see `README.md`).
- [x] WASM hashes (SHA-256) are computed at build time and re-verified
  on-chain by `scripts/deploy-mainnet.sh` and `scripts/verify-mainnet.sh`.
- [x] Public interfaces (constructor args, `set_marketplace`,
  `mint`/`sell`/`sell_forwarded`/`mint_forwarded`, `pause`/`unpause`) are
  documented in `README.md` and covered by the 58 unit tests.
- [x] Migration plan for pre-`set_marketplace` instances is documented in
  `README.md` under "Migración de instancias existentes": redeploy both
  contracts, bind once with `set_marketplace`, no automatic balance
  reinterpretation, any balance migration must be explicit and auditable.
- [ ] The frozen commit hash, toolchain versions, and WASM hashes for the
  actual Mainnet release candidate are recorded in a signed release note
  (template: `docs/security/AUDIT_PROCESS.md#sign-off-record`) before
  deploying.

## 3. Independent security review

- [ ] Independent review/audit completed. Process, scope, and severity SLA
  are defined in `docs/security/AUDIT_PROCESS.md`; the sign-off record in
  that document is intentionally blank until a real review happens.
- [ ] All critical/high findings resolved and re-reviewed.

This repository cannot generate or simulate this review — it requires an
external reviewer with no stake in the code.

## 4. Fresh Testnet exercise (adversarial, resource budgets, pause/recovery, reconciliation)

- [x] `scripts/testnet-dry-run.sh` deploys a fresh Testnet pair from the
  release commit and runs, against real Testnet transactions:
  - adversarial calls (`mint_forwarded`/`sell_forwarded` invoked directly,
    bypassing the marketplace — must fail),
  - a pause/recovery drill (`pause()` blocks `buy_prompt`, `unpause()`
    restores it),
  - a resource-budget capture (`--cost` output per invocation, logged for
    review against the account's expected fee budget),
  - a reconciliation check (on-chain `total_supply` matches the expected
    mint/burn/remint ledger the script keeps).
- [ ] The dry run has actually been executed against a live Testnet RPC for
  this release commit and its JSON report
  (`deploy-artifacts/testnet-dry-run-report-*.json`) is attached to the
  release sign-off. Running it is a maintainer action; this PR provides the
  tool, not the run.

## 5. Deployer/admin separation and custody policy

- [x] `scripts/deploy-mainnet.sh` and `scripts/verify-mainnet.sh` require
  distinct `MAINNET_DEPLOYER_SOURCE` / `MAINNET_ADMIN_SOURCE` /
  `MAINNET_ADMIN_ADDR` and never accept inline private keys.
- [x] Multisig/hardware-wallet policy for the admin identity is documented
  in `docs/security/MAINNET_CUSTODY_POLICY.md`, including quorum, key
  storage, and rotation-on-compromise procedure.
- [ ] The actual Mainnet admin account is a multisig/hardware-backed
  account matching that policy, and a test transaction proving the quorum
  works has been executed and recorded.

## 6. Deploy, verify, publish, canary

- [x] `scripts/deploy-mainnet.sh` deploys, initializes, binds, and validates
  on-chain state/hashes, writing a JSON deploy summary.
- [x] `scripts/verify-mainnet.sh` independently re-verifies a deployed pair
  without redeploying, for CI or periodic checks.
- [x] `scripts/canary-mainnet.sh` runs one capped, real-value purchase
  (hard-capped price, requires an explicit confirmation phrase, refuses to
  run unless `verify-mainnet.sh` passes first) and checks settlement,
  `has_access` delivery, and balance reconciliation.
- [ ] Contract IDs and supported interfaces for the actual Mainnet
  deployment are published (README table + release note).
- [ ] The canary has actually been run on Mainnet and its report attached
  to the release sign-off.

## 7. Monitoring, incident response, pause criteria, rollback, ownership

- [x] `docs/operations/MONITORING_AND_INCIDENT_RESPONSE.md` defines
  monitoring signals, alert thresholds, incident severity levels, pause
  criteria (using the existing owner-gated `pause()`/`unpause()` on
  `MyToken`, which also blocks `sell_forwarded`/`mint_forwarded` and
  therefore the entire purchase flow), the rollback/migration procedure,
  and a named-operator template.
- [ ] The named-operator table in that document is filled in with real
  people/roles (not placeholders) and the pause/recovery drill has been
  exercised end-to-end by those operators, not just by the script in CI.

## Non-goals (from #26, reaffirmed here)

- A passing script run is not a security audit.
- This checklist does not authorize deploying before Backend/UI staging
  proves the complete purchase journey end-to-end.
