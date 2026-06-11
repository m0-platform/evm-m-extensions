# Encrypted Transfer Events — Review

Scope: commits `9ba313e` (implementation) and `c14ec9c` (tests + harness + seismic-profile exclusion bump) on branch `feat/seismic`, PR #116. Review was performed read-only; nothing was modified, committed, or pushed.

## Verdict

Ship with caveats.

The six required check items all PASS against the spec at `/Users/uyoyou.uwuseba/.claude/plans/golden-snuggling-clover.md`. The implementation matches the locked design table line-for-line: append-only storage layout (slots 5–8), distinct `Transfer` topic0s, monotonic nonce with a free SSTORE on the unregistered fallback, one-shot admin-gated `setContractKey` with the `TxSeismic 0x4A` requirement called out in NatSpec, and no rerouting of `_mint` / `_burn` / native infra `transferFrom(uint256)` / forced transfers through the encrypted overload. Tests under `FOUNDRY_PROFILE=seismic` are green (369 passed, 0 failed) and the dual-emit regression guards specifically lock the routing invariant.

The caveats are non-blocking and are surfaced under **Additional findings** below — most importantly, that the `_emitEncryptedTransfer` ordering interacts subtly with the existing zero-amount short-circuit in `_shieldedTransfer`, which surfaces an extra emit + nonce burn for a zero-amount transfer to a registered recipient. That's an event-shape / gas observation, not a security issue.

## Six Required Check Items

### 1. Storage-slot append safety — PASS

- **Citation:** `src/projects/yieldToOne/MYieldToOne.sol:17-57`; baseline at `git show 172cb30:src/projects/yieldToOne/MYieldToOne.sol`.
- Slots 0–4 are byte-for-byte unchanged in type and order: `uint256 totalSupply` (0), `address yieldRecipient` (1), `mapping(address => suint256) balanceOf` (2), `mapping(address => mapping(address => suint256)) shieldedAllowance` (3), `mapping(address => bool) allowlist` (4). The only diff against `172cb30` on those five lines is the addition of explanatory `// slot N —` comments; the declared types and ordering are identical (verified via `git diff 172cb30 9ba313e -- src/projects/yieldToOne/MYieldToOne.sol`).
- Slots 5–8 are strictly appended after slot 4. No slot was inserted between existing slots.
- The namespace constant `_M_YIELD_TO_ONE_STORAGE_LOCATION = 0xee2f6fc7e2e5879b17985791e0d12536cba689bda43c77b8911497248f4af100` at line 57 is unchanged from the baseline. The ERC-7201 derivation comment above it (`keccak256(abi.encode(uint256(keccak256("M0.storage.MYieldToOne")) - 1)) & ~bytes32(uint256(0xff))`) is also unchanged.
- This is upgrade-safe under the OZ UUPS pattern as required by the spec.

### 2. `Transfer` event topic0 separation — PASS

- **Citation:** `src/projects/yieldToOne/interfaces/IMYieldToOne.sol:47` (`event Transfer(address indexed from, address indexed to, bytes encryptedAmount);`); inherited `IERC20.Transfer(address,address,uint256)` from `lib/common/src/interfaces/IERC20.sol`.
- **Distinct topic0s, confirmed by computation:**
  - `keccak256("Transfer(address,address,uint256)") = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef`
  - `keccak256("Transfer(address,address,bytes)") = 0xd7e0e76a339fe8e46c3a779742dd7c08951ec9048bb513b9e5749820fc3a6fb7`
  - The tests at `test/unit/projects/yieldToOne/MYieldToOne.t.sol:1277-1278, 1328-1329, 1425-1426, 1475-1476, 1531-1532` derive these literally and assert presence/absence of each in the recorded logs of every dual-emit case, which is the strongest possible mechanical guard.
