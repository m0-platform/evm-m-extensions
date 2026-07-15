# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# dapp deps
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

# Deployment helpers
deploy-local :; FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url localhost $(BROADCAST_ONLY_FLAGS) -v
deploy-sepolia :; FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url sepolia $(BROADCAST_ONLY_FLAGS) -vvv

# Run slither
slither :; FOUNDRY_PROFILE=production forge build --build-info --skip '*/test/**' --skip '*/script/**' --force && slither --compile-force-framework foundry --ignore-compile --sarif results.sarif --config-file slither.config.json .

# Common tasks
profile ?=default

build:
	@./build.sh -p production

tests:
	@./test.sh -p $(profile)

fuzz:
	@./test.sh -t testFuzz -p $(profile)

integration:
	@./test.sh -d test/integration -p $(profile)

invariant:
	@./test.sh -d test/invariant -p $(profile)

coverage:
	FOUNDRY_PROFILE=$(profile) forge coverage --report lcov && lcov --extract lcov.info -o lcov.info 'src/*' --ignore-errors inconsistent && genhtml lcov.info -o coverage

gas-report:
	FOUNDRY_PROFILE=$(profile) forge test --force --gas-report > gasreport.ansi

sizes:
	@./build.sh -p production -s

clean:
	forge clean && rm -rf ./abi && rm -rf ./bytecode && rm -rf ./types

#
#
# DEPLOY
#
#

# EXTENSION_NAME is an ERC-20 token name and may contain spaces (e.g. "Dual
# Class USD"), so it is quoted wherever it is passed on a recipe command line —
# an unquoted $(EXTENSION_NAME) word-splits and breaks the deploy.
deploy-yield-to-one:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_NAME="$(EXTENSION_NAME)" \
	forge script script/deploy/DeployYieldToOne.s.sol:DeployYieldToOne \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

deploy-yield-to-one-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
deploy-yield-to-one-sepolia: deploy-yield-to-one

deploy-yield-to-one-forced-transfer:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_NAME="$(EXTENSION_NAME)" \
	forge script script/deploy/DeployYieldToOneForcedTransfer.s.sol:DeployYieldToOneForcedTransfer \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS) \
	--verifier ${VERIFIER} --verifier-url ${VERIFIER_URL}

deploy-yield-to-one-forced-transfer-local: RPC_URL=$(LOCALHOST_RPC_URL)
deploy-yield-to-one-forced-transfer-local: deploy-yield-to-one-forced-transfer

deploy-yield-to-one-forced-transfer-mainnet: RPC_URL=$(MAINNET_RPC_URL)
deploy-yield-to-one-forced-transfer-mainnet: VERIFIER="etherscan"
deploy-yield-to-one-forced-transfer-mainnet: VERIFIER_URL=${MAINNET_VERIFIER_URL}
deploy-yield-to-one-forced-transfer-mainnet: deploy-yield-to-one-forced-transfer

deploy-yield-to-one-forced-transfer-citrea: RPC_URL=$(CITREA_RPC_URL)
deploy-yield-to-one-forced-transfer-citrea: VERIFIER="custom"
deploy-yield-to-one-forced-transfer-citrea: VERIFIER_URL=${CITREA_VERIFIER_URL}
deploy-yield-to-one-forced-transfer-citrea: deploy-yield-to-one-forced-transfer

deploy-yield-to-one-forced-transfer-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
deploy-yield-to-one-forced-transfer-sepolia: VERIFIER="etherscan"
deploy-yield-to-one-forced-transfer-sepolia: VERIFIER_URL=${SEPOLIA_VERIFIER_URL}
deploy-yield-to-one-forced-transfer-sepolia: deploy-yield-to-one-forced-transfer

deploy-yield-to-all:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_NAME="$(EXTENSION_NAME)" \
	forge script script/deploy/DeployYieldToAllWithFee.s.sol:DeployYieldToAllWithFee \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

deploy-yield-to-all-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
deploy-yield-to-all-sepolia: deploy-yield-to-all

deploy-m-earner-manager:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_NAME="$(EXTENSION_NAME)" \
	forge script script/deploy/DeployMEarnerManager.s.sol:DeployMEarnerManager \
	--private-key $(PRIVATE_KEY) \
	--rpc-url $(RPC_URL) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

deploy-m-earner-manager-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
deploy-m-earner-manager-sepolia: deploy-m-earner-manager

