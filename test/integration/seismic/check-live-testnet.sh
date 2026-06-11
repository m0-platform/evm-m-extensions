#!/usr/bin/env bash
# Read-only status checklist for the live Seismic-testnet USDS deployment (chain 5124).
# Sends NO transactions. PENDING lines are expected until the post-deploy chain
# (configure-extension, set-contract-key — see RUNBOOK.md) has been run.
#
# Usage: bash test/integration/seismic/check-live-testnet.sh   (SEISMIC_TESTNET_RPC_URL to override)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
[ -f "$REPO_ROOT/scripts/seismic-env.sh" ] && source "$REPO_ROOT/scripts/seismic-env.sh" > /dev/null

CAST=$(command -v scast || command -v cast) || { echo "FAIL: need scast or cast on PATH"; exit 1; }

RPC="${SEISMIC_TESTNET_RPC_URL:-https://testnet-1.seismictest.net/rpc}"
EXTENSION=0xb3b2f21f9a6a5d698D9178986Fa4148260B5d018
SWAP_FACILITY=0xB6807116b3B1B321a390594e31ECD6e0076f6278
PORTAL=0xD925C84b55E4e44a53749fF5F2a5A13F63D128fd

ok() { echo "[ok]      $1"; }
pending() { echo "[PENDING] $1"; }
failed() { echo "[FAIL]    $1"; FAILURES=$((FAILURES + 1)); }
FAILURES=0

CHAIN_ID=$("$CAST" chain-id --rpc-url "$RPC" 2> /dev/null) || { echo "FAIL: RPC unreachable: $RPC"; exit 1; }
[ "$CHAIN_ID" = "5124" ] && ok "RPC up, chain id 5124" || failed "unexpected chain id: $CHAIN_ID"

CODE=$("$CAST" code $EXTENSION --rpc-url "$RPC")
[ "$CODE" != "0x" ] && ok "extension proxy has code ($EXTENSION)" || failed "no code at extension proxy"

NAME=$("$CAST" call $EXTENSION "name()(string)" --rpc-url "$RPC")
SYMBOL=$("$CAST" call $EXTENSION "symbol()(string)" --rpc-url "$RPC")
[ "$NAME" = '"Seismic Dollar"' ] && ok "name/symbol: $NAME / $SYMBOL" || failed "unexpected name: $NAME"

SUPPLY=$("$CAST" call $EXTENSION "totalSupply()(uint256)" --rpc-url "$RPC")
ok "totalSupply: $SUPPLY"

PAUSED=$("$CAST" call $EXTENSION "paused()(bool)" --rpc-url "$RPC")
[ "$PAUSED" = "false" ] && ok "not paused" || failed "paused = $PAUSED"

KEY=$("$CAST" call $EXTENSION "contractPublicKey()(bytes)" --rpc-url "$RPC")
if [ "$KEY" != "0x" ]; then
    ok "contract key installed: $KEY"
else
    pending "contract key NOT set (run: make set-contract-key-seismic-testnet) — shielded transfers to registered recipients revert until installed"
fi

APPROVED=$("$CAST" call $SWAP_FACILITY "isApprovedExtension(address)(bool)" $EXTENSION --rpc-url "$RPC")
if [ "$APPROVED" = "true" ]; then
    ok "extension approved on SwapFacility"
else
    pending "extension NOT approved on SwapFacility (run: make configure-extension-seismic-testnet) — wrapping unavailable"
fi

PORTAL_LISTED=$("$CAST" call $EXTENSION "isAllowlisted(address)(bool)" $PORTAL --rpc-url "$RPC")
if [ "$PORTAL_LISTED" = "true" ]; then
    ok "Portal allowlisted"
else
    pending "Portal NOT allowlisted (part of configure-extension)"
fi

# Gate probe: an unsigned read of a third-party balance must revert (signed reads only).
if "$CAST" call $EXTENSION "balanceOf(address)(uint256)" 0x000000000000000000000000000000000000dEaD --rpc-url "$RPC" > /dev/null 2>&1; then
    failed "balanceOf gate: unsigned third-party read DID NOT revert"
else
    ok "balanceOf gate active (unsigned third-party read reverts)"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES check(s) FAILED"
    exit 1
fi
echo "checklist complete (PENDING items await the post-deploy chain — see RUNBOOK.md)"
