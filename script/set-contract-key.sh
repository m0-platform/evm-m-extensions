#!/usr/bin/env bash
# One-shot install of the extension's encryption keypair via `scast send --seismic`.
# NEVER port this to a .s.sol: sforge script has no --seismic broadcast, so a plain tx
# would publish the contract private key in plaintext calldata forever (setContractKey
# is one-shot; rotation is impossible). Generate a FRESH keypair per derived deployment;
# archive both keys in 1Password — the off-chain copy only grants ops decryption
# (recipients decrypt with their own keys via ECDH symmetry, never the contract key).
# Env: EXTENSION_PROXY, RPC_URL, PRIVATE_KEY (admin). NONINTERACTIVE=1 skips the pause.
set -euo pipefail

: "${EXTENSION_PROXY:?EXTENSION_PROXY is required}"
: "${RPC_URL:?RPC_URL is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"

SCAST="$(dirname "$0")/../.seismic-toolchain/bin/scast"
if [ ! -x "$SCAST" ]; then
    echo "error: scast not found at $SCAST — run: source scripts/seismic-env.sh && sfoundryup" >&2
    exit 1
fi

# Preflight: refuse to overwrite an installed key (the guard on-chain is one-shot too,
# but failing here avoids burning the freshly generated keypair).
existing="$(cast call "$EXTENSION_PROXY" "contractPublicKey()(bytes)" --rpc-url "$RPC_URL")"
if [ "$existing" != "0x" ]; then
    echo "error: contractPublicKey() is already set on $EXTENSION_PROXY: $existing" >&2
    exit 1
fi

# Keygen: fresh secp256k1 keypair; compress the 64-byte pubkey to 33 bytes
# (0x02/0x03 prefix by y parity), which is the format setContractKey stores.
contract_privkey="$(cast wallet new | awk '/Private key:/ { print $3 }')"
uncompressed="$(cast wallet public-key --raw-private-key "$contract_privkey")"
hex="${uncompressed#0x}"
if [ "${#hex}" -ne 128 ]; then
    echo "error: unexpected public key length from cast wallet public-key: $uncompressed" >&2
    exit 1
fi
x="${hex:0:64}"
y="${hex:64:64}"
case "${y: -1}" in
    0 | 2 | 4 | 6 | 8 | a | c | e | A | C | E) prefix=02 ;;
    *) prefix=03 ;;
esac
contract_pubkey="0x${prefix}${x}"

echo "Contract private key:            $contract_privkey"
echo "Contract public key (compressed): $contract_pubkey"
if [ "${NONINTERACTIVE:-0}" != "1" ]; then
    read -rp "Archive BOTH keys in 1Password now, then press enter to continue..." _
fi

"$SCAST" send --seismic "$EXTENSION_PROXY" "setContractKey(sbytes32,bytes)" \
    "$contract_privkey" "$contract_pubkey" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY"

# Postflight: assert the installed key matches what we generated.
after="$(cast call "$EXTENSION_PROXY" "contractPublicKey()(bytes)" --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')"
expected="$(echo "$contract_pubkey" | tr '[:upper:]' '[:lower:]')"
if [ "$after" != "$expected" ]; then
    echo "error: postflight mismatch — contractPublicKey() = $after, expected $expected" >&2
    exit 1
fi

echo "Contract key installed on $EXTENSION_PROXY"