deploy-jmi-extension:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_NAME="$(EXTENSION_NAME)" \
	forge script script/deploy/DeployJMIExtension.s.sol:DeployJMIExtension \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

deploy-jmi-extension-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
deploy-jmi-extension-sepolia: deploy-jmi-extension 

deploy-swap-adapter:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) \
	forge script script/deploy/DeploySwapAdapter.s.sol:DeploySwapAdapter \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive \
	$(BROADCAST_FLAGS) --verifier ${VERIFIER} --verifier-url ${VERIFIER_URL}

deploy-swap-adapter-local: RPC_URL=$(LOCALHOST_RPC_URL)
deploy-swap-adapter-local: deploy-swap-adapter

deploy-swap-adapter-mainnet: RPC_URL=$(MAINNET_RPC_URL)
deploy-swap-adapter-mainnet: VERIFIER="etherscan"
deploy-swap-adapter-mainnet: VERIFIER_URL=${MAINNET_VERIFIER_URL}
deploy-swap-adapter-mainnet: deploy-swap-adapter

deploy-swap-adapter-arbitrum: RPC_URL=$(ARBITRUM_RPC_URL)
deploy-swap-adapter-arbitrum: VERIFIER="etherscan"
deploy-swap-adapter-arbitrum: VERIFIER_URL=${ARBITRUM_VERIFIER_URL}
deploy-swap-adapter-arbitrum: deploy-swap-adapter

deploy-swap-adapter-soneium: RPC_URL=$(SONEIUM_RPC_URL)
deploy-swap-adapter-soneium: VERIFIER="blockscout"
deploy-swap-adapter-soneium: VERIFIER_URL=${SONEIUM_VERIFIER_URL}
deploy-swap-adapter-soneium: deploy-swap-adapter

deploy-swap-adapter-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
deploy-swap-adapter-sepolia: VERIFIER="etherscan"
deploy-swap-adapter-sepolia: VERIFIER_URL=${SEPOLIA_VERIFIER_URL}
deploy-swap-adapter-sepolia: deploy-swap-adapter

deploy-swap-adapter-arbitrum-sepolia: RPC_URL=$(ARBITRUM_SEPOLIA_RPC_URL)
deploy-swap-adapter-arbitrum-sepolia: VERIFIER="etherscan"
deploy-swap-adapter-arbitrum-sepolia: VERIFIER_URL=${ARBITRUM_SEPOLIA_VERIFIER_URL}
deploy-swap-adapter-arbitrum-sepolia: deploy-swap-adapter

deploy-swap-facility:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) PAUSER=$(PAUSER) \
	forge script script/deploy/DeploySwapFacility.s.sol:DeploySwapFacility \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive -v \
	$(BROADCAST_FLAGS) --verifier ${VERIFIER} --verifier-url ${VERIFIER_URL}

deploy-swap-facility-local: RPC_URL=$(LOCALHOST_RPC_URL)
deploy-swap-facility-local: deploy-swap-facility

deploy-swap-facility-mainnet: RPC_URL=$(MAINNET_RPC_URL)
deploy-swap-facility-mainnet: VERIFIER="etherscan"
deploy-swap-facility-mainnet: VERIFIER_URL=${MAINNET_VERIFIER_URL}
deploy-swap-facility-mainnet: deploy-swap-facility

deploy-swap-facility-arbitrum: RPC_URL=$(ARBITRUM_RPC_URL)
deploy-swap-facility-arbitrum: VERIFIER="etherscan"
deploy-swap-facility-arbitrum: VERIFIER_URL=${ARBITRUM_VERIFIER_URL}
deploy-swap-facility-arbitrum: deploy-swap-facility

deploy-swap-facility-optimism: RPC_URL=$(OPTIMISM_RPC_URL)
deploy-swap-facility-optimism: VERIFIER="etherscan"
deploy-swap-facility-optimism: VERIFIER_URL=${OPTIMISM_VERIFIER_URL}
deploy-swap-facility-optimism: deploy-swap-facility

deploy-swap-facility-hyperliquid: RPC_URL=$(HYPERLIQUID_RPC_URL)
deploy-swap-facility-hyperliquid: VERIFIER="etherscan"
deploy-swap-facility-hyperliquid: VERIFIER_URL=${HYPERLIQUID_VERIFIER_URL}
deploy-swap-facility-hyperliquid: deploy-swap-facility