- **Emit sites enumerated** (all `emit Transfer(...)` in the yieldToOne paths):
  - `MYieldToOne.sol:454` — `_mint`, `emit Transfer(address(0), recipient, amount)`. `amount` is `uint256` → resolves to the inherited plaintext overload. ✓
  - `MYieldToOne.sol:471` — `_burn`, `emit Transfer(account, address(0), amount)`. `amount` is `uint256` → plaintext overload. ✓
  - `MYieldToOne.sol:545` — `_shieldedTransfer` plaintext branch, `emit Transfer(sender, recipient, amount_)` where `amount_` is `uint256`. Reached only when `encryptEmit == false` (i.e. only from native infra `transferFrom(uint256)` at line 276). ✓
  - `MYieldToOne.sol:586` — `_emitEncryptedTransfer` unregistered fallback, `emit Transfer(from, to, bytes(""))`. Third arg is `bytes` → resolves to the new bytes overload. ✓
  - `MYieldToOne.sol:603` — `_emitEncryptedTransfer` encrypted path, `emit Transfer(from, to, ciphertext)` where `ciphertext` is `bytes memory` → bytes overload. ✓
  - `MYieldToOneForcedTransfer.sol:128` — `_forceTransfer`, `emit Transfer(frozenAccount, recipient, amount)` where `amount` is `uint256` → plaintext overload. ✓ The corresponding test at `test/unit/projects/yieldToOne/MYieldToOneForcedTransfer.t.sol:323, 369` uses explicit `emit IERC20.Transfer(...)` qualification, so even after the bytes overload was added to the contract scope, the test's emit signature still resolves to the plaintext one.
  - `MExtension.sol:249` — `_transfer` plaintext emit. **Unreachable** in MYieldToOne: the inherited `transfer(address,uint256)` is overridden to revert `UseShieldedTransfer` (line 259), and the inherited `transferFrom(address,address,uint256)` is overridden to call `_spendAllowanceAndTransfer` → `_shieldedTransfer`, never `_transfer`. No code path on MYieldToOne reaches it.
- `_shieldedApprove` at line 660 emits `Approval` only (line 667), never `Transfer` — confirmed untouched and orthogonal to this work.

### 3. `encryptedEventNonce` counter monotonicity — PASS

- **Citation:** `src/projects/yieldToOne/MYieldToOne.sol:596` (`uint256 n = ++$.encryptedEventNonce;`).
- The pre-increment fires **only on the encrypted-ciphertext branch**, after both early-returns:
  - Line 585 — unregistered-recipient empty-fallback `return;` runs **before** line 596, so an empty-bytes emit does **not** burn a nonce. ✓ This matches the spec ("the unregistered-recipient empty-fallback branch should NOT increment").
  - Line 592 — `ContractKeyNotSet` revert runs before line 596; a reverting tx burns no nonce. ✓
  - Line 596 itself is the only write site for `encryptedEventNonce` — no other path in the contract touches the counter. The pre-increment guarantees the first emitted nonce uses value `1`, so the counter is strictly monotonic increasing (1, 2, 3, …) and no two encrypted emits ever reuse a nonce under the same AES-GCM key.
- The test guard at `test/unit/projects/yieldToOne/MYieldToOne.t.sol:1265, 1273` (`shieldedTransfer_registeredRecipient_emitsBytesPayload`) asserts the counter is 0 before and exactly 1 after a single encrypted emit; the unregistered-fallback test at line 1373 (`shieldedTransfer_unregisteredRecipient_emitsEmptyBytesAndSucceeds`) asserts the counter stays at 0; the regression test at line 1422 (`nativeTransferFrom_registeredRecipient_emitsPlaintextOnly`) asserts the counter stays at 0 when the infra path runs even though the recipient has a registered pubkey. The mint/burn regression tests (lines 1472, 1528) likewise assert no counter change.
- The pre-increment + per-tuple keccak nonce combination is the deliberate departure from the tutorial's collision-prone `block.number` formulation and is filed in `docs/seismic-question-encrypted-events-ux.md` §1 for Seismic confirmation.

### 4. `setContractKey` gating + NatSpec — PASS

