# Mainnet Admin/Deployer Custody Policy

Governs who can build, deploy, and administer the Mainnet `MyToken` /
`PromptMarketplace` contracts. Required by
[#26](https://github.com/Stellar-AgentVerse/Smart-contracts/issues/26).

## Two identities, never one

`scripts/deploy-mainnet.sh` and `scripts/verify-mainnet.sh` already enforce
this at the tooling level by requiring separate env vars:

| Identity | Env var(s) | Powers | Custody requirement |
|---|---|---|---|
| **Deployer** | `MAINNET_DEPLOYER_SOURCE` | Pays fees, submits `contract deploy`. No ownership of the deployed contracts. | Funded hot key is acceptable; scope it to deployment only, rotate after each release. |
| **Admin/Owner** | `MAINNET_ADMIN_SOURCE`, `MAINNET_ADMIN_ADDR` | `MyToken`: `owner` — `mint`, `set_marketplace` (one-time), `pause`/`unpause`. `PromptMarketplace`: `admin` — `register_prompt`, `update_price`, `remove_prompt`, `remint`. | **Must** be a multisig account or hardware-wallet-backed signer. This key can mint tokens and pause the market — treat it as the highest-value secret in this repository. |

The deployer and admin **must** be different accounts. If they are the same
key, a single compromised secret can both deploy and administer the
contracts, defeating the separation.

## Multisig requirement for the admin identity

- The Mainnet `MAINNET_ADMIN_SOURCE` must resolve to a Stellar multisig
  account (native multi-signature via `set_options` thresholds) or a
  hardware-wallet-backed signer (e.g. Ledger via Stellar CLI's hardware
  wallet support). A single software key is not acceptable for admin on
  Mainnet.
- Recommended default quorum: **2-of-3** signers, with signers on separate
  devices and, ideally, separate people. The maintainers approve the final
  quorum and signer set before the first Mainnet deploy; record that
  approval in the release sign-off (`docs/security/AUDIT_PROCESS.md`).
- The Stellar CLI transparently prompts/co-signs for a configured multisig
  source (see `README.md` → "Multisig / DAuthorization"); no code change is
  required to use one, only correct `stellar keys`/network configuration by
  whoever holds the signing hardware.
- Before the quorum is trusted for a real deploy, run one **test
  transaction** (e.g. a no-op `pause()` + `unpause()` on a fresh Testnet
  deploy) through the actual multisig setup and record that it required the
  expected number of independent signatures.

## Key handling rules

- No private key is ever written to disk in plaintext, sourced inline in a
  shell command, or committed to this repository or CI configuration.
  `deploy-mainnet.sh` and `verify-mainnet.sh` only accept CLI *source
  aliases* (`stellar keys` names) — the actual secret material must be
  injected by a secrets manager (1Password CLI, AWS Secrets Manager,
  HashiCorp Vault, GitHub encrypted secrets, or equivalent) or held on
  hardware for the admin key.
- CI never holds the Mainnet admin key. Mainnet deploy/verify/canary runs
  are executed manually or from a controlled, human-triggered pipeline —
  never on `push`/`pull_request`.

## Rotation on suspected compromise

1. Call `pause()` on `MyToken` from the admin multisig immediately — this
   blocks `mint`, `sell`, `sell_forwarded`, and `mint_forwarded`, which
   covers the entire purchase flow (see
   `docs/operations/MONITORING_AND_INCIDENT_RESPONSE.md`).
2. Do not attempt to `set_marketplace` again on the same token — the
   binding is one-time and cannot be silently retargeted
   (`test_set_marketplace_cannot_retarget`). Recovery is a redeploy, not a
   rebind.
3. Deploy a new `MyToken` + `PromptMarketplace` pair under a newly
   generated admin identity, following the existing "Migración de
   instancias existentes" procedure in `README.md`.
4. Treat any balance migration from the paused contracts as an explicit,
   reviewed, auditable operation — never automatic.
5. Publish the new contract IDs and revoke trust in the old ones in the
   README and any release notes.

## Sign-off

Before the first Mainnet deploy, record in the release sign-off (see
`docs/security/AUDIT_PROCESS.md`):

- Admin account address and quorum/hardware setup used.
- Names/roles of the signers (internal record; not necessarily public).
- Date and result of the test transaction proving the quorum works.
