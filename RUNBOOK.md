# Seismic Ops Runbook

Operational chain for deploying and configuring M extensions on Seismic (this branch never merges to `main`).
Toolchain: `source scripts/seismic-env.sh` (sforge/scast/ssolc on PATH); `.env` populated from `.env.example`.

## Post-deploy chain (once per derived extension instance)

Run in order — USDS (chain 5124) is done through step 1; JMIExtension and any future instance need all four.

1. **Deploy + verify**: `make deploy-yield-to-one-forced-transfer-seismic-testnet`
   (broadcasts, then auto-verifies every contract on socialscan via `script/verify-seismic.py`).
2. **Configure**: `make configure-extension-seismic-testnet`
   (env: `EXTENSION_PROXY`, `PORTAL`, `LIMIT_ORDER_PROTOCOL`; runs `script/ConfigureSeismicExtension.s.sol` — approves the extension on SwapFacility and allowlists the infra contracts).
3. **Install the contract key**: `make set-contract-key-seismic-testnet`
   (env: `EXTENSION_PROXY`; runs `script/set-contract-key.sh`).
   **MUST run BEFORE any user onboarding**: `registerPublicKey` is permissionless, and shielded transfers to a registered recipient revert `ContractKeyNotSet` until the key is installed — an open griefing window. One-shot, no rotation; fresh keypair per instance; archive both keys in 1Password (see the script header for why this is a shell script and not a forge script).
4. **Commit the record**: `deployments/<chainId>.json` + `broadcast/<DeployScript>.s.sol/<chainId>/run-*.json`.

## registerPublicKey

End-user concern, owned by the dapp/SDK — a plain tx (the public key is public; nothing to shield) that lets the contract encrypt `Transfer(bytes)` payloads to that user. Infra contracts (Portal, LimitOrderProtocol, SwapFacility) never register: the empty-ciphertext fallback plus the gated `balanceOf` cover them.

## Chain 5124 deployment record (USDS "Seismic Dollar")

| Contract | Address |
|---|---|
| MYieldToOneForcedTransfer proxy (USDS) | `0xb3b2f21f9a6a5d698D9178986Fa4148260B5d018` |
| MYieldToOneForcedTransfer implementation | `0x268b6e7e1ef3f3eab7aab5b20286ab51997223d9` |
| ProxyAdmin | `0x3471d21118f19bfdb84591a92c82546c74f2f321` |
| SwapFacility | `0xB6807116b3B1B321a390594e31ECD6e0076f6278` |
| M token | `0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b` |
| Admin / deployer (all roles + ProxyAdmin owner) | `0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217` |

Deploy txs (2026-06-05, commit `2cb7a6c`): implementation `0x6b2a685a27be27965f1c1f370693388cb6d1a57a314738804b0f642bf0150c5f` (block 15161974), CreateX `deployCreate3` for proxy + ProxyAdmin `0x248bb6469df2f154784da5ac647b62e806e94d65793e1e42081f5de60cc39eee` (block 15161982).

**Broadcast provenance**: the original `broadcast/DeployYieldToOneForcedTransfer.s.sol/5124/run-*.json` was never committed and the local copy was lost. The committed `run-latest.json` is a reconstruction (2026-06-11): tx hashes located via the socialscan explorer API, transaction payloads taken from the surviving `dry-run/run-latest.json` and verified byte-identical to the on-chain init code (inputs, gas, and nonces all match), receipts fetched from the RPC. All three contracts are source-verified on the explorer, which provides independent provenance for the addresses in `deployments/5124.json`.

## Seismic mainnet go-live checklist

Mainnet deploys currently fail closed (empty `SEISMIC_MAINNET_CHAIN_ID`, no `Config.sol` chain branch) — both items below are required:

1. `.env`: set `SEISMIC_MAINNET_RPC_URL`, `SEISMIC_MAINNET_CHAIN_ID`, `SEISMIC_MAINNET_VERIFIER_URL` (confirm the socialscan mainnet `command_api` path when the explorer is live).
2. `script/Config.sol`: add the mainnet chain-id constant and a `_getDeployConfig` branch — until then every script reverts `UnsupportedChain`.

Then run the same four-step post-deploy chain with the `-seismic-mainnet` targets.

## Onboarding the next deploy script (e.g. JMIExtension)

`deploy-jmi-extension-seismic-testnet` is already wired. To onboard another deploy script, copy the 4-line Makefile variant block:

```make
deploy-<name>-seismic-testnet: RPC_URL=$(SEISMIC_TESTNET_RPC_URL)
deploy-<name>-seismic-testnet: DEPLOY_FLAGS=$(BROADCAST_ONLY_FLAGS)
deploy-<name>-seismic-testnet: POST_DEPLOY=$(call SEISMIC_VERIFY_TESTNET,Deploy<Name>.s.sol,$(SEISMIC_TESTNET_CHAIN_ID))
deploy-<name>-seismic-testnet: deploy-<name>
```

The base `deploy-<name>` target must use `$(DEPLOY_FLAGS)` and end with a `$(POST_DEPLOY)` line (see `deploy-yield-to-one-forced-transfer`). After deploying, run steps 2–4 of the post-deploy chain against the new proxy.
