# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# --- Seismic toolchain (sforge/ssolc) -----------------------------------------
# Shielded types need the Seismic fork: prepend the repo-local install if present, else fail fast via $(require-toolchain); recipes can't source seismic-env.sh under make's sh.
ifneq ($(wildcard .seismic-toolchain/bin/sforge),)
export PATH := $(CURDIR)/.seismic-toolchain/bin:$(PATH)
endif

define require-toolchain
@command -v sforge >/dev/null 2>&1 || { echo "Seismic toolchain missing — run: source scripts/seismic-env.sh && sfoundryup"; exit 1; }
endef

# dapp deps (stock forge; does not compile sources)
update:; forge update

# Default to actual deployment (not simulation)
DRY_RUN ?= false

# Conditionally set broadcast and verify flags
ifeq ($(DRY_RUN),true)
	BROADCAST_FLAGS =
	BROADCAST_ONLY_FLAGS =
else
	BROADCAST_FLAGS = --broadcast --verify
	BROADCAST_ONLY_FLAGS = --broadcast
endif

# Not runnable on this branch: crytic-compile cannot ingest mercury/ssolc builds (shielded types).
slither:
	@echo "slither cannot ingest mercury/ssolc builds; last clean static-analysis baseline is merge-base 87a2f42 on main — see AUDIT-SCOPE.md"
	@exit 1

# Common tasks — honor an inherited FOUNDRY_PROFILE (e.g. from .husky/pre-commit); default "seismic".
profile ?= $(if $(FOUNDRY_PROFILE),$(FOUNDRY_PROFILE),seismic)

# sforge for the seismic profile (mercury EVM, ssolc); stock forge otherwise.
FORGE_BIN = $(if $(filter seismic,$(profile)),sforge,forge)

build:
	$(require-toolchain)
	@./build.sh -p $(profile)

tests:
	$(require-toolchain)
	@./test.sh -p $(profile)

fuzz:
	$(require-toolchain)
	@./test.sh -t testFuzz -p $(profile)

# Fork RPCs lack eth_getFlaggedStorageAt, so integration tests only run against a Seismic
# devnet; FOUNDRY_NO_MATCH_PATH re-includes test/integration/** (excluded by the profile).
integration:
	$(require-toolchain)
	@if [ -z "$(SEISMIC_DEVNET_RPC_URL)" ]; then \
		echo "integration tests cannot run locally (fork RPC lacks eth_getFlaggedStorageAt); run against Seismic devnet"; \
		exit 1; \
	fi
	SEISMIC_DEVNET_RPC_URL=$(SEISMIC_DEVNET_RPC_URL) FOUNDRY_NO_MATCH_PATH='no_match_nothing/**' ./test.sh -d test/integration -p $(profile)

# In-process Seismic integration suite (real precompiles, no node needed).
integration-seismic:
	$(require-toolchain)
	FOUNDRY_NO_MATCH_PATH='no_match_nothing/**' FOUNDRY_PROFILE=$(profile) $(FORGE_BIN) test --match-path 'test/integration/seismic/*' -vv

# Full sanvil E2E: TxSeismic key install, signed-read gating, off-chain decryption.
e2e-sanvil:
	$(require-toolchain)
	bash test/integration/seismic/run-sanvil-e2e.sh

# Read-only status checklist against the live chain-5124 deployment.
check-live-seismic-testnet:
	bash test/integration/seismic/check-live-testnet.sh

coverage:
	$(require-toolchain)
	FOUNDRY_PROFILE=$(profile) $(FORGE_BIN) coverage --report lcov && lcov --extract lcov.info -o lcov.info 'src/*' --ignore-errors inconsistent && genhtml lcov.info -o coverage

gas-report:
	$(require-toolchain)
	FOUNDRY_PROFILE=$(profile) $(FORGE_BIN) test --force --gas-report > gasreport.ansi

sizes:
	$(require-toolchain)
	@./build.sh -p $(profile) -s

clean:
	forge clean && rm -rf ./abi && rm -rf ./bytecode && rm -rf ./types

# --- DEPLOY (Seismic only; this branch never merges back — other-chain targets live on main) ---

# --- Seismic (mercury/ssolc) verification --------------------------------------
# socialscan rejects `evmVersion: mercury`, so inline `--verify` can't work; targets broadcast only, then script/verify-seismic.py auto-verifies the whole broadcast (python3 + jq).
# Testnet (chain 5124) — full socialscan verify endpoint.
SEISMIC_TESTNET_CHAIN_ID ?= 5124
SEISMIC_TESTNET_VERIFIER_URL ?= https://api.socialscan.io/seismic-testnet/v1/explorer/command_api/contract
SEISMIC_VERIFY_TESTNET = VERIFIER_URL=$(SEISMIC_TESTNET_VERIFIER_URL) python3 script/verify-seismic.py $(1) $(2)

# Mainnet — expected socialscan path (confirm at launch); CHAIN_ID defaults empty so targets fail closed until .env sets SEISMIC_MAINNET_{RPC_URL,CHAIN_ID,VERIFIER_URL}.
SEISMIC_MAINNET_CHAIN_ID ?=
SEISMIC_MAINNET_VERIFIER_URL ?= https://api.socialscan.io/seismic/v1/explorer/command_api/contract
SEISMIC_VERIFY_MAINNET = VERIFIER_URL=$(SEISMIC_MAINNET_VERIFIER_URL) python3 script/verify-seismic.py $(1) $(2)
# $(call SEISMIC_VERIFY_{TESTNET,MAINNET},<DeployScript.s.sol>,<chain_id>)

