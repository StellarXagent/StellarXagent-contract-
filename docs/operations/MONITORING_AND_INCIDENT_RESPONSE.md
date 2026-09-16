# Mainnet Monitoring & Incident Response

Operational runbook for the deployed `MyToken` / `PromptMarketplace` pair,
required by [#26](https://github.com/Stellargent/Smart-contracts/issues/26).

## Monitoring signals

| Signal | How to check | Alert condition |
|---|---|---|
| Contract paused state | `stellar contract invoke --id <TOKEN> -- paused` (also emitted by `scripts/verify-mainnet.sh`) | Unexpected `true` outside a declared incident/maintenance window. |
| On-chain WASM hash drift | `scripts/verify-mainnet.sh`, scheduled periodically | Hash mismatch vs. the last signed release artifact — treat as a possible upgrade/compromise and stop the world until explained. |
| Admin/deployer account balance | `stellar keys address` + horizon/RPC balance query | Deployer/admin XLM balance below the amount needed for one `pause()`/incident transaction plus fees. |
| Token supply trend | `total_supply` via `stellar contract invoke` | Mint/remint volume outside the range agreed for the approved economy (see #26 acceptance criteria on the "approved economy"). |
| Marketplace registrations | `PromptPurchased` / prompt registration events | Spike in registrations or purchases inconsistent with expected usage — possible abuse or bug. |
| Purchase reconciliation | Sum of `SellEvent`/`MintEvent` amounts vs. `total_supply` delta (same math as `scripts/testnet-dry-run.sh`'s reconciliation step) | Any mismatch — this means tokens were created or destroyed outside the observed event stream. |

These are the required signals, not a specific vendor. Wiring them into a
concrete dashboard/alerting stack is out of scope for this repository and
is a maintainer/ops task, not a contract-code task.

## Incident severity levels

| Severity | Example | Response |
|---|---|---|
| SEV-1 | Suspected admin/deployer key compromise, unauthorized mint, contract behaving outside its tested spec, exploited auth bypass. | Page on-call immediately. Pause within the target response time below. Do not wait for full root-cause before pausing. |
| SEV-2 | Resource/fee exhaustion risk, degraded but not exploited auth path, monitoring signal firing without confirmed fund impact. | Investigate within the same business day; pause if investigation is inconclusive after the target window. |
| SEV-3 | Documentation/monitoring gaps, non-exploitable inconsistency. | Track as a normal issue. |

## Pause criteria (SEV-1 default action)

`MyToken.pause()` is owner-gated and, because `sell`, `sell_forwarded`, and
`mint_forwarded` are all `#[when_not_paused]`, pausing the token also
blocks the entire `PromptMarketplace` purchase/remint flow — there is no
separate marketplace-level pause to forget. Pause first, investigate
second, for any SEV-1.

- **Target time-to-pause once a SEV-1 is confirmed: 15 minutes**, bounded by
  how fast the admin multisig/hardware quorum can co-sign (see
  `docs/security/MAINNET_CUSTODY_POLICY.md`). This number must be validated
  against the real quorum's signing latency before being trusted as a
  release gate, and updated here if the real number differs.
- Unpausing requires the same admin quorum and a documented reason —
  treat `unpause()` with the same care as `pause()`, not as a routine
  action.

## Rollback / migration procedure

There is no in-place contract upgrade path in this codebase (`set_marketplace`
is a one-time bind, not an upgrade mechanism). Rollback means:

1. Pause the affected `MyToken` (stops all value movement immediately).
2. Root-cause the incident against the frozen commit / audit sign-off.
3. Fix, then repeat the full release gate
   (`docs/security/MAINNET_RELEASE_CHECKLIST.md`) for the fix — a hotfix to
   a Mainnet money contract still needs review and a fresh Testnet dry run,
   just on a shorter clock.
4. Deploy a new `MyToken` + `PromptMarketplace` pair, bind with
   `set_marketplace` once, and follow "Migración de instancias existentes"
   in `README.md`. Any balance carry-over from the paused contracts is an
   explicit, reviewed, auditable operation, never automatic.
5. Publish the new contract IDs; mark the old ones as retired in the
   README, the same way the pre-`set_marketplace` Testnet IDs are already
   marked unsafe.

## Named operators

_Placeholder — must be filled with real names/roles before the first
Mainnet deploy is considered release-gate-complete
(`MAINNET_RELEASE_CHECKLIST.md` §7)._

| Role | Name | Contact | Backup |
|---|---|---|---|
| Release owner | _TBD_ | _TBD_ | _TBD_ |
| On-call / pause authority (multisig signer) | _TBD_ | _TBD_ | _TBD_ |
| Security contact | _TBD_ | _TBD_ | _TBD_ |

## Post-release ownership

The release owner above is responsible for: keeping this document current
as the contracts or economy change, re-running `scripts/verify-mainnet.sh`
on the cadence agreed with the team, and owning the next release-gate pass
if a rollback/migration happens.