deploy-swap-facility-plume: RPC_URL=$(PLUME_RPC_URL)
deploy-swap-facility-plume: VERIFIER="blockscout"
deploy-swap-facility-plume: VERIFIER_URL=${PLUME_VERIFIER_URL}
deploy-swap-facility-plume: deploy-swap-facility

deploy-swap-facility-bsc: RPC_URL=$(BSC_RPC_URL)
deploy-swap-facility-bsc: VERIFIER="etherscan"
deploy-swap-facility-bsc: VERIFIER_URL=${BSC_VERIFIER_URL}
deploy-swap-facility-bsc: deploy-swap-facility

deploy-swap-facility-mantra: RPC_URL=$(MANTRA_RPC_URL)
deploy-swap-facility-mantra: VERIFIER="blockscout"
deploy-swap-facility-mantra: VERIFIER_URL=${MANTRA_VERIFIER_URL}
deploy-swap-facility-mantra: deploy-swap-facility

deploy-swap-facility-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
deploy-swap-facility-sepolia: VERIFIER="etherscan"
deploy-swap-facility-sepolia: VERIFIER_URL=${SEPOLIA_VERIFIER_URL}
deploy-swap-facility-sepolia: deploy-swap-facility

deploy-swap-facility-arbitrum-sepolia: RPC_URL=$(ARBITRUM_SEPOLIA_RPC_URL)
deploy-swap-facility-arbitrum-sepolia: VERIFIER="etherscan"
deploy-swap-facility-arbitrum-sepolia: VERIFIER_URL=${ARBITRUM_SEPOLIA_VERIFIER_URL}
deploy-swap-facility-arbitrum-sepolia: deploy-swap-facility

deploy-swap-facility-optimism-sepolia: RPC_URL=$(OPTIMISM_SEPOLIA_RPC_URL)
deploy-swap-facility-optimism-sepolia: VERIFIER="etherscan"
deploy-swap-facility-optimism-sepolia: VERIFIER_URL=${OPTIMISM_SEPOLIA_VERIFIER_URL}
deploy-swap-facility-optimism-sepolia: deploy-swap-facility

deploy-swap-facility-apechain-testnet: RPC_URL=$(APECHAIN_TESTNET_RPC_URL)
deploy-swap-facility-apechain-testnet: VERIFIER="etherscan"
deploy-swap-facility-apechain-testnet: VERIFIER_URL=${APECHAIN_TESTNET_VERIFIER_URL}
deploy-swap-facility-apechain-testnet: deploy-swap-facility

deploy-swap-facility-bsc-testnet: RPC_URL=$(BSC_TESTNET_RPC_URL)
deploy-swap-facility-bsc-testnet: VERIFIER="etherscan"
deploy-swap-facility-bsc-testnet: VERIFIER_URL=${BSC_TESTNET_VERIFIER_URL}
deploy-swap-facility-bsc-testnet: deploy-swap-facility

deploy-swap-facility-soneium-testnet: RPC_URL=$(SONEIUM_TESTNET_RPC_URL)
deploy-swap-facility-soneium-testnet: VERIFIER="blockscout"
deploy-swap-facility-soneium-testnet: VERIFIER_URL=${SONEIUM_TESTNET_VERIFIER_URL}
deploy-swap-facility-soneium-testnet: deploy-swap-facility

deploy-swap-facility-base-sepolia: RPC_URL=$(BASE_SEPOLIA_RPC_URL)
deploy-swap-facility-base-sepolia: VERIFIER="etherscan"
deploy-swap-facility-base-sepolia: VERIFIER_URL=${BASE_SEPOLIA_VERIFIER_URL}
deploy-swap-facility-base-sepolia: deploy-swap-facility

deploy-swap-facility-base: RPC_URL=$(BASE_RPC_URL)
deploy-swap-facility-base: VERIFIER="etherscan"
deploy-swap-facility-base: VERIFIER_URL=${BASE_VERIFIER_URL}
deploy-swap-facility-base: deploy-swap-facility

deploy-swap-facility-soneium: RPC_URL=$(SONEIUM_RPC_URL)
deploy-swap-facility-soneium: VERIFIER="blockscout"
deploy-swap-facility-soneium: VERIFIER_URL=${SONEIUM_VERIFIER_URL}
deploy-swap-facility-soneium: deploy-swap-facility

