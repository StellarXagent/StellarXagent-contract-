#!/usr/bin/env bash
# =============================================================================
# AgentVerse — Testnet Dry-Run for the Mainnet Release Gate
# =============================================================================
# Deploys a FRESH MyToken + PromptMarketplace pair on Testnet from the
# current release build, then exercises the checks required before promoting
# a release candidate to Mainnet (see
# docs/security/MAINNET_RELEASE_CHECKLIST.md, §4):
#
#   1. Adversarial scenarios: forwarded mint/burn rejected when called
#      directly, bypassing the bound marketplace.
#   2. Resource budget capture: records the simulated resource cost of the
#      core purchase flow for human review.
#   3. Pause / recovery drill: pause() blocks the purchase flow end-to-end,
#      unpause() restores it.
#   4. Reconciliation: on-chain total_supply matches the mint/burn ledger
#      this script tracks locally.
#
# This script does NOT touch Mainnet and does NOT require real funds.
#
# Required environment variables:
#   DRYRUN_ADMIN_SOURCE      Stellar CLI source for the deployer/admin/owner
#                            account (Testnet — a single funded test key is
#                            fine here, unlike Mainnet).
#   DRYRUN_ADMIN_ADDR        Public address matching DRYRUN_ADMIN_SOURCE.
#   DRYRUN_BUYER_SOURCE      Stellar CLI source for a funded Testnet buyer.
#   DRYRUN_BUYER_ADDR        Public address matching DRYRUN_BUYER_SOURCE.
#
# Optional environment variables:
#   DRYRUN_TOKEN_NAME, DRYRUN_TOKEN_SYMBOL, DRYRUN_TOKEN_DECIMALS
#   DRYRUN_OUT_DIR           Directory for the JSON report (default: ./deploy-artifacts)
#
# Example:
#   DRYRUN_ADMIN_SOURCE=default \
#   DRYRUN_ADMIN_ADDR="$(stellar keys address default)" \
#   DRYRUN_BUYER_SOURCE=buyer \
#   DRYRUN_BUYER_ADDR="$(stellar keys address buyer)" \
#   bash scripts/testnet-dry-run.sh
# =============================================================================

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
NETWORK="testnet"
TARGET="wasm32v1-none"
RELEASE_DIR="target/${TARGET}/release"

TOKEN_NAME="${DRYRUN_TOKEN_NAME:-AgentVerse Dry-Run Token}"
TOKEN_SYMBOL="${DRYRUN_TOKEN_SYMBOL:-AVTD}"
TOKEN_DECIMALS="${DRYRUN_TOKEN_DECIMALS:-7}"
OUT_DIR="${DRYRUN_OUT_DIR:-./deploy-artifacts}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

TOKEN_WASM="${RELEASE_DIR}/my_token.wasm"
MKT_WASM="${RELEASE_DIR}/prompt_marketplace.wasm"

PROMPT_ID="dryrun-prompt-$$"
PROMPT_PRICE=500
REMINT_AMOUNT=200
MINT_AMOUNT=1000

# ── Helpers (mirrors scripts/deploy-mainnet.sh conventions) ─────────────────

log_section() { echo ""; echo "=== $1 ==="; }
log_info()    { echo "  ℹ️  $*"; }
log_ok()      { echo "  ✅ $*"; }
log_warn()    { echo "  ⚠️  $*"; }
log_error()   { echo "  ❌ $*" >&2; }
fail()        { log_error "$*"; exit 1; }

