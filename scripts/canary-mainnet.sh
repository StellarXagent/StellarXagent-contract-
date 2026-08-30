#!/usr/bin/env bash
# =============================================================================
# AgentVerse — Mainnet Canary Purchase
# =============================================================================
# Runs ONE small, capped, REAL-VALUE purchase against already-deployed and
# verified Mainnet contracts to prove that settlement, delivery (has_access),
# and payment (burn) accounting behave as approved, before opening the
# marketplace to the public. Required by
# https://github.com/Stellar-AgentVerse/Smart-contracts/issues/26.
#
# SECURITY NOTICE — THIS SCRIPT MOVES REAL FUNDS:
#   - It refuses to run above CANARY_MAX_PRICE (hard cap).
#   - It refuses to run unless CANARY_CONFIRM is the exact required phrase.
#   - It runs scripts/verify-mainnet.sh first and refuses to proceed if that
#     fails — never canary against contracts that haven't been re-verified.
#   - It never accepts inline private keys, only Stellar CLI source aliases.
#
# Required environment variables:
#   MAINNET_TOKEN_ID          Deployed MyToken contract ID
#   MAINNET_MARKETPLACE_ID    Deployed PromptMarketplace contract ID
#   MAINNET_ADMIN_ADDR        Expected admin/owner address (passed through to
#                             scripts/verify-mainnet.sh)
#   CANARY_ADMIN_SOURCE       Stellar CLI source for the admin account
#                             (registers the canary prompt)
#   CANARY_BUYER_SOURCE       Stellar CLI source for the canary buyer account
#   CANARY_BUYER_ADDR         Public address matching CANARY_BUYER_SOURCE —
#                             must already hold at least CANARY_PRICE tokens
#   CANARY_CONFIRM            Must be exactly: I_UNDERSTAND_THIS_USES_REAL_FUNDS
#
# Optional environment variables:
#   CANARY_PROMPT_ID    Canary prompt id (default: "mainnet-canary-<date>")
#   CANARY_PRICE        Purchase price in token base units (default: 1)
#   CANARY_MAX_PRICE    Hard cap on CANARY_PRICE (default: 10)
#   CANARY_CLEANUP      If "true", admin removes the canary prompt after a
#                       successful purchase (default: false — leaves it as a
#                       visible on-chain record of the canary)
#   CANARY_OUT_DIR      Directory for the JSON report (default: ./deploy-artifacts)
#
# Example:
#   MAINNET_TOKEN_ID="C..." MAINNET_MARKETPLACE_ID="C..." MAINNET_ADMIN_ADDR="G..." \
#   CANARY_ADMIN_SOURCE=admin CANARY_BUYER_SOURCE=canary-buyer \
#   CANARY_BUYER_ADDR="G..." \
#   CANARY_CONFIRM="I_UNDERSTAND_THIS_USES_REAL_FUNDS" \
#   bash scripts/canary-mainnet.sh
# =============================================================================

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
NETWORK="mainnet"
REQUIRED_CONFIRM="I_UNDERSTAND_THIS_USES_REAL_FUNDS"

TOKEN_ID="${MAINNET_TOKEN_ID:-}"
MKT_ID="${MAINNET_MARKETPLACE_ID:-}"
ADMIN_ADDR="${MAINNET_ADMIN_ADDR:-}"

CANARY_PROMPT_ID="${CANARY_PROMPT_ID:-mainnet-canary-$(date -u +%Y%m%d)}"
CANARY_PRICE="${CANARY_PRICE:-1}"
CANARY_MAX_PRICE="${CANARY_MAX_PRICE:-10}"
CANARY_CLEANUP="${CANARY_CLEANUP:-false}"
OUT_DIR="${CANARY_OUT_DIR:-./deploy-artifacts}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helpers ─────────────────────────────────────────────────────────────────

log_section() { echo ""; echo "=== $1 ==="; }
log_info()    { echo "  ℹ️  $*"; }
log_ok()      { echo "  ✅ $*"; }
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

# ── Pre-flight: safety gates ─────────────────────────────────────────────────

log_section "Mainnet Canary Purchase — Safety Gates"

require_cmd stellar