deploy-swap-facility-plasma: RPC_URL=$(PLASMA_RPC_URL)
deploy-swap-facility-plasma: VERIFIER="custom"
deploy-swap-facility-plasma: VERIFIER_URL=${PLASMA_VERIFIER_URL}
deploy-swap-facility-plasma: deploy-swap-facility

deploy-swap-facility-citrea: RPC_URL=$(CITREA_RPC_URL)
deploy-swap-facility-citrea: VERIFIER="custom"
deploy-swap-facility-citrea: VERIFIER_URL=${CITREA_VERIFIER_URL}
deploy-swap-facility-citrea: deploy-swap-facility

deploy-swap-facility-sei: RPC_URL=$(SEI_RPC_URL)
deploy-swap-facility-sei: VERIFIER="etherscan"
deploy-swap-facility-sei: VERIFIER_URL=${SEI_VERIFIER_URL}
deploy-swap-facility-sei: deploy-swap-facility

deploy-swap-facility-0g: RPC_URL=$(ZG_RPC_URL)
deploy-swap-facility-0g: VERIFIER="custom"
deploy-swap-facility-0g: VERIFIER_URL=$(ZG_VERIFIER_URL)
deploy-swap-facility-0g: deploy-swap-facility

#
#
# CONFIGURE (Post-deployment config actions)
#
#

enable-earning:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_ADDRESS=$(EXTENSION_ADDRESS) \
	forge script script/execute/EnableEarning.s.sol:EnableEarning \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_ONLY_FLAGS)

set-permissioned-extension:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) SWAP_FACILITY_ADDRESS=$(SWAP_FACILITY_ADDRESS) \
	EXTENSION_ADDRESS=$(EXTENSION_ADDRESS) SAFE_ADDRESS=$(SAFE_ADDRESS) \
	forge script script/execute/ProposeSetPermissionedExtension.s.sol:ProposeSetPermissionedExtension \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_ONLY_FLAGS)

set-permissioned-mswapper:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) SWAP_FACILITY_ADDRESS=$(SWAP_FACILITY_ADDRESS) \
	EXTENSION_ADDRESS=$(EXTENSION_ADDRESS) SWAPPER_ADDRESS=$(SWAPPER_ADDRESS) SAFE_ADDRESS=$(SAFE_ADDRESS) \
	forge script script/execute/ProposeSetPermissionedMSwapper.s.sol:ProposeSetPermissionedMSwapper \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_ONLY_FLAGS)

# Testnet-only EOA-direct variants of the two multisig-propose targets above.
# Invoked by m0-launchpad's worker only when network.environment == 'testnet'
# AND the registry step has executionMode "multisig-propose". On testnet, the
# deployer EOA holds DEFAULT_ADMIN_ROLE on SwapFacility so a direct broadcast
# succeeds. Contract-level access control is the implicit second gate on mainnet.
set-permissioned-extension-testnet-direct:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) SWAP_FACILITY_ADDRESS=$(SWAP_FACILITY_ADDRESS) \
	EXTENSION_ADDRESS=$(EXTENSION_ADDRESS) \
	forge script script/execute/SetPermissionedExtensionDirect.s.sol:SetPermissionedExtensionDirect \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_ONLY_FLAGS)

set-permissioned-mswapper-testnet-direct:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) SWAP_FACILITY_ADDRESS=$(SWAP_FACILITY_ADDRESS) \
	EXTENSION_ADDRESS=$(EXTENSION_ADDRESS) SWAPPER_ADDRESS=$(SWAPPER_ADDRESS) \
	forge script script/execute/SetPermissionedMSwapperDirect.s.sol:SetPermissionedMSwapperDirect \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_ONLY_FLAGS)

#
#
# UPGRADE
#
#

upgrade-swap-facility:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) PAUSER=$(PAUSER) \
	forge script script/upgrade/UpgradeSwapFacility.s.sol:UpgradeSwapFacility \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS) \
	--verifier ${VERIFIER} --verifier-url ${VERIFIER_URL}

upgrade-swap-facility-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
upgrade-swap-facility-sepolia: VERIFIER="etherscan"
upgrade-swap-facility-sepolia: VERIFIER_URL=${SEPOLIA_VERIFIER_URL}
upgrade-swap-facility-sepolia: upgrade-swap-facility

