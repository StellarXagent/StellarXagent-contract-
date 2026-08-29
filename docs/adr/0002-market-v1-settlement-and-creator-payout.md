# ADR 0002: Market V1 Settlement Asset and Creator Payout Model

## Status
Approved

Maintainer merge of this ADR is the Market V1 economy approval gate, so the landed status is **Approved**. That unblocks Smart-contracts [#25](https://github.com/Stellar-AgentVerse/Smart-contracts/issues/25). This document still does not contain contract or backend code; implementation remains #25.

## Context

AgentVerse currently demonstrates purchase execution, not a marketplace economy.

`PromptMarketplace::buy_prompt` and `buy_private_prompt` debit the buyer by burning `MyToken` (`sell_forwarded`). The stored prompt `owner` is never paid. The platform never collects a fee. Circulation is restored only if an admin later calls `remint`. Users have no production path to acquire that custom token. Backend wallet credits and simulated XLM balances are a separate ledger ([Backend #16](https://github.com/Stellar-AgentVerse/Backend/issues/16)) and must not be treated as settlement.

ADR [0001](./0001-private-access-threat-model.md) defines private-access commitments and residual metadata leaks. It does **not** define who is paid, in which asset, or who owns funds after a failed delivery. Backend [ADR 003](https://github.com/Stellar-AgentVerse/Backend/blob/main/docs/adr/003-encrypted-prompt-delivery.md) defines encrypted delivery. It also does not define settlement.

Backend [#18](https://github.com/Stellar-AgentVerse/Backend/issues/18) splits the product into a Testnet UX beta and a later **Market V1** that may move real value only after this ADR, [#25](https://github.com/Stellar-AgentVerse/Smart-contracts/issues/25), security, and legal gates. Market V1 inventory is one product type: curated `PROMPT`.

This ADR chooses the narrow Market V1 economic model so implementation and audit work stay small and explicit.

## Decision

Market V1 is approved as follows:

| Choice | Market V1 |
| :--- | :--- |
| **Settlement asset** | Circle **USDC** on Stellar, held and transferred via the Stellar Asset Contract (SAC / SEP-41). |
| **Creator payout** | **Atomic on-chain split** in the same successful purchase invocation that grants access. |
| **Platform fee** | **1000 bps (10%)** of the on-chain price, integer math, remainder to the creator. |
| **Custody of creator principal** | **None.** Creator funds never sit in a platform wallet. |
| **Refunds / disputes** | Off-chain operator policy. On-chain purchase is final. Refunds are paid from the **platform treasury**, not clawed from the creator. |
| **Platform treasury** | Constructor-pinned. No setter. A new treasury requires a new marketplace instance. |
| **Legacy burn/remint** | **Not** Market V1. Existing records are not reinterpreted as paid USDC settlement. |

Rejected for Market V1:

- Custom `MyToken` / AVT / PRMPT as the settlement asset.
- Native XLM as the settlement asset.
- Platform collection with batched/manual creator payouts.

Testnet beta may keep using the current burn-path contracts for UX evidence. That path must not be presented as live revenue, and it must not be copied forward as the Market V1 catalog.

## 1. Settlement asset comparison

| Criterion | Custom AVT (`MyToken`) | Native XLM | Circle USDC (SAC) |
| :--- | :--- | :--- | :--- |
| Production acquisition | **None.** Owner-gated mint and `remint` are a closed demo loop. | Exchanges, DEX, Friendbot (Testnet only). | Exchanges, Circle, Stellar DEX/anchors, Testnet Circle faucet. |
| Price stability for digital goods | N/A (no external price). | Volatile. Creators cannot plan USD income. | USD-pegged. Catalog prices can be USD. |
| Wallet / ecosystem support | Custom contract; limited wallet recognition. | Universal, no trustline. | Native Stellar asset; Freighter and major wallets already support it. |
| Accounting / tax | Would require a second FX conversion. | Requires FX at each payout. | USD units match invoices and fee income. |
| Contract work | Already wired, but the burn path destroys value. | SAC `native` is simple (no trustline). | SAC `transfer`; G-address buyers/creators need a USDC trustline. |
| Trust | Platform is the issuer. Supply is an admin power. | Protocol native. | Circle issuance and reserves; issuer is not AgentVerse. |
| Fit for Market V1 | **No** — this is the problem statement. | **No** — funding exists, but the unit of account is wrong. | **Yes** — real-value unit plus an existing funding path. |

### Pinned USDC identity

The marketplace constructor stores the **USDC SAC `C...` address**. Pin code, issuer, **and** SAC id. Derive the SAC at deploy with `stellar contract id asset`; do not copy `C...` values from blogs alone.

| Network | Asset | Issuer | SAC (`C...`) |
| :--- | :--- | :--- | :--- |
| Mainnet | `USDC` | `GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN` | `CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75` |
| Testnet | `USDC` | `GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5` | `CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA` |

```text
stellar contract id asset --network mainnet --asset USDC:GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN
stellar contract id asset --network testnet --asset USDC:GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5
```

Issuer source: [Circle USDC contract addresses](https://developers.circle.com/stablecoins/usdc-contract-addresses). SAC ids above are the currently well-known values; the deploy command is authoritative.

Deploy verification must check that the constructor SAC equals the CLI-derived id, `decimals() == 7`, and symbol / issuer binding before the instance is used. The settlement asset cannot be retargeted after construct. A different asset requires a new marketplace instance and a new ADR if the unit of account changes.

**Issuer risk:** Circle USDC has `auth_clawback_enabled = false`, so this ADR’s treasury-funded refund model does not collide with issuer clawback. Circle has `auth_revocable = true`, so Circle can freeze a buyer, creator, or treasury trustline. A frozen destination makes the atomic purchase fail; it is not a platform clawback.

USDC on Stellar uses **7 decimals**. One display USDC = `10_000_000` stroops. All contract amounts are `i128` stroops.

## 2. Creator payout comparison

| Criterion | A. Atomic on-chain split | B. Platform collection + batched payouts |
| :--- | :--- | :--- |
| Settlement guarantee | Buyer debit, creator credit, platform fee, and access grant succeed or roll back together. | Buyer pays the platform. Creator payment is a later ops action. |
| Who holds creator funds | Creator wallet, immediately. | Platform treasury until a human batch runs. |
| Trust | Creators trust the fee formula and the listing `owner` address, not a payout queue. | Creators trust the platform to pay, reconcile, and remain solvent. |
| Legal / compliance | Platform receives only the fee. It is not a custodian of creator principal. | Custody, reconciliation, and likely money-transmitter / escrow burden. |
| Refund power | Platform cannot claw creator funds on-chain (Circle USDC clawback is not enabled for this issuer). Refunds come from treasury. | Platform can refund before payout, but then owns delayed-payout risk. |
| Contract / audit work | One or two SEP-41 transfers (skip amount `0`), fee math, stale-price and stale-split-auth guards, versioned events. | One transfer plus an off-chain ledger, payout tool, and evidence process. |
| Speed to a curated launch | More Soroban work; still a single focused follow-up (#25). | Faster contract, slower and riskier ops/legal launch. |
| Fit for Market V1 | **Approved.** | **Rejected** for V1. Revisit only with a new ADR if legal requires it. |

Atomic split is the point of putting the marketplace on Stellar. Option B recreates the backend simulated-credit problem with real money.

## 3. Approved purchase semantics

For both public `buy_prompt` and private `buy_private_prompt`:

1. Buyer authorizes the purchase.
2. Contract loads the listing, checks it is registered, and rejects replay (`AlreadyPurchased` / existing `PrivatePurchase`).
3. Caller supplies `expected_price`. It must equal the stored price. Stale backend intents fail closed. `expected_price` only protects the buyer **total**.
4. Contract computes `fee_amount` and `creator_amount` (see §6). `fee_amount + creator_amount == price`. `creator_amount` must be `> 0`.
5. Contract transfers USDC via the pinned SAC:
   - always `transfer(buyer → listing.owner, creator_amount)`
   - `transfer(buyer → platform_treasury, fee_amount)` **only when** `fee_amount > 0`
   Skip a SEP-41 transfer when its amount is `0` (a zero-amount transfer often fails). Nested SAC auths must bind the exact `creator_amount` and, when the fee transfer runs, the exact `fee_amount`.
6. Only after the required transfer(s) succeed does the contract write the access grant and emit the versioned purchase event.

If any required transfer fails (insufficient USDC, missing or frozen trustline, pause, wrong asset, stale nested-auth amounts), the invocation rolls back: the buyer keeps the funds and gains no access.

`MyToken::sell_forwarded` / `mint_forwarded` / `remint` are **out of the Market V1 purchase path**. They may remain on the legacy Testnet demo instance only.

## 4. Buyer onboarding and funding (end to end)

Market V1 is non-custodial. The backend never holds buyer secret keys ([Backend #9](https://github.com/Stellar-AgentVerse/Backend/issues/9)).

```
1. Install Freighter (or Stellar Wallets Kit).
2. Create / import a Stellar G-address.
3. Fund a small XLM balance for account reserves, trustlines, fees, and Soroban rent.
   Testnet: Friendbot. Mainnet: exchange or another Stellar account.
4. Create a USDC trustline to the pinned Circle issuer for that network.
5. Acquire USDC:
   Testnet — Circle Testnet faucet / documented test issuer.
   Mainnet — CEX withdrawal to Stellar USDC, Circle, or Stellar DEX/anchor.
6. Open AgentVerse, authenticate (JWT bound to that wallet), browse curated PROMPT inventory.
7. Backend creates an idempotent purchase intent bound to:
   asset id, expected_price stroops, creator_amount, fee_amount, fee_bps,
   USDC SAC id, marketplace id, network passphrase, entrypoint, arguments, expiry.
8. Wallet simulates, then signs the Soroban invocation plus nested SAC transfer auths
   bound to those exact split amounts (omit fee-transfer auth when fee_amount is 0).
9. Buyer submits; backend confirms from executed ledger evidence, not from a hash alone.
10. On success: USDC left the buyer, split hit creator + treasury, access grant exists,
    encrypted delivery may proceed (Backend ADR 003).
```

Backend simulated credit packages, Stripe/PayPal fabricated success, and `/api/wallet` placeholder balances are **not** a Market V1 funding path. They must fail closed in staging/production (Backend #16).

Buyers still need XLM for fees. That is a network cost, not the settlement asset.

## 5. Creator payout and withdrawal (end to end)

Market V1 onboarding is curated and operator-assisted (Backend #18). There is no open self-service publishing.

```
1. Creator provides a Stellar G-address they control (or a C-address they control).
2. Operator verifies the address can receive the pinned USDC:
   G-address — live USDC trustline to the pinned issuer, not frozen.
   C-address — SAC destination that can hold the asset.
3. Admin registers the listing with that address as `owner` and a price in USDC stroops
   (>= minimum price).
4. On each successful purchase, `creator_amount` USDC arrives in that address in the
   same transaction as the buyer's debit. No payout ticket, no schedule, no clawback.
5. Withdrawal is ordinary Stellar USDC movement from the creator's wallet:
   spend on-network, DEX, or CEX/off-ramp. AgentVerse does not run a withdrawal queue.
6. Support can show the versioned purchase event as proof of payment. It cannot
   re-route a completed split.
```

If the creator address cannot receive USDC at purchase time, the buy fails atomically and the listing is an operator defect. Operators must re-verify trustlines before going live and after issuer/auth flag changes.

There is no “pending creator balance” in platform custody. Any UI that shows “earnings” must be an index of on-chain split events, not an IOU.

## 6. Fee math, decimals, dust

Constants for Market V1:

| Parameter | Value | Notes |
| :--- | :--- | :--- |
| `FEE_BPS` | `1000` | 10%. Stored on-chain. |
| `BPS_DENOMINATOR` | `10_000` | |
| `MAX_FEE_BPS` | `2000` | 20% hard cap. Raising the cap needs a new ADR. |
| `MIN_PRICE` | `10_000_000` | 1.0000000 USDC. |
| Decimals | `7` | Circle USDC on Stellar. |

Integer math (no rounding beyond truncation toward zero):

```text
fee_amount     = price * FEE_BPS / 10_000
creator_amount = price - fee_amount
```

Invariants:

- `price > 0` and `price >= MIN_PRICE`.
- `fee_amount >= 0`, `creator_amount > 0`.
- `fee_amount + creator_amount == price` for every successful purchase.
- `fee_amount * 10_000 <= price * FEE_BPS` (platform never takes more than the advertised bps).
- At `FEE_BPS = 1000` and `MIN_PRICE = 10_000_000`, `fee_amount >= 1_000_000` stroops (0.1 USDC). Dust below one stroop cannot exist at this minimum.
- At `FEE_BPS = 0`, `fee_amount = 0` and `creator_amount = price`. #25 must **skip** the treasury transfer and still require `creator_amount > 0`. Do not call SEP-41 `transfer(..., 0)`.

Admin may lower `FEE_BPS` (including to `0` for promotions) or raise it up to `MAX_FEE_BPS`. Each change emits an event with old/new bps. Listings do not snapshot fee bps; the live schedule applies at purchase.

`expected_price` only guards the buyer’s total debit. Nested SAC auths must bind the exact `creator_amount` and (when non-zero) `fee_amount`. If `FEE_BPS` changes between simulation/sign and execution in a way that alters the split, the nested auths no longer match and the purchase **fails closed**. It must not settle a different creator/platform cut. If a later revision needs fee snapshotting per listing, that is a new ADR.

Prices are stored and charged in stroops. UI may display decimal USDC; clients must convert without floating-point drift (integer stroops on the wire).

## 7. Fund-ownership invariants

States below are for **one purchase**. Delivery is off-chain and cannot move USDC.

| State | Buyer USDC | Creator USDC | Platform treasury | Access grant |
| :--- | :--- | :--- | :--- | :--- |
| Intent created, not executed | Buyer | Unchanged | Unchanged | None |
| Invocation fails (auth, balance, trustline, freeze, pause, stale price, stale split auth, replay) | Buyer (rollback) | Unchanged | Unchanged | None |
| Invocation succeeds (`fee_amount > 0`) | Debited `price` | Credited `creator_amount` | Credited `fee_amount` | Written |
| Invocation succeeds (`FEE_BPS = 0`) | Debited `price` | Credited `price` | Unchanged | Written |
| Off-chain delivery success | Unchanged from success | Unchanged | Unchanged | Remains |
| Off-chain delivery failure / dispute | Unchanged from success | Unchanged from success | May later debit a refund | May be revoked by admin |
| Operator refund (V1 policy) | Credited `price` from treasury (off-contract payment) | Keeps `creator_amount` | Debited refund; net fee may go negative for that SKU | Revoked when refund is issued |
| Chargeback at a fiat on-ramp | On-chain USDC is already gone | Keeps funds | Absorbs on-ramp loss | Per dispute policy |

Rules:

1. **No partial settlement.** Access exists only after the required transfer(s) succeed. When `fee_amount = 0`, the treasury transfer is skipped by design; that is not a partial split.
2. **Creator principal is final** after success. V1 has no creator clawback function.
3. **Platform owns only fee USDC** plus whatever it later spends from treasury on refunds and operating costs.
4. **Failed delivery does not unwind the atomic split.** The contract cannot observe Backend ADR 003. Delivery failure is an ops/treasury problem, not a second ledger.
5. **Revoke ≠ refund.** `revoke_private_access` removes the grant. It must not be treated as a payment reversal unless a matching treasury refund record exists.
6. **Simulated backend credits never own Market V1 funds.**

## 8. Refunds, disputes, failed delivery, chargebacks

On-chain USDC settlement is final. Digital prompt delivery is off-chain (ADR 0001: the contract cannot mathematically enforce delivery).

### V1 policy (approved)

- **No on-chain escrow** and **no on-chain refund entrypoint** in #25. That keeps the audit boundary small.
- Buyer-initiated disputes go to a human operator within a published window (recommended: 7 days after the successful ledger close). The window is a support SLA, not a contract timeout.
- If ops upholds the buyer: (a) platform treasury sends `price` USDC back to the buyer in a separate, recorded payment; (b) admin revokes access; (c) backend marks the purchase `REFUNDED` against the original ledger tx and the refund tx; (d) creator keeps `creator_amount`. The platform eats the creator share as a support cost and may recover it off-chain by delisting or contract with the creator.
- If ops upholds the creator: no USDC movement; grant remains.
- Duplicate refunds are forbidden: one refund payment reference per original purchase event.
- Fiat on-ramp / card chargebacks are not Stellar operations. They are treasury risk owned by the Legal/Treasury roles. They must never rewrite on-chain history.

### Explicitly deferred

- Buyer-creator on-chain escrow until delivery ack.
- Automatic refund if the delivery worker fails.
- Clawback of creator USDC.
- Insurance pool inside the marketplace contract.

## 9. Replay, idempotency, reconciliation

### On-chain

- Public: at most one grant per `(buyer, prompt_id)`.
- Private: at most one grant per `(buyer, prompt_hash)` until admin revoke; a new purchase after revoke is a new payment (same as a new sale).
- `expected_price` mismatch aborts. That check does not bind the creator/platform cut.
- Settlement SAC address is instance-fixed; wrong-asset invocations cannot succeed against this marketplace.
- Nested buyer authorization must bind the exact `creator_amount` and, when `fee_amount > 0`, the exact `fee_amount`. A live `FEE_BPS` change that would alter those amounts fails closed (stale nested auth), not with a different split.
- When `fee_amount = 0`, there is no treasury transfer and therefore no nested fee-transfer auth.
- A replayed envelope against a grant that already exists fails `AlreadyPurchased` before a second debit.

### Off-chain (backend)

- Purchase intents use a buyer-scoped idempotency key, immutable snapshot, and expiry (Backend #9).
- Confirmation requires executed-ledger evidence that matches the snapshot (marketplace id, SAC id, entrypoint, arguments, amounts, network).
- Transaction hash is unique. Concurrent confirms settle once.

### Accounting evidence

Successful Market V1 purchases emit versioned events, for example `prompt_purchased_v2` / `private_prompt_purchased_v2`, with at least:

`buyer`, `prompt_id` or `prompt_hash`, `price`, `creator`, `creator_amount`, `platform_treasury`, `fee_amount`, `fee_bps`, `settlement_asset`.

Forbidden in events/storage: plaintext prompt content, DEKs, content URIs on the private path (ADR 0001). Public `prompt_id` remains a residual leak on the public catalog path.

Daily (or per-shift) reconciliation:

```text
sum(price) == sum(creator_amount) + sum(fee_amount)
Δ creator wallets (indexed) == sum(creator_amount)
Δ treasury wallet == sum(fee_amount) - sum(refund payments)
access grants == successful purchase events - revokes
```

Mismatches are incidents. Operators reconcile from events + RPC, not by editing database balances into existence.

## 10. Admin, pause, multisig, migration powers

| Power | Market V1 | Bound by |
| :--- | :--- | :--- |
| Register / update / remove curated listings | Yes | `admin.require_auth()` |
| Set `FEE_BPS` in `[0, MAX_FEE_BPS]` | Yes | Admin + event |
| Pause / unpause purchases | Yes (marketplace-level) | Admin. USDC itself cannot be paused by AgentVerse. |
| Change settlement SAC | **No** | Constructor-pinned. New instance + new ADR if the asset changes |
| Change `platform_treasury` | **No** | Constructor-pinned. No setter. A new treasury requires a new marketplace instance and deploy record, same class of risk as retargeting the settlement SAC. |
| `remint` / burn-for-access | **Not on Market V1 instance** | Legacy demo only |
| Upgrade WASM | Only if an explicit upgrade path is added later | Out of V1 settlement scope; #26 covers Mainnet controls |
| Refund USDC | Off-contract treasury payment | Treasury signers |
| Revoke private access | Yes (existing) | Admin; not a payment reversal |

Before Mainnet, `admin` and `platform_treasury` SHOULD be distinct Stellar **multisig** accounts. Signer lists live in deploy artifacts, not in this ADR’s prose. Single-key admin is acceptable on Testnet only.

## 11. Named owners of trust, custody, legal, and operations

Roles below are the Market V1 binding. Empty legal ownership **blocks Mainnet**, not this ADR’s merge (same gate as Backend #18).

| Domain | Named owner | Notes |
| :--- | :--- | :--- |
| Economy policy (asset, fee, payout model) | **Joaquín Pappa (`@Joaco2603`)** as Stellar-AgentVerse product maintainer, with the remaining **Smart-contracts maintainers** on merge | Author of #24, #25, and Backend #18. |
| Marketplace `admin` (pause, listings, fee bps, revokes) | **Stellar-AgentVerse maintainers** via the on-chain admin account | Mainnet: multisig; signers named in the deploy summary. |
| Platform treasury (fee income, refund payments, on-ramp losses) | **Stellar-AgentVerse maintainers** via the constructor-pinned `platform_treasury` account | Distinct from admin when operationally possible. No on-chain retarget. |
| Creator-principal custody | **None** | Atomic split. If a future ADR chooses Option B, this row must become a named custodian before any collection. |
| Ledger reconciliation and support | **Stellar-AgentVerse maintainers** until #26 names an ops owner | Use versioned events; no silent DB edits. |
| Legal, tax, consumer-refund law, licensing | **Unassigned until Mainnet** | Must be a named human in [#26](https://github.com/Stellar-AgentVerse/Smart-contracts/issues/26) / Backend #18 before real-value launch. This ADR does not appoint counsel. |
| Tax reporting for creators | **Each creator** for their USDC income; platform files only what counsel requires | Communicate in creator onboarding. |

Changing a named owner does not require a new economic model, but it does require an update to this table or the Mainnet deploy record.

## 12. Migration from burn / remint (no silent reinterpretation)

| Artifact | Burn-era (current Testnet demo) | Market V1 |
| :--- | :--- | :--- |
| Payment | `MyToken` burned from buyer | Circle USDC transferred to creator + treasury |
| Creator | Stored, unpaid | Paid `creator_amount` in the purchase tx |
| Platform | Unpaid; optional later `remint` | Paid `fee_amount` in the purchase tx |
| Access `Purchase` / `PrivatePurchase` | Demo entitlement on that instance | New grants on a **new** marketplace instance |
| Events `prompt_purchased` (v1) | Burn evidence | Must not be indexed as USDC settlement |
| AVT / PRMPT balances | Custom token, admin-minted | **Not convertible** to USDC |
| Backend simulated XLM/credits | Fake ledger | Forbidden as settlement evidence |

Rules:

1. Deploy a **new** `PromptMarketplace` instance whose constructor pins the USDC SAC, `platform_treasury`, and initial `FEE_BPS`. There is no treasury or SAC setter. Do not reuse the burn-era contract id as a live Market V1 catalog.
2. Do **not** copy `has_access` / `has_private_access` from the burn-era instance. Those grants were not paid in USDC.
3. Do **not** treat a historical `PromptPurchased` burn event as a creator payable or platform receivable.
4. Leave the burn-era Testnet contracts up only if labeled demo/non-value. README deploy ids that point at burn-era WASM stay historical until operators replace them.
5. Backend purchase rows that settled under the burn path keep their original meaning. A schema/version flag must distinguish `settlement_model = burn_v0` from `settlement_model = usdc_split_v1`.
6. If a Testnet buyer “bought” a prompt by burning AVT, they must buy again in USDC to hold a Market V1 grant. Communicate this; do not airdrop grants.

## 13. Privacy interaction (ADR 0001)

ADR 0001 remains in force for private listings: opaque `BytesN<32>` commitments, no plaintext content on-chain.

Additional residual leaks introduced by this ADR (accepted for V1):

- USDC transfers reveal `creator_amount` and `fee_amount` destinations.
- `listing.owner` is already public on registration events; the split makes the economic relationship explicit.

Atomic USDC split does not restore unlinkability. Relayers/ZK remain out of scope (ADR 0001).

## 14. Follow-up implementation and audit boundaries

Implementation is **Smart-contracts #25**, unblocked when this Approved ADR lands. Suggested review slices:

| Slice | In scope | Out of scope |
| :--- | :--- | :--- |
| **A. Settlement core** | SAC `transfer`s; skip any transfer whose amount is `0`; `expected_price`; `MIN_PRICE`; fee math; constructor fields (`usdc_sac`, `platform_treasury`, `fee_bps`) with **no** SAC or treasury setter; marketplace pause | New token contract, DEX, on-ramp, AVT migration mint, treasury retarget |
| **B. Events / accounting** | Versioned `*_v2` purchase events with split fields; fee-update event | Backend indexer (separate Backend PR) |
| **C. Auth** | Nested buyer auth binding exact `creator_amount` / `fee_amount`; Testnet integration with real signatures (Freighter/CLI). Document the Soroban v25 mock-auth limitation already noted in README | Relayers, sponsored fees, smart-wallet passkeys |
| **D. Legacy isolation** | Market V1 instance has no `remint` purchase coupling; tests prove burn-era ids are unused | Deleting `MyToken` from the repo |
| **E. Evidence** | Unit + invariant tests (`fee+creator==price`, skip `transfer(..., 0)`, rollback on failed transfer, replay, stale price, stale nested split auth, pause, frozen destination); Testnet script; `simulateTransaction` resource note | Full Mainnet audit package (#26) |

#25 must not add escrow, clawback, on-chain refunds, or a second settlement asset. Those expand the audit surface past a focused review.

Client/backend payload changes that #25 should document (not implement in this repo unless already present): nested auth entries bound to exact split amounts, skip zero-amount transfers, `expected_price`, constructor-pinned USDC SAC id and `platform_treasury`, `settlement_model` version, stop sending burn-path XDR for Market V1 inventory.

## Non-goals

- Implementing or deploying settlement code in the PR that lands this ADR.
- Choosing an AVT listing/liquidity program.
- Open creator onboarding or non-PROMPT inventory.
- On-chain delivery escrow, ZK payments, or privacy stronger than ADR 0001.
- Appointing licensed counsel (Mainnet gate, not this document’s merge).
- Reinterpreting Testnet burn purchases as USDC-paid.

## Consequences

- Market V1 prices are USDC stroops. UI, backend intents, and contracts share one unit.
- Creators must be able to receive Circle USDC before a listing goes live.
- Platform revenue is the 10% fee actually received by `platform_treasury`.
- Support refunds are a treasury expense; they cannot silently debit creators.
- `MyToken` remains a Testnet demonstration token, not a currency.
- ADR 0001 private purchases use the same split; privacy guarantees do not change except for the extra transfer metadata above.
- #25 is unblocked by this Approved ADR.

## Acceptance criteria map

| Criterion | Where this ADR satisfies it |
| :--- | :--- |
| One settlement asset and one payout model | USDC SAC + atomic on-chain split (§Decision, §1, §2) |
| Buyer funding and creator withdrawal journeys | §4, §5 |
| Fund ownership including delivery failure / refund / dispute | §7, §8 |
| Fee math, decimals, dust, replay, idempotency, reconciliation | §6, §9 |
| Named owners for trust / custody / legal / ops | §11 |
| Explicit burn/remint migration, no silent reinterpretation | §12 |
| Small follow-up / audit boundaries | §14, #25 slices A–E |