- **Citation:** `src/projects/yieldToOne/MYieldToOne.sol:186-213` (implementation) and `src/projects/yieldToOne/interfaces/IMYieldToOne.sol:180-197` (interface NatSpec).
- **(a) Role gate** — `onlyRole(DEFAULT_ADMIN_ROLE)` modifier at line 199. Test guard: `test/unit/projects/yieldToOne/MYieldToOne.t.sol:1148-1155` asserts a non-admin caller reverts with `AccessControlUnauthorizedAccount`. ✓
- **(b) One-shot guard** — `if (bytes32($.contractPrivateKey) != bytes32(0)) revert ContractKeyAlreadySet();` at line 207. Test guard: `test_setContractKey_oneShot` at line 1157-1166 confirms the second call reverts. ✓
- **(c) Length validation** — `if (publicKey.length != 33) revert InvalidPublicKeyLength();` at line 200, with NatSpec at `IMYieldToOne.sol:189-190` stating "Reverts `InvalidPublicKeyLength` unless `publicKey.length == 33` (compressed secp256k1 encoding)". Test guards at lines 1168-1184 cover length 32 and length 34. ✓
- **(d) `TxSeismic 0x4A` operational-requirement NatSpec** — explicitly called out at two places:
  - On the implementation, lines 187-191:
    > "OPERATIONAL REQUIREMENT (not enforceable from Solidity): the admin MUST send this call as a Seismic `TxSeismic` transaction (type `0x4A`), so the private key is encrypted in the calldata layer. If sent as a plain transaction the private key is recoverable from the mempool / public tx history, defeating the purpose of the shielded slot."
  - On the interface, lines 185-188:
    > "MUST be sent as a Seismic `TxSeismic` transaction (type `0x4A`) so the private key is encrypted in calldata. This is an operational requirement that cannot be enforced from Solidity — see `docs/seismic-question-encrypted-events-ux.md`."
  Both sites correctly disclaim that this is **not** enforceable on-chain. ✓

### 5. Unregistered-recipient fallback — PASS

- **Citation:** `src/projects/yieldToOne/MYieldToOne.sol:579-588`.
- The fallback branch at lines 581-588 fires **before** the contract-key check at line 592:
  ```solidity
  bytes memory pubKey = $.publicKeys[to];
  if (pubKey.length == 0) {
      emit Transfer(from, to, bytes(""));
      return;
  }
  if (bytes32($.contractPrivateKey) == bytes32(0)) revert ContractKeyNotSet();
  ```
- This means a transfer to an unregistered recipient succeeds even when the contract keypair has not yet been installed by the admin. This is exactly what the spec requires ("Otherwise an unregistered-recipient transfer would also revert `ContractKeyNotSet` if the contract is mid-setup, which would break inflow before the admin completes the keypair init"). The test at `test/unit/projects/yieldToOne/MYieldToOne.t.sol:1354-1378` (`shieldedTransfer_unregisteredRecipient_emitsEmptyBytesAndSucceeds`) installs the contract key first and skips the precompile mocks — proving the fallback path neither reads the private key nor calls any precompile. The complementary test at line 1382-1394 (`shieldedTransfer_contractKeyNotSet_reverts`) registers a recipient pubkey but leaves the contract key unset, isolating the `ContractKeyNotSet` branch.
- The empty-ciphertext fallback's UX is filed for Seismic's input in `docs/seismic-question-encrypted-events-ux.md` and is explicitly out of scope per the briefing.

### 6. No accidental cross-emit rerouting — PASS

Per-site analysis (full enumeration in §2 above, restated here against the design):

| Site | File:Line | Overload emitted | Matches design? |
|---|---|---|---|
| `_mint` | `MYieldToOne.sol:454` | `Transfer(uint256)` — plaintext | ✓ public bridge amount |
| `_burn` | `MYieldToOne.sol:471` | `Transfer(uint256)` — plaintext | ✓ public bridge amount |
| `_shieldedTransfer` (plaintext branch) | `MYieldToOne.sol:545` | `Transfer(uint256)` — plaintext | ✓ reached only with `encryptEmit=false` from infra `transferFrom(uint256)` (line 276) |
| `_shieldedTransfer` → `_emitEncryptedTransfer` (fallback) | `MYieldToOne.sol:586` | `Transfer(bytes)` — empty | ✓ unregistered recipient on user-to-user path |
| `_shieldedTransfer` → `_emitEncryptedTransfer` (encrypted) | `MYieldToOne.sol:603` | `Transfer(bytes)` — ciphertext | ✓ user-to-user with registered recipient |
| `_shieldedApprove` | `MYieldToOne.sol:667` | `Approval` only — no Transfer | ✓ orthogonal, out of scope per spec |
| `MYieldToOneForcedTransfer._forceTransfer` | `MYieldToOneForcedTransfer.sol:128` | `Transfer(uint256)` — plaintext | ✓ operator-privileged, plaintext by design |
| `MExtension._transfer` (parent) | `MExtension.sol:249` | unreachable on MYieldToOne | ✓ overridden entry points block both `transfer(uint256)` and `transferFrom(uint256)` from reaching it |

