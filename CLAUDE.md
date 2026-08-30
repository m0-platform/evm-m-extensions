# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

M Extensions Framework - A modular system for creating ERC-20 stablecoin extensions that wrap the yield-bearing `$M` token into non-rebasing variants for DeFi composability. All contracts deploy behind transparent upgradeable proxies.

## Build Commands

```bash
# Build
make build                    # Production build with sizes

# Test
npm test                      # Run all tests
make fuzz                     # Fuzz tests only (5,000 runs default)
make integration              # Integration tests only
make invariant                # Invariant tests
make coverage                 # Generate lcov coverage report

# Run specific test
forge test --match-test "testFunctionName" -vvv
forge test --match-contract "ContractName" -vvv

# Code quality
npm run prettier              # Format Solidity files
npm run solhint               # Lint src/ files
npm run solhint-fix           # Auto-fix linting issues
npm run slither               # Static analysis

# CI profile (more thorough)
make tests profile=ci         # 10,000 fuzz runs, 250 invariant depth
```

## Architecture

### Core Contract Hierarchy

```
MExtension (abstract base)
├── MYieldToOne              - All yield to single recipient, with blacklist
├── MYieldToOneForcedTransfer - Adds forced transfer recovery from frozen accounts
├── MEarnerManager           - Yield to all holders minus per-address fee, with whitelist
├── MYieldFee                - Same yield rate for all, global fee deduction
├── MSpokeYieldFee           - For L2s, index updates via bridging not time
└── JMIExtension             - "Just Mint It" model with collateral deposits
```

### Swap Infrastructure

- **SwapFacility**: Exclusive router for wrap/unwrap operations. Only SwapFacility can call `wrap()`/`unwrap()` on extensions.
- **UniswapV3SwapAdapter**: Helper for token swaps via Uniswap V3 SwapRouter02.

### Component Modules (src/components/)

Reusable behaviors that extensions can compose:
- `freezable/` - Account freezing mechanism
- `pausable/` - Pause/unpause functionality
- `forcedTransferable/` - Recovery mechanism for frozen accounts

### Storage Pattern

Uses ERC-7201 namespaced storage for upgradeable contracts. Storage structs are accessed via `_getStorage()` internal functions.

## Testing

Tests are in `test/unit/` and `test/integration/`. Base test setup in `test/utils/BaseUnitTest.sol` provides:
- Mock contracts (MockM, MockRateOracle, MockRegistrar)
- SwapFacility deployment with transparent proxy
- Standard test accounts (alice, bob, carol, etc.)
- Role constants (PAUSER_ROLE, FREEZE_MANAGER_ROLE, etc.)

Test files use `.t.sol` suffix. Deployment scripts use `.s.sol` suffix.

## Deployment

Deployments use Foundry scripts in `script/deploy/`. Configuration in `script/Config.sol` defines per-chain settings.

```bash
# Dry run (simulation only)
DRY_RUN=true make deploy-swap-facility-sepolia

# Actual deployment (broadcasts and verifies)
make deploy-swap-facility-sepolia

# Available deployment targets
make deploy-yield-to-one-{sepolia|mainnet}
make deploy-yield-to-one-forced-transfer-{sepolia|mainnet}
make deploy-swap-facility-{sepolia|mainnet|arbitrum|optimism|base|...}
make deploy-swap-adapter-{sepolia|mainnet|arbitrum}
```

Deployed addresses are stored in `deployments/{chainId}.json`.

## Key Configuration

- Solidity 0.8.26, Cancun EVM
- Optimizer: 19,999 runs
- Max line length: 120 chars
- Private variables: prefix with `_`
- FFI enabled for proxy deployments

## Pre-commit Hooks

Husky runs on commit:
1. Prettier formats changed .sol/.json/.md/.yml files
2. Solhint lints changed src/ and test/ .sol files
3. Full test suite runs