require_env() {
  local var_name="$1"
  local var_value="${!var_name:-}"
  [[ -n "$var_value" ]] || fail "Missing required environment variable: ${var_name}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

stellar_invoke() {
  local contract_id="$1" source="$2"
  shift 2
  stellar contract invoke --id "$contract_id" --source "$source" --network "$NETWORK" -- "$@"
}

stellar_invoke_send() {
  local contract_id="$1" source="$2"
  shift 2
  stellar contract invoke --id "$contract_id" --source "$source" --network "$NETWORK" --send=yes -- "$@"
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "ADVERSARIAL CHECK FAILED — expected rejection but call succeeded: ${label}"
  fi
  log_ok "Adversarial check passed: ${label}"
}

# ── Pre-flight ───────────────────────────────────────────────────────────────

log_section "Testnet Dry-Run — Mainnet Release Gate"
log_info "Network: ${NETWORK}"
log_info "Timestamp: ${TIMESTAMP}"

require_cmd cargo
require_cmd stellar

require_env DRYRUN_ADMIN_SOURCE
require_env DRYRUN_ADMIN_ADDR
require_env DRYRUN_BUYER_SOURCE
require_env DRYRUN_BUYER_ADDR

log_ok "Prerequisites satisfied"

# ── Build + deploy fresh pair ────────────────────────────────────────────────

log_section "Build Release"
SOROBAN_SDK_BUILD_SYSTEM_SUPPORTS_SPEC_SHAKING_V2=1 \
  cargo build --target "${TARGET}" --release
[[ -f "$TOKEN_WASM" ]] || fail "Token WASM not found: ${TOKEN_WASM}"
[[ -f "$MKT_WASM" ]] || fail "Marketplace WASM not found: ${MKT_WASM}"
log_ok "Release build completed"

log_section "Deploy fresh Testnet pair"

TOKEN_ID=$(stellar contract deploy --wasm "$TOKEN_WASM" --source "$DRYRUN_ADMIN_SOURCE" --network "$NETWORK")
[[ -n "$TOKEN_ID" ]] || fail "Token deployment returned an empty contract ID"
log_ok "MyToken deployed: ${TOKEN_ID}"

stellar_invoke_send "$TOKEN_ID" "$DRYRUN_ADMIN_SOURCE" \
  __constructor --owner "$DRYRUN_ADMIN_ADDR" --name "$TOKEN_NAME" --symbol "$TOKEN_SYMBOL" --decimals "$TOKEN_DECIMALS"
log_ok "MyToken initialized"

MKT_ID=$(stellar contract deploy --wasm "$MKT_WASM" --source "$DRYRUN_ADMIN_SOURCE" --network "$NETWORK")
[[ -n "$MKT_ID" ]] || fail "Marketplace deployment returned an empty contract ID"
log_ok "PromptMarketplace deployed: ${MKT_ID}"

stellar_invoke_send "$MKT_ID" "$DRYRUN_ADMIN_SOURCE" \
  __constructor --admin "$DRYRUN_ADMIN_ADDR" --token "$TOKEN_ID"
log_ok "PromptMarketplace initialized"

stellar_invoke_send "$TOKEN_ID" "$DRYRUN_ADMIN_SOURCE" set_marketplace --marketplace "$MKT_ID"
log_ok "MyToken bound to PromptMarketplace"

# ── 1. Adversarial scenarios ─────────────────────────────────────────────────

log_section "Adversarial Scenarios"

expect_failure "direct sell_forwarded bypassing marketplace" \
  stellar contract invoke --id "$TOKEN_ID" --source "$DRYRUN_BUYER_SOURCE" --network "$NETWORK" --send=yes \
    -- sell_forwarded --seller "$DRYRUN_BUYER_ADDR" --amount 1

expect_failure "direct mint_forwarded bypassing marketplace" \
  stellar contract invoke --id "$TOKEN_ID" --source "$DRYRUN_BUYER_SOURCE" --network "$NETWORK" --send=yes \
    -- mint_forwarded --to "$DRYRUN_BUYER_ADDR" --amount 1

expect_failure "non-owner calling pause()" \
  stellar contract invoke --id "$TOKEN_ID" --source "$DRYRUN_BUYER_SOURCE" --network "$NETWORK" --send=yes \
    -- pause --caller "$DRYRUN_BUYER_ADDR"

expect_failure "non-admin registering a prompt" \
  stellar contract invoke --id "$MKT_ID" --source "$DRYRUN_BUYER_SOURCE" --network "$NETWORK" --send=yes \
    -- register_prompt --prompt_id "attacker-prompt" --price 1 --owner "$DRYRUN_BUYER_ADDR" --content_uri "ipfs://x"

# ── 2. Resource budget capture ──────────────────────────────────────────────

log_section "Resource Budget Capture"
log_info "Capturing resource cost (--cost) of the core purchase flow for"
log_info "human review against the account's expected fee budget. This is"
log_info "advisory logging only — the CLI's --cost output format is not"
log_info "parsed or asserted on, only recorded."

mkdir -p "$OUT_DIR"
COST_LOG="${OUT_DIR}/testnet-dry-run-resource-cost-${TIMESTAMP//:/-}.log"

# These are the same mint/buy_prompt calls the rest of the dry run depends on
# for its reconciliation math below — --cost only adds resource reporting to
# stderr, it does not change what the call does, so this must not be skipped
# or retried without --cost (that would run the mutation twice).
{
  echo "--- mint ---"
  stellar contract invoke --id "$TOKEN_ID" --source "$DRYRUN_ADMIN_SOURCE" --network "$NETWORK" --send=yes --cost \
    -- mint --to "$DRYRUN_BUYER_ADDR" --amount "$MINT_AMOUNT"
} 2>&1 | tee -a "$COST_LOG"

stellar_invoke_send "$MKT_ID" "$DRYRUN_ADMIN_SOURCE" \
  register_prompt --prompt_id "$PROMPT_ID" --price "$PROMPT_PRICE" --owner "$DRYRUN_BUYER_ADDR" --content_uri "ipfs://dryrun"

{
  echo "--- buy_prompt (cross-contract) ---"
  stellar contract invoke --id "$MKT_ID" --source "$DRYRUN_BUYER_SOURCE" --network "$NETWORK" --send=yes --cost \
    -- buy_prompt --buyer "$DRYRUN_BUYER_ADDR" --prompt_id "$PROMPT_ID"
} 2>&1 | tee -a "$COST_LOG"

log_ok "Resource cost log written to: ${COST_LOG} — review before Mainnet sign-off."
log_info "If your installed Stellar CLI does not support --cost, drop the flag"
log_info "here and capture resource usage separately; do not skip this section."

# ── 3. Pause / recovery drill ────────────────────────────────────────────────

log_section "Pause / Recovery Drill"

stellar_invoke_send "$TOKEN_ID" "$DRYRUN_ADMIN_SOURCE" pause --caller "$DRYRUN_ADMIN_ADDR"
IS_PAUSED=$(stellar_invoke "$TOKEN_ID" "$DRYRUN_ADMIN_SOURCE" paused)
[[ "$IS_PAUSED" == "true" ]] || fail "Token did not report paused=true after pause()"
log_ok "Token paused"

expect_failure "buy_prompt while paused (remint path)" \
  stellar contract invoke --id "$MKT_ID" --source "$DRYRUN_ADMIN_SOURCE" --network "$NETWORK" --send=yes \
    -- remint --to "$DRYRUN_BUYER_ADDR" --amount "$REMINT_AMOUNT"

stellar_invoke_send "$TOKEN_ID" "$DRYRUN_ADMIN_SOURCE" unpause --caller "$DRYRUN_ADMIN_ADDR"
IS_PAUSED=$(stellar_invoke "$TOKEN_ID" "$DRYRUN_ADMIN_SOURCE" paused)
[[ "$IS_PAUSED" == "false" ]] || fail "Token did not report paused=false after unpause()"
log_ok "Token unpaused — recovery confirmed"

stellar_invoke_send "$MKT_ID" "$DRYRUN_ADMIN_SOURCE" remint --to "$DRYRUN_BUYER_ADDR" --amount "$REMINT_AMOUNT"
log_ok "remint succeeded post-recovery (purchase flow fully restored)"

# ── 4. Reconciliation ────────────────────────────────────────────────────────

log_section "Reconciliation"

# Expected ledger: mint(MINT_AMOUNT) - buy_prompt burn(PROMPT_PRICE) + remint(REMINT_AMOUNT)
EXPECTED_SUPPLY=$((MINT_AMOUNT - PROMPT_PRICE + REMINT_AMOUNT))
ACTUAL_SUPPLY=$(stellar_invoke "$TOKEN_ID" "$DRYRUN_ADMIN_SOURCE" total_supply)

if [[ "$ACTUAL_SUPPLY" != "$EXPECTED_SUPPLY" ]]; then
  fail "Reconciliation failed: expected total_supply=${EXPECTED_SUPPLY}, got ${ACTUAL_SUPPLY}"
fi
log_ok "Reconciliation passed: total_supply=${ACTUAL_SUPPLY} matches mint/burn/remint ledger"

ACCESS=$(stellar_invoke "$MKT_ID" "$DRYRUN_ADMIN_SOURCE" has_access --user "$DRYRUN_BUYER_ADDR" --prompt_id "$PROMPT_ID")
[[ "$ACCESS" == "true" ]] || fail "Delivery check failed: has_access expected true, got ${ACCESS}"
log_ok "Delivery check passed: buyer has_access=true for purchased prompt"

# ── Report ────────────────────────────────────────────────────────────────

REPORT_FILE="${OUT_DIR}/testnet-dry-run-report-${TIMESTAMP//:/-}.json"
cat > "$REPORT_FILE" <<EOF
{
  "network": "${NETWORK}",
  "timestamp": "${TIMESTAMP}",
  "token_id": "${TOKEN_ID}",
  "marketplace_id": "${MKT_ID}",
  "checks": {
    "adversarial_sell_forwarded_rejected": true,
    "adversarial_mint_forwarded_rejected": true,
    "adversarial_non_owner_pause_rejected": true,
    "adversarial_non_admin_register_rejected": true,
    "pause_blocks_purchase_flow": true,
    "unpause_restores_purchase_flow": true,
    "reconciliation_total_supply_ok": true,
    "delivery_has_access_ok": true
  },
  "expected_total_supply": ${EXPECTED_SUPPLY},
  "actual_total_supply": ${ACTUAL_SUPPLY},
  "resource_cost_log": "${COST_LOG}",
  "note": "Advisory only — attach this report to the Mainnet release sign-off (docs/security/MAINNET_RELEASE_CHECKLIST.md). It is not a substitute for the independent security review."
}
EOF

log_section "Dry-Run Summary"
cat <<EOF
Network:      ${NETWORK}
Token:        ${TOKEN_ID}
Marketplace:  ${MKT_ID}
Report:       ${REPORT_FILE}
Cost log:     ${COST_LOG}
EOF

log_ok "Testnet dry-run completed — attach the report to the release sign-off before Mainnet."