The dual-emit regression tests at `test/unit/projects/yieldToOne/MYieldToOne.t.sol:1398, 1451, 1500` (`nativeTransferFrom_registeredRecipient_emitsPlaintextOnly`, `test_mint_emitsPlaintextOnly`, `test_burn_emitsPlaintextOnly`) install a contract key and register pubkeys for the relevant addresses to specifically probe for accidental encrypted-bytes emission. Each test asserts `foundBytes == false` AND `foundPlaintext == true` AND the counter is unchanged — three independent witnesses that the routing is correct.

## Additional Findings

### Warning

#### W-1: Zero-amount transfer to a registered recipient burns a nonce and emits a ciphertext

- **File:** `src/projects/yieldToOne/MYieldToOne.sol:536-555` (and `:579-604`).
- **Issue:** `_shieldedTransfer` calls `_emitEncryptedTransfer` **before** the `if (amount_ == 0) return;` short-circuit:
  ```solidity
  if (encryptEmit) {
      _emitEncryptedTransfer(sender, recipient, amount);  // line 543 — runs first
  } else {
      emit Transfer(sender, recipient, amount_);
  }
  if (amount_ == 0) return;                               // line 548 — checked second
  ```
  For a user-to-user transfer of `suint256(0)` where the recipient has a registered pubkey, the encrypted-emit pipeline runs end-to-end: it pre-increments `encryptedEventNonce` (one SSTORE), executes three precompile staticcalls (ECDH, HKDF, AES-GCM-encrypt), and emits a `Transfer(bytes)` ciphertext of the zero amount. Then control returns to line 548 and short-circuits before `_update`.
  This matches what the existing plaintext path did pre-refactor (it also emitted on `amount_ == 0`), so the **behavior shape is preserved** (a zero-amount transfer is still observable as an emit and still succeeds), and the spec explicitly calls out the "existing zero-amount-still-emits semantic" as preserved. The new wrinkle is that the encrypted path now does real cryptographic work for a meaningless emit, and burns a counter slot that could collide-detect a future, real transfer. There is no security loss — the nonce remains unique, so a real subsequent transfer is still safely encryptable — but it is gas waste and arguably noise in the log stream.
- **Recommendation (non-blocking):** if Seismic confirms in the question-doc round that the counter strategy is final, consider hoisting the `if (amount_ == 0) { emit Transfer(...); return; }` short-circuit for the encrypted branch above the precompile calls — emit a fixed `bytes("")` (or a distinguished zero-ciphertext sentinel, if you want to keep the empty-fallback semantic meaningful) and skip the precompile calls. Out of scope to fix in this PR; flag for Seismic's review.

#### W-2: `_emitEncryptedTransfer` is positioned in a new section but documents three internal precompile wrappers underneath, which slightly breaks the M0 section-ordering convention

- **File:** `src/projects/yieldToOne/MYieldToOne.sol:557-652`.
- The new section header `/* ============ Encrypted Transfer Event Pipeline ============ */` is inserted between `_shieldedTransfer` (Internal Interactive Functions block) and `_shieldedApprove` (which is also Internal Interactive). Per the M0 EVM section-ordering convention (Events → Custom Errors → Variables → Interactive Functions → View/Pure Functions → Internal sections), all four internal functions should sit together under the same Internal Interactive header. The current arrangement scatters internals across two adjacent labelled sections (`Encrypted Transfer Event Pipeline` then a return to `_shieldedApprove` without a section break of its own).
- **Recommendation (non-blocking):** either fold the four encrypted-pipeline internals back under `Internal Interactive Functions`, or re-label the existing `Internal Interactive Functions` header to be the only one and rename the encrypted block to a sub-comment. Cosmetic.

### Note

#### N-1: `_contractPublicKey` leading-underscore field is a deliberate workaround for the external view name collision

- **File:** `src/projects/yieldToOne/MYieldToOne.sol:43` (storage field) and `:378` (external view).
- This is called out in the briefing as an explicit design choice and the briefing says do not flag — recording here only because a passing solhint reviewer who didn't read the briefing would. No action.