# Seismic targets override DEPLOY_FLAGS to broadcast-only + POST_DEPLOY (see above).
DEPLOY_FLAGS = $(BROADCAST_FLAGS) --verifier ${VERIFIER} --verifier-url ${VERIFIER_URL}
POST_DEPLOY ?=

deploy-yield-to-one-forced-transfer:
	$(require-toolchain)
	FOUNDRY_PROFILE=seismic PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_NAME=$(EXTENSION_NAME) \
	sforge script script/deploy/DeployYieldToOneForcedTransfer.s.sol:DeployYieldToOneForcedTransfer \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(DEPLOY_FLAGS)
	$(POST_DEPLOY)

# local node must be sanvil (stock anvil lacks the mercury EVM / shielded types)
deploy-yield-to-one-forced-transfer-local: RPC_URL=$(LOCALHOST_RPC_URL)
deploy-yield-to-one-forced-transfer-local: DEPLOY_FLAGS=$(BROADCAST_ONLY_FLAGS)
deploy-yield-to-one-forced-transfer-local: deploy-yield-to-one-forced-transfer

# Re-verify the latest seismic-testnet broadcast without redeploying.
verify-yield-to-one-forced-transfer-seismic-testnet:
	$(call SEISMIC_VERIFY_TESTNET,DeployYieldToOneForcedTransfer.s.sol,$(SEISMIC_TESTNET_CHAIN_ID))

# Re-verify the latest seismic-mainnet broadcast without redeploying.
verify-yield-to-one-forced-transfer-seismic-mainnet:
	$(call SEISMIC_VERIFY_MAINNET,DeployYieldToOneForcedTransfer.s.sol,$(SEISMIC_MAINNET_CHAIN_ID))

# Seismic mainnet: broadcast only, then auto-verify from the broadcast (fails closed until .env is set).
deploy-yield-to-one-forced-transfer-seismic-mainnet: RPC_URL=$(SEISMIC_MAINNET_RPC_URL)
deploy-yield-to-one-forced-transfer-seismic-mainnet: DEPLOY_FLAGS=$(BROADCAST_ONLY_FLAGS)
deploy-yield-to-one-forced-transfer-seismic-mainnet: POST_DEPLOY=$(call SEISMIC_VERIFY_MAINNET,DeployYieldToOneForcedTransfer.s.sol,$(SEISMIC_MAINNET_CHAIN_ID))
deploy-yield-to-one-forced-transfer-seismic-mainnet: deploy-yield-to-one-forced-transfer

# Seismic testnet: broadcast only, then auto-verify from the broadcast.
deploy-yield-to-one-forced-transfer-seismic-testnet: RPC_URL=$(SEISMIC_TESTNET_RPC_URL)
deploy-yield-to-one-forced-transfer-seismic-testnet: DEPLOY_FLAGS=$(BROADCAST_ONLY_FLAGS)
deploy-yield-to-one-forced-transfer-seismic-testnet: POST_DEPLOY=$(call SEISMIC_VERIFY_TESTNET,DeployYieldToOneForcedTransfer.s.sol,$(SEISMIC_TESTNET_CHAIN_ID))
deploy-yield-to-one-forced-transfer-seismic-testnet: deploy-yield-to-one-forced-transfer

deploy-jmi-extension:
	$(require-toolchain)
	FOUNDRY_PROFILE=seismic PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_NAME=$(EXTENSION_NAME) \
	sforge script script/deploy/DeployJMIExtension.s.sol:DeployJMIExtension \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(DEPLOY_FLAGS)
	$(POST_DEPLOY)

# Seismic testnet: broadcast only, then auto-verify from the broadcast.
deploy-jmi-extension-seismic-testnet: RPC_URL=$(SEISMIC_TESTNET_RPC_URL)
deploy-jmi-extension-seismic-testnet: DEPLOY_FLAGS=$(BROADCAST_ONLY_FLAGS)
deploy-jmi-extension-seismic-testnet: POST_DEPLOY=$(call SEISMIC_VERIFY_TESTNET,DeployJMIExtension.s.sol,$(SEISMIC_TESTNET_CHAIN_ID))
deploy-jmi-extension-seismic-testnet: deploy-jmi-extension

# Re-verify the latest seismic-testnet broadcast without redeploying.
verify-jmi-extension-seismic-testnet:
	$(call SEISMIC_VERIFY_TESTNET,DeployJMIExtension.s.sol,$(SEISMIC_TESTNET_CHAIN_ID))

# --- OPS (post-deploy configuration) --------------------------------------------

# Contract-key install via `scast send --seismic` — a forge broadcast would publish the key in plaintext calldata (see script header). Env: EXTENSION_PROXY.
set-contract-key-seismic-testnet:
	RPC_URL=$(SEISMIC_TESTNET_RPC_URL) EXTENSION_PROXY=$(EXTENSION_PROXY) PRIVATE_KEY=$(PRIVATE_KEY) ./script/set-contract-key.sh

# Approve the extension on SwapFacility + populate the infra allowlist. Env: EXTENSION_PROXY, PORTAL, LIMIT_ORDER_PROTOCOL.
configure-extension-seismic-testnet:
	$(require-toolchain)
	FOUNDRY_PROFILE=seismic PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_PROXY=$(EXTENSION_PROXY) PORTAL=$(PORTAL) LIMIT_ORDER_PROTOCOL=$(LIMIT_ORDER_PROTOCOL) \
	sforge script script/ConfigureSeismicExtension.s.sol:ConfigureSeismicExtension \
	--rpc-url $(SEISMIC_TESTNET_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_ONLY_FLAGS)