require_env MAINNET_TOKEN_ID
require_env MAINNET_MARKETPLACE_ID
require_env MAINNET_ADMIN_ADDR
require_env CANARY_ADMIN_SOURCE
require_env CANARY_BUYER_SOURCE
require_env CANARY_BUYER_ADDR
require_env CANARY_CONFIRM

if [[ "$CANARY_CONFIRM" != "$REQUIRED_CONFIRM" ]]; then
  fail "CANARY_CONFIRM must be exactly '${REQUIRED_CONFIRM}'. Refusing to move real funds without explicit confirmation."
fi

if ! [[ "$CANARY_PRICE" =~ ^[0-9]+$ ]] || ! [[ "$CANARY_MAX_PRICE" =~ ^[0-9]+$ ]]; then
  fail "CANARY_PRICE and CANARY_MAX_PRICE must be non-negative integers."
fi

if (( CANARY_PRICE > CANARY_MAX_PRICE )); then
  fail "CANARY_PRICE (${CANARY_PRICE}) exceeds CANARY_MAX_PRICE (${CANARY_MAX_PRICE}). This is a hard cap — lower the price or raise the cap deliberately."
fi

log_ok "Safety gates passed: capped price (${CANARY_PRICE} <= ${CANARY_MAX_PRICE}), explicit confirmation provided"

# ── Pre-flight: re-verify the deployed contracts ────────────────────────────

log_section "Re-Verifying Deployed Contracts"
log_info "Running scripts/verify-mainnet.sh before touching real funds..."

MAINNET_TOKEN_ID="$TOKEN_ID" \
MAINNET_MARKETPLACE_ID="$MKT_ID" \
MAINNET_ADMIN_ADDR="$ADMIN_ADDR" \
bash "${SCRIPT_DIR}/verify-mainnet.sh" || fail "verify-mainnet.sh failed — refusing to canary against unverified contracts."

log_ok "Deployed contracts re-verified"

# ── Record pre-purchase state ───────────────────────────────────────────────

log_section "Pre-Purchase State"

BUYER_BALANCE_BEFORE=$(stellar_invoke "$TOKEN_ID" "$CANARY_ADMIN_SOURCE" balance --account "$CANARY_BUYER_ADDR")
SUPPLY_BEFORE=$(stellar_invoke "$TOKEN_ID" "$CANARY_ADMIN_SOURCE" total_supply)

if (( BUYER_BALANCE_BEFORE < CANARY_PRICE )); then
  fail "Buyer balance (${BUYER_BALANCE_BEFORE}) is lower than CANARY_PRICE (${CANARY_PRICE}). Fund the canary buyer account first."
fi

log_info "Buyer balance before: ${BUYER_BALANCE_BEFORE}"
log_info "Token total_supply before: ${SUPPLY_BEFORE}"

# ── Register (idempotent) and purchase the canary prompt ───────────────────

log_section "Canary Purchase"

EXISTING_PRICE=""
if EXISTING_PRICE=$(stellar_invoke "$MKT_ID" "$CANARY_ADMIN_SOURCE" get_price --prompt_id "$CANARY_PROMPT_ID" 2>/dev/null); then
  log_info "Canary prompt '${CANARY_PROMPT_ID}' already registered at price ${EXISTING_PRICE}"
  if [[ "$EXISTING_PRICE" != "$CANARY_PRICE" ]]; then
    fail "Existing canary prompt price (${EXISTING_PRICE}) does not match CANARY_PRICE (${CANARY_PRICE}). Use a different CANARY_PROMPT_ID or reconcile the price manually."
  fi
else
  stellar_invoke_send "$MKT_ID" "$CANARY_ADMIN_SOURCE" \
    register_prompt --prompt_id "$CANARY_PROMPT_ID" --price "$CANARY_PRICE" --owner "$ADMIN_ADDR" --content_uri "ipfs://mainnet-canary"
  log_ok "Canary prompt registered: ${CANARY_PROMPT_ID} @ ${CANARY_PRICE}"
fi

stellar_invoke_send "$MKT_ID" "$CANARY_BUYER_SOURCE" \
  buy_prompt --buyer "$CANARY_BUYER_ADDR" --prompt_id "$CANARY_PROMPT_ID"
