#!/usr/bin/env bash
# Sanvil E2E: deploy -> setContractKey (TxSeismic 0x4A) -> wrap -> shielded transfer ->
# off-chain decrypt -> unwrap, plus signed-read gating checks. Local node only; exits non-zero on failure.
#
# Usage: bash test/integration/seismic/run-sanvil-e2e.sh   (SANVIL_PORT to override, default 8547)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"
source scripts/seismic-env.sh > /dev/null

for bin in sforge sanvil scast python3; do
    command -v "$bin" > /dev/null || { echo "FAIL: $bin not on PATH (run: source scripts/seismic-env.sh && sfoundryup)"; exit 1; }
done

PORT="${SANVIL_PORT:-8547}"
RPC="http://127.0.0.1:$PORT"
DECRYPTOR="$REPO_ROOT/script/decrypt-transfer-event.py"

# sanvil dev accounts: 0 = deployer/admin/alice (every role), 1 = bob (recipient).
ALICE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ALICE=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
BOB_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
BOB=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
# Throwaway contract keypair (local node only — NEVER reuse a fixed key on a public network).
CONTRACT_KEY=0x1111111111111111111111111111111111111111111111111111111111111111

WRAP_AMOUNT=5000000000
TRANSFER_AMOUNT=1234567890

PASS=0
step() { PASS=$((PASS + 1)); echo "[$PASS] $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# NOTE: `scast send --seismic --json` prefixes the receipt JSON with the ephemeral encryption pubkey.
json_get() { python3 -c "
import json, sys
raw = sys.stdin.read()
print(json.loads(raw[raw.index('{'):])$1)"; }

# ---- boot a fresh sanvil ----
pkill -f "sanvil --port $PORT" 2> /dev/null || true
sleep 0.5
sanvil --port "$PORT" --silent > /tmp/sanvil-e2e.log 2>&1 &
SANVIL_PID=$!
trap 'kill $SANVIL_PID 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
    curl -s -X POST "$RPC" -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | grep -q result && break
    sleep 0.5
done
curl -s -X POST "$RPC" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | grep -q result || fail "sanvil did not start (see /tmp/sanvil-e2e.log)"
step "sanvil up on $RPC"

# ---- deploy the stack ----
DEPLOY_OUT=$(PRIVATE_KEY=$ALICE_KEY sforge script test/integration/seismic/SanvilStack.s.sol \
    --rpc-url "$RPC" --broadcast --private-key $ALICE_KEY 2>&1) || { echo "$DEPLOY_OUT" | tail -20; fail "deploy"; }
M_TOKEN=$(echo "$DEPLOY_OUT" | sed -n 's/.*M_TOKEN=\(0x[0-9a-fA-F]*\).*/\1/p' | head -1)
SWAP_FACILITY=$(echo "$DEPLOY_OUT" | sed -n 's/.*SWAP_FACILITY=\(0x[0-9a-fA-F]*\).*/\1/p' | head -1)
EXTENSION=$(echo "$DEPLOY_OUT" | sed -n 's/.*EXTENSION=\(0x[0-9a-fA-F]*\).*/\1/p' | head -1)
[ -n "$EXTENSION" ] || fail "could not parse deployed addresses"
step "stack deployed: extension=$EXTENSION swapFacility=$SWAP_FACILITY mToken=$M_TOKEN"

# ---- derive the contract's compressed pubkey ----
CONTRACT_PUB_UNCOMPRESSED=$(scast wallet public-key --raw-private-key $CONTRACT_KEY)
CONTRACT_PUB=$(python3 -c "
pub = '${CONTRACT_PUB_UNCOMPRESSED#0x}'
x, y = pub[:64], pub[64:]
print(('0x02' if int(y, 16) % 2 == 0 else '0x03') + x)")
step "contract keypair derived: pubkey=$CONTRACT_PUB"

# ---- setContractKey via TxSeismic 0x4A (shielded calldata) ----
RECEIPT=$(scast send "$EXTENSION" "setContractKey(sbytes32,bytes)" $CONTRACT_KEY "$CONTRACT_PUB" \
    --private-key $ALICE_KEY --rpc-url "$RPC" --seismic --json)
[ "$(echo "$RECEIPT" | json_get "['status']")" = "0x1" ] || fail "setContractKey reverted"
[ "$(echo "$RECEIPT" | json_get "['type']")" = "0x4a" ] || fail "setContractKey was not TxSeismic (type 0x4A)"
TXH=$(echo "$RECEIPT" | json_get "['transactionHash']")
TX_INPUT=$(curl -s -X POST "$RPC" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionByHash\",\"params\":[\"$TXH\"]}" | json_get "['result']['input']")
echo "$TX_INPUT" | grep -q "${CONTRACT_KEY#0x}" && fail "private key visible in on-chain calldata"
[ "$(scast call "$EXTENSION" 'contractPublicKey()(bytes)' --rpc-url "$RPC")" = "$CONTRACT_PUB" ] || fail "contractPublicKey mismatch"
step "setContractKey: type 0x4A, calldata shielded, key installed"

# ---- bob registers his real pubkey (plain tx — pubkeys are public) ----
BOB_PUB_UNCOMPRESSED=$(scast wallet public-key --raw-private-key $BOB_KEY)
BOB_PUB=$(python3 -c "
pub = '${BOB_PUB_UNCOMPRESSED#0x}'
x, y = pub[:64], pub[64:]
print(('0x02' if int(y, 16) % 2 == 0 else '0x03') + x)")
scast send "$EXTENSION" "registerPublicKey(bytes)" "$BOB_PUB" --private-key $BOB_KEY --rpc-url "$RPC" > /dev/null
step "bob registered pubkey $BOB_PUB"

# ---- wrap M -> extension (real SwapFacility path) ----
# NOTE: plain-tx gas estimation runs as an unsigned call (msg.sender zeroed) on sanvil, so any
# msg.sender-gated call needs an explicit --gas-limit.
scast send "$M_TOKEN" "setBalanceOf(address,uint256)" $ALICE $WRAP_AMOUNT --private-key $ALICE_KEY --rpc-url "$RPC" > /dev/null
scast send "$M_TOKEN" "approve(address,uint256)" "$SWAP_FACILITY" $WRAP_AMOUNT --private-key $ALICE_KEY --rpc-url "$RPC" > /dev/null
scast send "$SWAP_FACILITY" "swapInM(address,uint256,address)" "$EXTENSION" $WRAP_AMOUNT $ALICE \
    --private-key $ALICE_KEY --rpc-url "$RPC" --gas-limit 1500000 > /dev/null
BALANCE=$(scast call "$EXTENSION" "balanceOf(address)" $ALICE --private-key $ALICE_KEY --rpc-url "$RPC" --seismic)
[ $((BALANCE)) -eq $WRAP_AMOUNT ] || fail "wrap: expected balance $WRAP_AMOUNT, got $((BALANCE))"
step "wrapped $WRAP_AMOUNT via swapInM"

# ---- signed-read gating ----
scast call "$EXTENSION" "balanceOf(address)" $ALICE --rpc-url "$RPC" > /dev/null 2>&1 \
    && fail "unsigned balanceOf did not revert" || true
scast call "$EXTENSION" "balanceOf(address)" $ALICE --from $BOB --rpc-url "$RPC" > /dev/null 2>&1 \
    && fail "unsigned balanceOf with spoofed from did not revert" || true
scast call "$EXTENSION" "balanceOf(address)" $ALICE --private-key $BOB_KEY --rpc-url "$RPC" --seismic > /dev/null 2>&1 \
    && fail "signed balanceOf from stranger did not revert" || true
step "balanceOf gate: unsigned reverts, spoofed-from rejected by node, signed stranger reverts, signed holder reads"

# ---- shielded transfer alice -> bob (TxSeismic; amount inside encrypted calldata) ----
RECEIPT=$(scast send "$EXTENSION" "transfer(address,suint256)" $BOB $TRANSFER_AMOUNT \
    --private-key $ALICE_KEY --rpc-url "$RPC" --seismic --json)
[ "$(echo "$RECEIPT" | json_get "['status']")" = "0x1" ] || fail "shielded transfer reverted"
[ "$(echo "$RECEIPT" | json_get "['type']")" = "0x4a" ] || fail "transfer was not TxSeismic"
TRANSFER_BYTES_TOPIC=$(scast keccak "Transfer(address,address,bytes)")
CIPHERTEXT=$(echo "$RECEIPT" | python3 -c "
import json, sys
raw = sys.stdin.read()
receipt = json.loads(raw[raw.index('{'):])
for log in receipt['logs']:
    if log['topics'][0] == '$TRANSFER_BYTES_TOPIC':
        data = bytes.fromhex(log['data'][2:])
        length = int.from_bytes(data[32:64], 'big')
        print('0x' + data[64:64 + length].hex())
        break
else:
    sys.exit('Transfer(bytes) log not found')")
step "captured encrypted Transfer payload: $CIPHERTEXT"

# ---- off-chain decryption (recipient privkey + contract pubkey only) ----
DECRYPTED=$(python3 "$DECRYPTOR" \
    --privkey $BOB_KEY --peer-pubkey "$CONTRACT_PUB" \
    --from $ALICE --to $BOB --nonce-counter 1 --ciphertext "$CIPHERTEXT")
echo "$DECRYPTED" | grep -q "amount: $TRANSFER_AMOUNT" || fail "decryptor recovered wrong amount: $DECRYPTED"
step "off-chain decrypt recovered exact amount $TRANSFER_AMOUNT"

# ---- unwrap (bob -> M) ----
scast send "$SWAP_FACILITY" "grantRole(bytes32,address)" "$(scast keccak 'M_SWAPPER_ROLE')" $BOB \
    --private-key $ALICE_KEY --rpc-url "$RPC" --gas-limit 500000 > /dev/null
scast send "$EXTENSION" "approve(address,uint256)" "$SWAP_FACILITY" $TRANSFER_AMOUNT \
    --private-key $BOB_KEY --rpc-url "$RPC" --gas-limit 500000 > /dev/null
scast send "$SWAP_FACILITY" "swapOutM(address,uint256,address)" "$EXTENSION" $TRANSFER_AMOUNT $BOB \
    --private-key $BOB_KEY --rpc-url "$RPC" --gas-limit 1500000 > /dev/null
M_BALANCE=$(scast call "$M_TOKEN" "balanceOf(address)(uint256)" $BOB --rpc-url "$RPC")
[ "${M_BALANCE%% *}" = "$TRANSFER_AMOUNT" ] || fail "unwrap: expected $TRANSFER_AMOUNT M, got $M_BALANCE"
BOB_EXT_BALANCE=$(scast call "$EXTENSION" "balanceOf(address)" $BOB --private-key $BOB_KEY --rpc-url "$RPC" --seismic)
[ $((BOB_EXT_BALANCE)) -eq 0 ] || fail "unwrap: bob extension balance not zero"
step "unwrapped $TRANSFER_AMOUNT back to M"

echo
echo "ALL E2E CHECKS PASSED ($PASS steps)"
