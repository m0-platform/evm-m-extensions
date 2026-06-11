# Audit Scope — Seismic MYieldToOne (shielded SRC-20)

> Standalone branch for the Seismic deployment; never merges to `main`. Toolchain pins and
> platform trust assumptions: [TOOLCHAIN.md](TOOLCHAIN.md). Prior-audit coverage:
> [audits/README.md](audits/README.md).

## Frozen commit

- **Commit / tag: TODO** — tag the freeze commit (proposed: `audit/seismic-v1`) once the
  pre-audit fixes land. Until then, branch tip of `feat/seismic` is the moving reference.
- Merge-base with `main`: `87a2f42` (last commit covered by the prior audits and the last
  clean slither baseline).

## In scope

| Path | Why |
| ---- | --- |
| `src/projects/yieldToOne/MYieldToOne.sol` | Shielded rewrite: `suint256` balances/allowances, gated reads, shielded SRC-20 overloads, infra allowlist, encrypted events |
| `src/projects/yieldToOne/MYieldToOneForcedTransfer.sol` | Forced transfers on shielded balances (deployed on 5124 as USDS) |
| `src/projects/yieldToOne/interfaces/IMYieldToOne.sol` | Interface, events (incl. `Transfer(bytes)` overload), errors |
| `src/projects/jmi/JMIExtension.sol` | **DECIDED: in scope.** In the deployable seismic build; inherits the shielded MYieldToOne |
| `src/MExtension.sol` | Exactly one behavioral line: `_revertIfInsufficientBalance` made `virtual` |
| `lib/common` delta `v1.5.1..a1fbf37` | 12 lines in one file, embedded below |

Everything else in the diff vs `main` is pragma-only (`0.8.26` → `^0.8.26`) and out of
scope as a source change — but note that *all* contracts in the seismic build are
recompiled with ssolc (see [audits/README.md](audits/README.md) for why prior audits do
not cover that bytecode).

### lib/common delta (`v1.5.1..a1fbf37`, branch `feat/erc20-virtual`)

The audit pin is the submodule gitlink `a1fbf37b0ab10b0f8e71223793a0fd6af77b527d`
(recorded in `foundry.lock`; do not run `forge update` / `git submodule update --remote`
before handoff). The entire delta vs tag `v1.5.1`:

```diff
diff --git a/src/ERC20ExtendedUpgradeable.sol b/src/ERC20ExtendedUpgradeable.sol
index b8b56d7..c19231c 100644
--- a/src/ERC20ExtendedUpgradeable.sol
+++ b/src/ERC20ExtendedUpgradeable.sol
@@ -63,7 +63,7 @@ abstract contract ERC20ExtendedUpgradeable is
     /* ============ Interactive Functions ============ */
 
     /// @inheritdoc IERC20
-    function approve(address spender_, uint256 amount_) external returns (bool) {
+    function approve(address spender_, uint256 amount_) external virtual returns (bool) {
         _approve(msg.sender, spender_, amount_);
         return true;
     }
@@ -77,7 +77,7 @@ abstract contract ERC20ExtendedUpgradeable is
         uint8 v_,
         bytes32 r_,
         bytes32 s_
-    ) external {
+    ) external virtual {
         _revertIfInvalidSignature(owner_, _permitAndGetDigest(owner_, spender_, value_, deadline_), v_, r_, s_);
     }
 
@@ -88,18 +88,18 @@ abstract contract ERC20ExtendedUpgradeable is
         uint256 value_,
         uint256 deadline_,
         bytes memory signature_
-    ) external {
+    ) external virtual {
         _revertIfInvalidSignature(owner_, _permitAndGetDigest(owner_, spender_, value_, deadline_), signature_);
     }
 
     /// @inheritdoc IERC20
-    function transfer(address recipient_, uint256 amount_) external returns (bool) {
+    function transfer(address recipient_, uint256 amount_) external virtual returns (bool) {
         _transfer(msg.sender, recipient_, amount_);
         return true;
     }
 
     /// @inheritdoc IERC20
-    function transferFrom(address sender_, address recipient_, uint256 amount_) external returns (bool) {
+    function transferFrom(address sender_, address recipient_, uint256 amount_) external virtual returns (bool) {
         ERC20ExtendedStorageStruct storage $ = _getERC20ExtendedStorageLocation();
         uint256 spenderAllowance_ = $.allowance[sender_][msg.sender]; // Cache `spenderAllowance_` to stack.
 
@@ -119,7 +119,7 @@ abstract contract ERC20ExtendedUpgradeable is
     /* ============ View/Pure Functions ============ */
 
     /// @inheritdoc IERC20
-    function allowance(address account, address spender) public view returns (uint256) {
+    function allowance(address account, address spender) public view virtual returns (uint256) {
         return _getERC20ExtendedStorageLocation().allowance[account][spender];
     }
 
```

## System context (Seismic testnet, chain 5124)

Live dependencies the in-scope contracts interact with. Deployment coordinated through
`m0-foundation/evm-m-suite-deployment`, branch `feat/seismic` @ `c63e7a8` (the canonical
5124 deployment artifacts landed on its follow-up branch `feat/seismic-chain-config` @
`530b942`; upstream M0 repos are consumed as submodules on pragma-only `feat/seismic`
branches — **TODO: freeze exact submodule SHAs at handoff**).

