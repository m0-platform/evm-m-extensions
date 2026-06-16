## $M Extensions Framework — Seismic branch

> **Standalone branch.** This branch exists solely for the Seismic deployment of `MYieldToOne`
> and never merges back to `main`. It builds with Seismic's `sforge`/`ssolc` toolchain — stock
> Foundry cannot compile it (see [Building this branch](#building-this-branch-seismic-toolchain)).
> Audit scope and the ERC-20 deviations this branch introduces are summarized under
> [Audit scope](#audit-scope).

**M Extension Framework** is a modular templates of ERC-20 **stablecoin extensions** that wrap the yield-bearing `$M` token into non-rebasing variants for improved composability within DeFi. Each extension manages yield distribution differently and integrates with a central **SwapFacility** contract that acts as the exclusive entry point for wrapping and unwrapping.

All contracts are deployed behind transparent upgradeable proxies (by default).

---

### 🧩 M Extensions

Each extension inherits from the abstract `MExtension` base contract, which defines shared wrapping logic. Only the `SwapFacility` is authorized to call `wrap()` and `unwrap()`. Yield is accrued based on the locked `$M` balance within each extension and minted via dedicated yield claim functions.

On this branch, `MYieldToOne` is rewritten as a **shielded SRC-20** for the Seismic mercury EVM; the other extensions are source-unchanged (modulo pragma) but are recompiled with `ssolc`. See [Audit scope](#audit-scope) for what is in scope.

- **`MYieldToOne`** (shielded SRC-20 on this branch)
  - All yield goes to a single configurable `yieldRecipient`
  - Balances and allowances are shielded `suint256`; `balanceOf` and `allowance` reads are gated (an account can read its own balance; third-party reads revert)
  - Shielded SRC-20 overloads of `transfer` / `approve` / `transferFrom` take `suint256` amounts, keeping them out of public calldata
  - Native ERC-20 paths are infra-only: `transferFrom(uint256)` and `approve(uint256)` work only for the immutable `SwapFacility` and an admin-managed infra allowlist (Portal, LimitOrderProtocol); `transfer(uint256)` and both `permit`s always revert
  - Encrypted `Transfer` / `Approval` events: amounts are emitted as per-recipient ECDH + AES-GCM ciphertexts (`setContractKey` installs the one-shot contract keypair; holders opt in via `registerPublicKey`)
  - Freezing enforced on all user actions
  - Handles loss of `$M` earner status gracefully

- **`MYieldToOneForcedTransfer`** (deployed on Seismic testnet as USDS)
  - Inherits all functionality from `MYieldToOne`
  - Adds compliant fund recovery via forced transfers from frozen accounts

- **`MEarnerManager`**
  - Redistributes yield to all holders minus per-address `feeRate`
  - Enforces a whitelist; non-whitelisted users are frozen and yield is redirected as fee
  - Yield is claimed via `claimFor(address)`
  - **Does not handle loss of `$M` earner status**, leading to potential insolvency if not upgraded

- **`MYieldFee`**
  - All users receive the same yield rate, discounted by a global `feeRate`
  - Yield can be redirected via `claimRecipient` per user
  - Includes `updateIndex()` to resync with new `$M` rates
  - Can handle loss and regain of `$M` earning status via `disableEarning()` and `enableEarning()`

- **`MSpokeYieldFee`**
  - Optimized for EVM sidechains (e.g., Arbitrum, Optimism)
  - Index updates occur via bridging, not time-based growth
  - Uses an external `rateOracle` for fee calculation
  - Inherits most behavior from `MYieldFee`

- **`JMIExtension`**
  - Wraps `$M` token into a non-rebasing equivalent with a "Just Mint It" (JMI) backing model
  - Allows minting by depositing `$M` or other approved collateral assets, assuming a 1:1 peg
  - All yield is consolidated and claimable by a single, designated `yieldRecipient`
  - Includes pausing functionality, asset freezes, and caps on non-`$M` collateral
  - Inherits core `MExtension` functionality and yield direction from `MYieldToOne`

---

### Building this branch (Seismic toolchain)

Shielded types (`suint256`, `sbytes32`) require Seismic's `ssolc` compiler fork and the `mercury` EVM revision; stock `forge`/`solc` fail at parse. The deployed Seismic-testnet bytecode is built with the pinned toolchain below; reproduce the audit with exactly these versions:

| Tool                          | Version                                    | Commit                                     |
| ----------------------------- | ------------------------------------------ | ------------------------------------------ |
| `sforge` / `scast` / `sanvil` | `1.3.5-v0.2.0`                             | `6065731fd5a1367603f6adac38f2fa174cbd66b8` |
| `ssolc`                       | `0.8.31-develop.2026.4.29+commit.cd9163d8` | `cd9163d8d7926fee2e2d3fe1f9609548e0414bf1` |

`sfoundryup` always fetches the _latest_ `ssolc` release, so confirm the installed `ssolc` matches the pin above after install. The socialscan verifier expects the label `v0.8.31+commit.cd9163d8` (the `-develop` prerelease tag stripped); `script/verify-seismic.py` handles that conversion.

First-time setup (repo-local install, nothing touches `~`):

```bash
# 1. Repo-local toolchain env (sforge auto-uses FOUNDRY_PROFILE=seismic)
source scripts/seismic-env.sh

# 2. Install sfoundryup
curl -L -H "Accept: application/vnd.github.v3.raw" \
  "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash

# 3. Install the pinned toolchain release (versions + commits in the table above)
sfoundryup -i v0.2.0
```

Then build and test (the seismic profile is the default on this branch):

```bash
make build
make tests
```

Known limitations:

- **No slither**: crytic-compile cannot ingest mercury/ssolc builds. The last clean static-analysis baseline is the merge-base with `main` (`87a2f42`).
- **Integration tests need a Seismic devnet**: shielded reads use `eth_getFlaggedStorageAt`, which mainnet-fork RPCs do not serve.
- **Verification** goes through `script/verify-seismic.py` (standard-JSON POST to the socialscan explorer API), not `forge verify-contract` — stock forge cannot reproduce mercury builds.

---

### Audit scope

In scope — the shielded rewrite and what inherits it:

| Path                                                    | Why                                                                                                                |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `src/projects/yieldToOne/MYieldToOne.sol`               | Shielded `suint256` balances/allowances, gated reads, shielded SRC-20 overloads, infra allowlist, encrypted events |
| `src/projects/yieldToOne/MYieldToOneForcedTransfer.sol` | Forced transfers on shielded balances (deployed on chain 5124 as USDS)                                             |
| `src/projects/yieldToOne/interfaces/IMYieldToOne.sol`   | Interface, events (incl. the `Transfer(…,bytes)` overload), errors                                                 |
| `src/projects/jmi/JMIExtension.sol`                     | In the deployable seismic build; inherits the shielded `MYieldToOne`                                               |
| `src/MExtension.sol`                                    | One behavioral line: `_revertIfInsufficientBalance` made `virtual`                                                 |
| `lib/common` (`v1.5.1..a1fbf37`)                        | 12 lines: ERC-20 entry points made `virtual`                                                                       |

Everything else in the diff vs `main` is pragma-only (`0.8.26` → `^0.8.26`). Every contract in the seismic build is recompiled with `ssolc`, so the prior audits (stock solc, unshielded) do not cover this bytecode — see [audits/README.md](audits/README.md).

#### ERC-20 deviations (intended SRC-20 surface)

| Surface                                 | This token                                                                                                                                                        |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `balanceOf` / `allowance`               | Gated reads: revert `Unauthorized` for third parties; allowed for the account itself, allowlisted infra, and compliance roles (freeze / forced-transfer managers) |
| `transfer(address,uint256)`             | Always reverts `UseShieldedTransfer` — use `transfer(address,suint256)`                                                                                           |
| `transferFrom(address,address,uint256)` | Allowlisted-infra callers only; others revert `UseShieldedTransfer`                                                                                               |
| `approve(address,uint256)`              | Allowlisted-infra spenders only; others revert `UseShieldedApprove`                                                                                               |
| `permit` (both overloads)               | Always revert `UseShieldedApprove`                                                                                                                                |
| `Transfer` / `Approval` events          | A second `(…,bytes)` shape (distinct topic0) carries the encrypted amount on shielded paths; mint / burn / infra paths stay plaintext `uint256`                   |

---

### 🔁 SwapFacility

The `SwapFacility` contract acts as the **exclusive router** for all wrapping and swapping operations involving `$M` and its extensions.

#### Key Functions

- `swap()` – Switch between extensions by unwrapping and re-wrapping
- `swapInM()`, `swapInMWithPermit()` – Accept `$M` and wrap into the selected extension
- `swapOutM()` – Unwrap to `$M` (restricted to whitelisted addresses only)

> All actions are subject to the rules defined by each extension (e.g., freeze lists, whitelists)

---

### 💱 UniswapV3SwapAdapter

A helper contract that enables token swaps via Uniswap V3.

- Immutable and admin-controlled
- Uses Uniswap's `SwapRouter02`
- Functions:
  - `swapIn(path, ...)`
  - `swapOut(path, ...)`
- Supports multi-hop paths or single-hop with default 0.01% fee
- Token whitelist is controlled via `DEFAULT_ADMIN_ROLE`

---

## Deployment Addresses

### Seismic Testnet (chain 5124)

USDS ("Seismic Dollar") is an instance of `MYieldToOneForcedTransfer`.

| Contract            | Address                                                                                                                                |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| USDS Proxy          | [0xb3b2f21f9a6a5d698D9178986Fa4148260B5d018](https://seismic-testnet.socialscan.io/address/0xb3b2f21f9a6a5d698D9178986Fa4148260B5d018) |
| USDS Implementation | [0x268b6e7e1ef3f3eab7aab5b20286ab51997223d9](https://seismic-testnet.socialscan.io/address/0x268b6e7e1ef3f3eab7aab5b20286ab51997223d9) |
| USDS ProxyAdmin     | [0x3471d21118f19bfdb84591a92c82546c74f2f321](https://seismic-testnet.socialscan.io/address/0x3471d21118f19bfdb84591a92c82546c74f2f321) |
| SwapFacility        | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://seismic-testnet.socialscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278) |
| M Token             | [0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b](https://seismic-testnet.socialscan.io/address/0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b) |

### SwapFacility

#### Mainnet

| Chain    | Proxy                                                                                                                             | Implementation                                                                                                                    | ProxyAdmin                                                                                                                        |
| -------- | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Ethereum | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://etherscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)             | [0xB4B738E41A0A79F09194e2f459b86F2406917Ef0](https://etherscan.io/address/0xb4b738e41a0a79f09194e2f459b86f2406917ef0)             | [0x0f38d8a5583f9316084e9c40737244870c565924](https://etherscan.io/address/0x0f38d8a5583f9316084e9c40737244870c565924)             |
| Arbitrum | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://arbiscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)              | [0xdBB20434e95afc9667C014FD69eda765Aa785eF9](https://arbiscan.io/address/0xdbb20434e95afc9667c014fd69eda765aa785ef9)              | [0x0f38d8a5583f9316084e9c40737244870c565924](https://arbiscan.io/address/0x0f38d8a5583f9316084e9c40737244870c565924)              |
| Optimism | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://optimistic.etherscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)  | [0x07dd9E3B00002F9cB178670159d4e6fe0D8Cd146](https://optimistic.etherscan.io/address/0x07dd9e3b00002f9cb178670159d4e6fe0d8cd146)  | [0x0f38d8a5583f9316084e9c40737244870c565924](https://optimistic.etherscan.io/address/0x0f38d8a5583f9316084e9c40737244870c565924)  |
| Base     | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://basescan.org/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)             | [0x23d8162e084aA33D8EF6FCC0Ab33f4028A53Ee79](https://basescan.org/address/0x23d8162e084aa33d8ef6fcc0ab33f4028a53ee79)             | [0x0f38d8a5583f9316084e9c40737244870c565924](https://basescan.org/address/0x0f38D8A5583f9316084E9c40737244870c565924)             |
| BSC      | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://bscscan.com/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)              | [0xBC1E1838889a9458acD7Bb3378B489CE5e1d2C1a](https://bscscan.com/address/0xbc1e1838889a9458acd7bb3378b489ce5e1d2c1a)              | [0x0f38d8a5583f9316084e9c40737244870c565924](https://bscscan.com/address/0x0f38d8a5583f9316084e9c40737244870c565924)              |
| Linea    | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://lineascan.build/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)          | [0x9E0fDb26954BC8998158C0C921C8254Bd6DfE5eC](https://lineascan.build/address/0x9e0fdb26954bc8998158c0c921c8254bd6dfe5ec)          | [0x0f38d8a5583f9316084e9c40737244870c565924](https://lineascan.build/address/0x0f38d8a5583f9316084e9c40737244870c565924)          |
| HyperEVM | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://hyperevmscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)          | [0x23E07a9353236d0367Ea9C5d6481c39920c6984C](https://hyperevmscan.io/address/0x23e07a9353236d0367ea9c5d6481c39920c6984c)          | [0x0f38d8a5583f9316084e9c40737244870c565924](https://hyperevmscan.io/address/0x0f38d8a5583f9316084e9c40737244870c565924)          |
| Plume    | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://explorer.plume.org/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)       | [0xF3Ef8f66955FFe4637768A2C7937f731CD67d890](https://explorer.plume.org/address/0xF3Ef8f66955FFe4637768A2C7937f731CD67d890)       | [0x0f38d8a5583f9316084e9c40737244870c565924](https://explorer.plume.org/address/0x0f38d8a5583f9316084e9c40737244870c565924)       |
| Mantra   | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://blockscout.mantrascan.io/address/0xb6807116b3b1b321a390594e31ecd6e0076f6278) | [0x23d8162e084aA33D8EF6FCC0Ab33f4028A53Ee79](https://blockscout.mantrascan.io/address/0x23d8162e084aA33D8EF6FCC0Ab33f4028A53Ee79) | [0x0f38d8a5583f9316084e9c40737244870c565924](https://blockscout.mantrascan.io/address/0x0f38d8a5583f9316084e9c40737244870c565924) |
| Plasma   | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://plasmascan.to/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)            | [0x83B73B2cc04578455f0194aD99af6752f4a117DD](https://plasmascan.to/address/0x83B73B2cc04578455f0194aD99af6752f4a117DD)            | [0x0f38d8a5583f9316084e9c40737244870c565924](https://plasmascan.to/address/0x0f38d8a5583f9316084e9c40737244870c565924)            |

#### Testnet

| Chain            | Proxy                                                                                                                                  | Implementation                                                                                                                         | ProxyAdmin                                                                                                                             |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Sepolia          | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://sepolia.etherscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)          | [0x431b9048C6Ff6Ef9D5d3e326675242134aFa3DC3](https://sepolia.etherscan.io/address/0x431b9048c6ff6ef9d5d3e326675242134afa3dc3)          | [0x0f38d8a5583f9316084e9c40737244870c565924](https://sepolia.etherscan.io/address/0x0f38d8a5583f9316084e9c40737244870c565924)          |
| Arbitrum Sepolia | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://sepolia.arbiscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)           | [0x248Af94D8F8F7f37b9b2355c8ca46B19E7c7c6C2](https://sepolia.arbiscan.io/address/0x248af94d8f8f7f37b9b2355c8ca46b19e7c7c6c2)           | [0x0f38d8a5583f9316084e9c40737244870c565924](https://sepolia.arbiscan.io/address/0x0f38d8a5583f9316084e9c40737244870c565924)           |
| Optimism Sepolia | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://sepolia-optimism.etherscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278) | [0x248Af94D8F8F7f37b9b2355c8ca46B19E7c7c6C2](https://sepolia-optimism.etherscan.io/address/0x248af94d8f8f7f37b9b2355c8ca46b19e7c7c6c2) | [0x0f38d8a5583f9316084e9c40737244870c565924](https://sepolia-optimism.etherscan.io/address/0x0f38d8a5583f9316084e9c40737244870c565924) |
| Base Sepolia     | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://sepolia.basescan.org/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278)          | [0x23d8162e084aA33D8EF6FCC0Ab33f4028A53Ee79](https://sepolia.basescan.org/address/0x23d8162e084aa33d8ef6fcc0ab33f4028a53ee79)          | [0x0f38d8a5583f9316084e9c40737244870c565924](https://sepolia.basescan.org/address/0x0f38d8a5583f9316084e9c40737244870c565924)          |
| Soneium Minato   | [0xB6807116b3B1B321a390594e31ECD6e0076f6278](https://soneium-minato.blockscout.com/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278) | [0x23d8162e084aA33D8EF6FCC0Ab33f4028A53Ee79](https://soneium-minato.blockscout.com/address/0x23d8162e084aA33D8EF6FCC0Ab33f4028A53Ee79) | [0x0f38d8a5583f9316084e9c40737244870c565924](https://soneium-minato.blockscout.com/address/0x0f38d8a5583f9316084e9c40737244870c565924) |

### UniswapV3SwapAdapter

| Chain    | Address                                                                                                               |
| -------- | --------------------------------------------------------------------------------------------------------------------- |
| Ethereum | [0x023bd2F0A95373C55FC8D1c5F8e60cC3B9Bc4f4b](https://etherscan.io/address/0x023bd2F0A95373C55FC8D1c5F8e60cC3B9Bc4f4b) |
| Arbitrum | [0x023bd2F0A95373C55FC8D1c5F8e60cC3B9Bc4f4b](https://arbiscan.io/address/0x023bd2F0A95373C55FC8D1c5F8e60cC3B9Bc4f4b)  |