#### N-2: `setContractKey` writes the public key into storage even though `contractPublicKey()` could derive it on the fly from the shielded private key

- **File:** `src/projects/yieldToOne/MYieldToOne.sol:209-210`.
- Storing `_contractPublicKey` separately doubles the storage footprint of the keypair but lets `contractPublicKey()` be a constant-gas plain `bytes memory` read with no precompile call — desirable for off-chain decryption clients. Storing it also makes the `ContractKeySet(publicKey)` event payload trivially the same value the view returns later, which is the most useful indexer invariant. Reasonable tradeoff; flagging only because a curious reviewer might ask.

#### N-3: The shielded `setContractKey` private-key parameter is taken as a function argument typed `sbytes32`, then assigned directly into shielded storage at line 209 without intermediate processing

- **File:** `src/projects/yieldToOne/MYieldToOne.sol:196-209`.
- This is the only correct way to do it — the `sbytes32` ABI-boundary type is exactly what triggers the `TxSeismic 0x4A` flagged-calldata path, and not casting the type out preserves the shielded semantic end-to-end. Recording only to flag for a future reviewer that the design assumes Seismic confirms the open question §2 in `docs/seismic-question-encrypted-events-ux.md` (whether `sbytes32(0)` is the canonical unset sentinel and the one-shot guard's `bytes32(...)` cast reads cleanly out of shielded storage). If Seismic rejects this pattern the one-shot guard will need to be rewritten — but that is exactly what the briefing says is out of scope for this review.

#### N-4: The seismic-profile `no_match_path` widened to skip all of `test/integration/**` and `test/unit/projects/JMIExtension.t.sol`

- **File:** `foundry.toml:51`.
- The diff is a strict superset of the old exclusion (which already skipped four specific integration files) — the new glob skips the entire integration tree plus the JMI unit suite. The commit message documents the rationale (mainnet fork has no `eth_getFlaggedStorageAt`; JMI is oversize under ssolc+mercury and was written against the unshielded `balanceOf` surface). Both reasons are listed in the briefing as known and out of scope. No action.

## What I Did Not Check

Per the briefing, the following were **explicitly out of scope** and are not flagged even though they appear in the implementation:

- **Precompile addresses (`0x65`, `0x66`, `0x68`) and `abi.encodePacked` input layouts** — `MYieldToOne.sol:617, 630, 647-649`. Open question §3 in `docs/seismic-question-encrypted-events-ux.md` (canonical tutorial addresses; Seismic will validate).
- **Nonce strategy** (monotonic counter vs tutorial's `block.number`) — `MYieldToOne.sol:594-600`. Open question §1.
- **`sbytes32` zero-sentinel comparison correctness** — `MYieldToOne.sol:207, 592`. Open question §2.
- **UX of the empty-ciphertext fallback for unregistered recipients** — `MYieldToOne.sol:585-588`. Question already filed at `docs/seismic-question-encrypted-events-ux.md`.
- **`TxSeismic 0x4A` requirement on `setContractKey`** — confirmed by the user as a Solidity-unenforceable operational constraint; documented in NatSpec at `MYieldToOne.sol:187-191`.
- **Approvals staying plaintext** (`_shieldedApprove`) — explicit design decision per `docs/seismic-src20-flow-diagrams.md` D5.
- **Forced transfers staying plaintext** (`MYieldToOneForcedTransfer._forceTransfer`) — explicit design decision; operator-auditable amount by design.
- **Mint/burn staying plaintext** — bridge amounts public via calldata; explicit design decision.
- **JMI bytecode-size overrun under the seismic profile** — known; JMI is not a Seismic deployment target.
- **Solhint warnings on `_contractPublicKey` leading underscore** — deliberate to avoid colliding with the external view name.
- **AES-GCM tag handling in the precompile output** — part of open question §3.
- **On-chain validation of the precompile outputs (e.g. ciphertext length sanity)** — relies on the open question being settled.
- **Off-chain decryption (ECDH + HKDF + AES-GCM-decrypt against the emitted bytes)** — devnet-only verification per the spec's §5 verification step; cannot run locally under sforge.

## Build / Test Status

Suite under `FOUNDRY_PROFILE=seismic`: 369 passed, 0 failed (verified at the head of `feat/seismic`; test commit `c14ec9c` commit message also reports the same number).