upgrade-swap-facility-arbitrum-sepolia: RPC_URL=$(ARBITRUM_SEPOLIA_RPC_URL)
upgrade-swap-facility-arbitrum-sepolia: VERIFIER="etherscan"
upgrade-swap-facility-arbitrum-sepolia: VERIFIER_URL=${ARBITRUM_SEPOLIA_VERIFIER_URL}
upgrade-swap-facility-arbitrum-sepolia: upgrade-swap-facility

# This upgrade is strictly specific to Sepolia as it caters to an old SwapFacility deployment
upgrade-old-swap-facility:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) \
	forge script script/upgrade/UpgradeOldSwapFacility.s.sol:UpgradeOldSwapFacility \
	--rpc-url $(SEPOLIA_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

upgrade-jmi-extension:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) EXTENSION_ADDRESS=$(EXTENSION_ADDRESS) \
	forge script script/upgrade/UpgradeJMIExtension.s.sol:UpgradeJMIExtension \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

upgrade-jmi-extension-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
upgrade-jmi-extension-sepolia: upgrade-jmi-extension

#
#
# PROPOSE (via Multisig)
#
#

propose-transfer-swap-facility-owner:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) \
	forge script script/ProposeTransferSwapFacilityOwner.s.sol:ProposeTransferSwapFacilityOwner \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_ONLY_FLAGS)

propose-transfer-swap-facility-owner-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
propose-transfer-swap-facility-owner-sepolia: propose-transfer-swap-facility-owner

propose-transfer-swap-facility-owner-mainnet: RPC_URL=$(MAINNET_RPC_URL)
propose-transfer-swap-facility-owner-mainnet: propose-transfer-swap-facility-owner

propose-transfer-swap-facility-owner-bsc: RPC_URL=$(BSC_RPC_URL)
propose-transfer-swap-facility-owner-bsc: propose-transfer-swap-facility-owner

propose-transfer-swap-facility-owner-linea: RPC_URL=$(LINEA_RPC_URL)
propose-transfer-swap-facility-owner-linea: propose-transfer-swap-facility-owner

propose-swap-facility-upgrade:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) SAFE_ADDRESS=$(SAFE_ADDRESS) PAUSER=$(PAUSER) \
	forge script script/upgrade/ProposeSwapFacilityUpgrade.s.sol:ProposeSwapFacilityUpgrade \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS) \
	--verifier ${VERIFIER} --verifier-url ${VERIFIER_URL}

propose-swap-facility-upgrade-sepolia: RPC_URL=$(SEPOLIA_RPC_URL)
propose-swap-facility-upgrade-sepolia: propose-swap-facility-upgrade

propose-swap-facility-upgrade-mainnet: RPC_URL=$(MAINNET_RPC_URL)
propose-swap-facility-upgrade-mainnet: VERIFIER="etherscan"
propose-swap-facility-upgrade-mainnet: VERIFIER_URL=$(MAINNET_VERIFIER_URL)
propose-swap-facility-upgrade-mainnet: propose-swap-facility-upgrade

propose-swap-facility-upgrade-arbitrum: RPC_URL=$(ARBITRUM_RPC_URL)
propose-swap-facility-upgrade-arbitrum: VERIFIER="etherscan"
propose-swap-facility-upgrade-arbitrum: VERIFIER_URL=$(ARBITRUM_VERIFIER_URL)
propose-swap-facility-upgrade-arbitrum: propose-swap-facility-upgrade

propose-swap-facility-upgrade-base: RPC_URL=$(BASE_RPC_URL)
propose-swap-facility-upgrade-base: VERIFIER="etherscan"
propose-swap-facility-upgrade-base: VERIFIER_URL=$(BASE_VERIFIER_URL)
propose-swap-facility-upgrade-base: propose-swap-facility-upgrade

propose-swap-facility-upgrade-optimism: RPC_URL=$(OPTIMISM_RPC_URL)
propose-swap-facility-upgrade-optimism: VERIFIER="etherscan"
propose-swap-facility-upgrade-optimism: VERIFIER_URL=$(OPTIMISM_VERIFIER_URL)
propose-swap-facility-upgrade-optimism: propose-swap-facility-upgrade

propose-swap-facility-upgrade-bsc: RPC_URL=$(BSC_RPC_URL)
propose-swap-facility-upgrade-bsc: VERIFIER="etherscan"
propose-swap-facility-upgrade-bsc: VERIFIER_URL=$(BSC_VERIFIER_URL)
propose-swap-facility-upgrade-bsc: propose-swap-facility-upgrade