| Contract | Address (5124) | Source | Scope |
| -------- | -------------- | ------ | ----- |
| M Token | `0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b` | `m0-foundation/protocol` (via suite deployment) | Out |
| SwapFacility | `0xB6807116b3B1B321a390594e31ECD6e0076f6278` | this repo, `src/swap/SwapFacility.sol` (source pragma-only vs `main`) | Out as source; ssolc-recompiled bytecode caveat applies |
| Portal (SpokePortal) | `0xD925C84b55E4e44a53749fF5F2a5A13F63D128fd` | `m0-foundation/m-portal-v2`, deployed via the suite deployment above (pinned in its `deployments/5124.json`) | Out |
| LimitOrderProtocol | TODO — not yet deployed on 5124 (allowlisting deferred; see note below) | TODO: repo + commit | Out |
| CreateX | `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` | canonical CreateX factory (`pcaversaccio/createx`) | Out (deploy infra only) |

The suite deployment's `deployments/5124.json` also records the rest of the 5124 stack:
registrar `0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c`, Hyperlane bridge
`0xfCc1d596Ad6cAb0b5394eAa447d8626813180f32`, wrapped M
`0x437cc33344a0B27A429f795ff6B469C72698B291` — none are direct dependencies of the
in-scope contracts.

`script/ConfigureSeismicExtension.s.sol` treats LimitOrderProtocol as optional
(`LIMIT_ORDER_PROTOCOL` unset ⇒ Portal-only allowlist at first configure); once deployed
it is added by rerunning the same `make configure-extension-seismic-testnet` target (both
setters no-op on already-set values).

## Trust model / roles

All roles below are held by **one EOA** on testnet. Intended mainnet custody is **TODO**
(multisig/timelock decision pending).

| Authority | Powers | Current testnet holder | Intended mainnet custody |
| --------- | ------ | ---------------------- | ------------------------ |
| `DEFAULT_ADMIN_ROLE` | Role admin for all roles; `setContractKey` (one-shot — whoever supplies the keypair can decrypt every encrypted event payload); `setAllowlisted` (an allowlisted address can read **any** account's balance and use native `transferFrom`) | `0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217` (EOA) | TODO |
| `FREEZE_MANAGER_ROLE` | Freeze / unfreeze any account | same EOA | TODO |
| `FORCED_TRANSFER_MANAGER_ROLE` | `forceTransfer` out of frozen accounts (plaintext amounts) | same EOA | TODO |
| `PAUSER_ROLE` | Pause / unpause all transfers | same EOA | TODO |
| `YIELD_RECIPIENT_MANAGER_ROLE` | `setYieldRecipient` | same EOA | TODO |
| ProxyAdmin owner | Upgrade the implementation | same EOA (`ProxyAdmin` `0x3471d21118f19bfdb84591a92c82546c74f2f321`) | TODO |

**Proxy-upgrade/admin authority can read or redirect all shielded state**: an
implementation swap (or an admin-allowlisted reader) defeats every shielding guarantee of
this token. On a privacy token, upgrade/admin authority is deanonymization authority.

## Accepted risks

1. **Insufficient-funds revert side-channel (ssolc Warning 10311, three sites):** the
   allowance check in `_spendAllowanceAndTransfer`, the sender-balance check in
   `_shieldedTransfer`, and the `_revertIfInsufficientBalance` override (unwrap path)
   branch on shielded values. Revert-vs-success lets an *authorized spender* (or the
   holder) binary-search a balance/allowance. Inherent to revert-on-insufficient ERC-20
   semantics over shielded storage; each site carries an inline `// NOTE:`.
   **TODO: confirm the recommended idiom with Seismic.**
2. **Forced-transfer amounts are plaintext by design (pending decision):** `forceTransfer`
   emits cleartext `Transfer`/`ForcedTransfer` with the seized amount, revealing (part of)
   a frozen holder's balance. Compliance transparency may want exactly this —
   **TODO: decide and record.**
3. **ERC-20 deviations** (table below): integrators relying on standard ERC-20 semantics
   will break; documented as the intended SRC-20 surface.

## ERC-20 deviations

| Surface | Standard ERC-20 | This token |
| ------- | ---------------- | ---------- |
| `balanceOf(address)` | Public read | Reverts `Unauthorized` for third parties; allowed for the account itself, allowlisted infra, and compliance roles (freeze / forced-transfer managers) |
| `allowance(address,address)` | Public read | Gated like `balanceOf` (account/spender only) |
| `transfer(address,uint256)` | Transfers | **Always reverts** `UseShieldedTransfer` — use `transfer(address,suint256)` |
| `transferFrom(address,address,uint256)` | Transfers per allowance | Allowlisted-infra callers only; others revert `UseShieldedTransfer` |
| `approve(address,uint256)` | Sets allowance | Allowlisted-infra spenders only; others revert `UseShieldedApprove` |
| `permit` (both overloads) | Gasless approval | **Always reverts** `UseShieldedApprove` |
| `Transfer` event | `Transfer(address,address,uint256)` | Second shape `Transfer(address,address,bytes)` (distinct topic0) carries the encrypted amount on shielded paths; mint/burn/infra paths stay plaintext |
| `Approval` event | `Approval(address,address,uint256)` | Second shape `Approval(address,address,bytes)` (distinct topic0) on the shielded approve path |

## Floating pragma

Pragmas are `^0.8.26` solely so ssolc 0.8.31 compiles the tree; deployed artifacts are
built with the pinned toolchain in [TOOLCHAIN.md](TOOLCHAIN.md).

## Monitoring / indexing

Observable **without** the contract key: `totalSupply`, M backing
(`mToken.balanceOf(extension)`), wrap/unwrap and other infra plaintext events, and the
transfer graph (indexed `from`/`to` topics on both event shapes). Per-holder amounts exist
only inside per-recipient ciphertexts and require the contract private key to decrypt
(**TODO: decryptor operator + key custody**). Indexers (Envio/subgraphs) must either
handle or deliberately ignore the `bytes`-overload `Transfer`/`Approval` events — they
share names but not topic0s with the standard events.

## Prior audits

None of the existing reports cover this branch's diff or its ssolc-built bytecode — see
[audits/README.md](audits/README.md).
