# Seismic integration suite

End-to-end evidence that the encrypted-event pipeline works against the **real** Seismic
crypto — no `vm.mockCall`. Three independent legs plus the off-chain decryptor
(`script/decrypt-transfer-event.py`).

## 1. In-process suite — `MYieldToOneSeismic.t.sol`

sforge's seismic EVM implements the precompiles natively (the unit suite mocks them for
determinism, not necessity), so this runs as a plain test suite:

```bash
source scripts/seismic-env.sh
FOUNDRY_NO_MATCH_PATH='no_match_nothing/**' sforge test --match-path 'test/integration/seismic/*'
```

The `FOUNDRY_NO_MATCH_PATH` override is required (same idiom as `make integration`):
`[profile.seismic]` sets `no_match_path = "test/integration/**"` because the
mainnet-fork suites need `eth_getFlaggedStorageAt`; note `*` crosses `/` in foundry
globs, so the replacement glob must not touch `test/integration` at all.

Covers: pinned precompile vectors (executable documentation of 0x65/0x66/0x67/0x68
semantics), ECDH symmetry, real-key shielded `transfer`/`transferFrom`/`approve` with
ciphertext reproduction and in-EVM decryption (0x67), nonce-counter evolution, off-curve
registered-key behavior (deterministic `PrecompileFailed(0x65)` on inbound transfers,
recoverable by re-registering), and the SwapFacility wrap → shielded transfer → unwrap
round-trip. `test_shieldedTransfer_realKeys_recipientDecrypts` logs a complete test
vector for the off-chain decryptor (run with `-vv`).

## 2. Local-node E2E — `run-sanvil-e2e.sh`

Boots a throwaway sanvil, deploys the stack via `SanvilStack.s.sol`, and drives it over
RPC with scast — the same transaction shapes ops/users send on the live network:

```bash
bash test/integration/seismic/run-sanvil-e2e.sh    # SANVIL_PORT=… to override (default 8547)
```

Asserts: `setContractKey` lands as **TxSeismic 0x4A** with the private key absent from
on-chain calldata; signed-read gating (unsigned `balanceOf` reverts, a spoofed `--from`
is rejected by the node itself, a signed stranger read reverts, the signed holder read
returns the balance); shielded transfer via encrypted calldata; off-chain decryption of
the captured `Transfer(bytes)` payload recovering the exact amount; wrap/unwrap through
the real SwapFacility path. Self-contained and idempotent; exits non-zero on any failure.

sanvil quirks worth knowing (discovered empirically):

- Plain-tx **gas estimation runs as an unsigned call** (`msg.sender` zeroed), so
  msg.sender-gated plain sends need `--gas-limit`. TxSeismic estimation is signed.
- `scast send --seismic --json` prefixes the receipt JSON with the ephemeral encryption
  pubkey line.
- Revert data returned by a signed `seismic_call` comes back AES-GCM-encrypted
  (4-byte selector ciphertext + 16-byte tag).

## 3. Live-testnet checklist — `check-live-testnet.sh`

Read-only status of the chain-5124 USDS deployment (sends nothing):

```bash
bash test/integration/seismic/check-live-testnet.sh
```

`[PENDING]` lines are expected until the post-deploy chain has run (`make configure-extension-seismic-testnet`, then `make set-contract-key-seismic-testnet`). Once
the contract key is installed, a live shielded-transfer smoke (register → transfer →
decrypt) can reuse the exact scast/decryptor commands from `run-sanvil-e2e.sh` against
`https://testnet-1.seismictest.net/rpc`.

## Pinned crypto semantics (chain ⇄ off-chain contract)

Verified against seismic-revm/enclave sources and reproduced off-chain; the in-process
suite and `script/decrypt-transfer-event.py --self-test` both assert these vectors.

| Precompile              | Semantics                                                                                                                                                                                                                                                                 |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0x65` ECDH             | in: 32-byte secp256k1 privkey ‖ 33-byte compressed pubkey. out: HKDF-SHA256(salt=∅, info=`"aes-gcm key"`) of the libsecp256k1 shared secret (= SHA-256 of the compressed shared point) — already a derived key, **not** the raw x-coordinate. Errors on off-curve points. |
| `0x68` HKDF             | out: HKDF-SHA256(salt=∅, info=`"seismic_hkdf_105"`, L=32) of the input bytes.                                                                                                                                                                                             |
| `0x66` / `0x67` AES-GCM | in: 32-byte key ‖ 12-byte nonce ‖ payload. AES-256-GCM; ciphertext layout `ct ‖ 16-byte tag`; empty AAD. `0x67` is the tag-checked inverse.                                                                                                                               |

Event key = `0x68(0x65(contractPriv, recipientPub))` — a double HKDF.
Event nonce = first 12 bytes of `keccak256(abi.encode(from, to, nonceCounter))`,
`nonceCounter` pre-incremented per encrypted emit (1-based, shared across Transfer/Approval).
Plaintext = `abi.encode(uint256 amount)`.