propose-swap-facility-upgrade-soneium: RPC_URL=$(SONEIUM_RPC_URL)
propose-swap-facility-upgrade-soneium: VERIFIER="blockscout"
propose-swap-facility-upgrade-soneium: VERIFIER_URL=$(SONEIUM_VERIFIER_URL)
propose-swap-facility-upgrade-soneium: propose-swap-facility-upgrade

propose-swap-facility-upgrade-mantra: RPC_URL=$(MANTRA_RPC_URL)
propose-swap-facility-upgrade-mantra: VERIFIER="blockscout"
propose-swap-facility-upgrade-mantra: VERIFIER_URL=$(MANTRA_VERIFIER_URL)
propose-swap-facility-upgrade-mantra: propose-swap-facility-upgrade

propose-swap-facility-upgrade-hyperliquid: RPC_URL=$(HYPERLIQUID_RPC_URL)
propose-swap-facility-upgrade-hyperliquid: VERIFIER="etherscan"
propose-swap-facility-upgrade-hyperliquid: VERIFIER_URL=$(HYPERLIQUID_VERIFIER_URL)
propose-swap-facility-upgrade-hyperliquid: propose-swap-facility-upgrade
#
#
# PROPOSE (via Multisig to Timelock)
#
#

propose-timelock-swap-facility-upgrade:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) SAFE_ADDRESS=$(SAFE_ADDRESS) TIMELOCK_ADDRESS=$(TIMELOCK_ADDRESS) PAUSER=$(PAUSER) \
	forge script script/upgrade/ProposeTimelockSwapFacilityUpgrade.s.sol:ProposeTimelockSwapFacilityUpgrade \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS) \
	--verifier ${VERIFIER} --verifier-url ${VERIFIER_URL}

propose-timelock-swap-facility-upgrade-mainnet: RPC_URL=$(MAINNET_RPC_URL)
propose-timelock-swap-facility-upgrade-mainnet: VERIFIER="etherscan"
propose-timelock-swap-facility-upgrade-mainnet: VERIFIER_URL=$(MAINNET_VERIFIER_URL)
propose-timelock-swap-facility-upgrade-mainnet: propose-timelock-swap-facility-upgrade

propose-timelock-swap-facility-upgrade-bsc: RPC_URL=$(BSC_RPC_URL)
propose-timelock-swap-facility-upgrade-bsc: VERIFIER="etherscan"
propose-timelock-swap-facility-upgrade-bsc: VERIFIER_URL=$(BSC_VERIFIER_URL)
propose-timelock-swap-facility-upgrade-bsc: propose-timelock-swap-facility-upgrade

propose-timelock-swap-facility-upgrade-linea: RPC_URL=$(LINEA_RPC_URL)
propose-timelock-swap-facility-upgrade-linea: VERIFIER="etherscan"
propose-timelock-swap-facility-upgrade-linea: VERIFIER_URL=$(LINEA_VERIFIER_URL)
propose-timelock-swap-facility-upgrade-linea: propose-timelock-swap-facility-upgrade

#
#
# EXECUTE (Timelock)
#
#

execute-timelock-swap-facility-upgrade:
	FOUNDRY_PROFILE=production PRIVATE_KEY=$(PRIVATE_KEY) TIMELOCK_ADDRESS=$(TIMELOCK_ADDRESS) PAUSER=$(PAUSER) NEW_IMPLEMENTATION=$(NEW_IMPLEMENTATION) \
	forge script script/upgrade/ExecuteTimelockSwapFacilityUpgrade.s.sol:ExecuteTimelockSwapFacilityUpgrade \
	--rpc-url $(RPC_URL) \
	--skip test --slow --non-interactive $(BROADCAST_FLAGS)

execute-timelock-swap-facility-upgrade-mainnet: RPC_URL=$(MAINNET_RPC_URL)
execute-timelock-swap-facility-upgrade-mainnet: execute-timelock-swap-facility-upgrade

execute-timelock-swap-facility-upgrade-bsc: RPC_URL=$(BSC_RPC_URL)
execute-timelock-swap-facility-upgrade-bsc: execute-timelock-swap-facility-upgrade

execute-timelock-swap-facility-upgrade-linea: RPC_URL=$(LINEA_RPC_URL)
execute-timelock-swap-facility-upgrade-linea: execute-timelock-swap-facility-upgrade
