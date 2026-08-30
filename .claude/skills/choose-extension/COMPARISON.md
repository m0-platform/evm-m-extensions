# M Extension Comparison

Detailed comparison of all M extension types to help you make an informed decision.

## Feature Matrix

| Feature | MYieldToOne | MYieldToOneForcedTransfer | MYieldFee | MSpokeYieldFee | MEarnerManager | JMIExtension |
|---------|:-----------:|:-------------------------:|:---------:|:--------------:|:--------------:|:------------:|
| **Yield Model** | Single | Single | All holders | All holders | Whitelisted | Single |
| **Freezable accounts** | Yes | Yes | Yes | Yes | No | Yes |
| **Pausable** | Yes | Yes | Yes | Yes | Yes | Yes |
| **Forced transfers** | No | Yes | No | No | No | No |
| **Whitelist required** | No | No | No | No | Yes | No |
| **Per-address fee rates** | No | No | No | No | Yes | No |
| **Global fee rate** | No | No | Yes | Yes | No | No |
| **Custom claim recipients** | No | No | Yes | Yes | No | No |
| **Multi-asset collateral** | No | No | No | No | No | Yes |
| **L2 compatible** | Yes | Yes | L1 only | L2 only | Yes | Yes |

## Yield Models Explained

### Single Recipient (Treasury Model)
All yield accumulates and is claimable by a single designated address. Best for protocols where yield should flow to a treasury, DAO, or specific entity.

**Yield calculation:** `yield = M_balance - totalSupply`

**Extensions:** MYieldToOne, MYieldToOneForcedTransfer, JMIExtension

### All Holders (User Yield Model)
Every token holder earns yield proportionally to their balance. A global fee percentage can be deducted from all yield.

**Yield calculation:** Uses continuous index-based accrual with adjustable fee rate.

**Extensions:** MYieldFee (L1), MSpokeYieldFee (L2)

### Whitelisted Holders (Institutional Model)
Only approved addresses can hold tokens. Each address can have a custom fee rate, enabling tiered arrangements.

**Yield calculation:** Per-account principal tracking with individual fee deductions.

**Extensions:** MEarnerManager

## Role Requirements

### MYieldToOne
| Role | Purpose |
|------|---------|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke other roles |
| `YIELD_RECIPIENT_MANAGER_ROLE` | Change yield recipient address |
| `FREEZE_MANAGER_ROLE` | Freeze/unfreeze accounts |
| `PAUSER_ROLE` | Pause/unpause contract |

### MYieldToOneForcedTransfer
All MYieldToOne roles plus:
| Role | Purpose |
|------|---------|
| `FORCED_TRANSFER_MANAGER_ROLE` | Transfer tokens from frozen accounts |

### MYieldFee / MSpokeYieldFee
| Role | Purpose |
|------|---------|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke other roles |
| `FEE_MANAGER_ROLE` | Set fee rate and fee recipient |
| `CLAIM_RECIPIENT_MANAGER_ROLE` | Set custom claim recipients per account |
| `FREEZE_MANAGER_ROLE` | Freeze/unfreeze accounts |
| `PAUSER_ROLE` | Pause/unpause contract |

### MEarnerManager
| Role | Purpose |
|------|---------|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke other roles |
| `EARNER_MANAGER_ROLE` | Whitelist accounts, set fee rates, manage fee recipient |
| `PAUSER_ROLE` | Pause/unpause contract |

### JMIExtension
All MYieldToOne roles plus:
| Role | Purpose |
|------|---------|
| `ASSET_CAP_MANAGER_ROLE` | Set caps for non-M collateral assets |

## Storage Patterns

All extensions use ERC-7201 namespaced storage for upgrade safety.

### Per-Account Storage
- **MYieldToOne/MYieldToOneForcedTransfer:** Balance, frozen status
- **MYieldFee/MSpokeYieldFee:** Balance, principal, custom claim recipient, frozen status
- **MEarnerManager:** Balance, principal, whitelisted status, fee rate
- **JMIExtension:** Balance, frozen status

### Global Storage
- **MYieldToOne/MYieldToOneForcedTransfer:** Total supply, yield recipient
- **MYieldFee/MSpokeYieldFee:** Total supply, total principal, fee rate, fee recipient, latest index
- **MEarnerManager:** Total supply, total principal, fee recipient, earning enabled flag
- **JMIExtension:** Total supply, yield recipient, per-asset caps and balances, total assets

## Gas Considerations

| Operation | Lower Gas | Higher Gas | Notes |
|-----------|-----------|------------|-------|
| Transfer | MYieldToOne | MEarnerManager | Whitelist checks add overhead |
| Wrap | MYieldToOne | JMIExtension | Multi-asset logic adds cost |
| Claim yield | MYieldToOne | MYieldFee | Index updates more complex |

## Upgrade Paths

All extensions deploy behind TransparentUpgradeableProxy, allowing:
- Bug fixes without redeployment
- Feature additions (with care for storage layout)
- Role/parameter adjustments via admin functions

**Important:** Changing yield models (e.g., MYieldToOne to MYieldFee) requires migration to a new contract.

## Chain Deployment Guide

| Chain Type | Recommended Extensions |
|------------|----------------------|
| Ethereum Mainnet | MYieldToOne, MYieldToOneForcedTransfer, MYieldFee, MEarnerManager, JMIExtension |
| Arbitrum | MSpokeYieldFee, MYieldToOne, MEarnerManager, JMIExtension |
| Optimism | MSpokeYieldFee, MYieldToOne, MEarnerManager, JMIExtension |
| Base | MSpokeYieldFee, MYieldToOne, MEarnerManager, JMIExtension |
| Other L2s | Check if Rate Oracle is available for MSpokeYieldFee |