log_ok "Canary purchase submitted"

# ── Verify settlement, delivery, reconciliation ─────────────────────────────

log_section "Post-Purchase Verification"

HAS_ACCESS=$(stellar_invoke "$MKT_ID" "$CANARY_ADMIN_SOURCE" has_access --user "$CANARY_BUYER_ADDR" --prompt_id "$CANARY_PROMPT_ID")
[[ "$HAS_ACCESS" == "true" ]] || fail "Delivery check failed: has_access expected true, got ${HAS_ACCESS}"
log_ok "Delivery confirmed: has_access=true"

BUYER_BALANCE_AFTER=$(stellar_invoke "$TOKEN_ID" "$CANARY_ADMIN_SOURCE" balance --account "$CANARY_BUYER_ADDR")
EXPECTED_BALANCE_AFTER=$((BUYER_BALANCE_BEFORE - CANARY_PRICE))
if [[ "$BUYER_BALANCE_AFTER" != "$EXPECTED_BALANCE_AFTER" ]]; then
  fail "Payment reconciliation failed: expected buyer balance ${EXPECTED_BALANCE_AFTER}, got ${BUYER_BALANCE_AFTER}"
fi
log_ok "Payment reconciled: buyer balance ${BUYER_BALANCE_BEFORE} -> ${BUYER_BALANCE_AFTER} (-${CANARY_PRICE})"

SUPPLY_AFTER=$(stellar_invoke "$TOKEN_ID" "$CANARY_ADMIN_SOURCE" total_supply)
EXPECTED_SUPPLY_AFTER=$((SUPPLY_BEFORE - CANARY_PRICE))
if [[ "$SUPPLY_AFTER" != "$EXPECTED_SUPPLY_AFTER" ]]; then
  fail "Supply reconciliation failed: expected total_supply ${EXPECTED_SUPPLY_AFTER}, got ${SUPPLY_AFTER}"
fi
log_ok "Supply reconciled: total_supply ${SUPPLY_BEFORE} -> ${SUPPLY_AFTER}"

# ── Optional cleanup ─────────────────────────────────────────────────────────

if [[ "$CANARY_CLEANUP" == "true" ]]; then
  log_section "Cleanup"
  stellar_invoke_send "$MKT_ID" "$CANARY_ADMIN_SOURCE" remove_prompt --prompt_id "$CANARY_PROMPT_ID"
  log_ok "Canary prompt removed"
else
  log_info "CANARY_CLEANUP is not 'true' — leaving the canary prompt on-chain as a visible record."
fi

# ── Report ────────────────────────────────────────────────────────────────

mkdir -p "$OUT_DIR"
REPORT_FILE="${OUT_DIR}/mainnet-canary-report-${TIMESTAMP//:/-}.json"
cat > "$REPORT_FILE" <<EOF
{
  "network": "${NETWORK}",
  "timestamp": "${TIMESTAMP}",
  "token_id": "${TOKEN_ID}",
  "marketplace_id": "${MKT_ID}",
  "canary_prompt_id": "${CANARY_PROMPT_ID}",
  "canary_price": ${CANARY_PRICE},
  "canary_max_price": ${CANARY_MAX_PRICE},
  "buyer": "${CANARY_BUYER_ADDR}",
  "buyer_balance_before": ${BUYER_BALANCE_BEFORE},
  "buyer_balance_after": ${BUYER_BALANCE_AFTER},
  "total_supply_before": ${SUPPLY_BEFORE},
  "total_supply_after": ${SUPPLY_AFTER},
  "checks": {
    "delivery_has_access_ok": true,
    "payment_reconciliation_ok": true,
    "supply_reconciliation_ok": true
  }
}
EOF

log_section "Canary Summary"
cat <<EOF
Network:      ${NETWORK}
Prompt:       ${CANARY_PROMPT_ID} @ ${CANARY_PRICE}
Buyer:        ${CANARY_BUYER_ADDR}
Report:       ${REPORT_FILE}
EOF

log_ok "Mainnet canary purchase settled, reconciled, and delivered correctly."
log_info "Attach this report to the release sign-off (docs/security/MAINNET_RELEASE_CHECKLIST.md)."
