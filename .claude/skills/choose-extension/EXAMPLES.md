# M Extension Use Case Examples

Real-world scenarios to help you identify which extension fits your needs.

## Example 1: Protocol Treasury

**Scenario:** A DeFi protocol wants to wrap M tokens for use in their ecosystem. All yield should go to the protocol treasury to fund development.

**Requirements:**
- Single yield recipient (treasury multisig)
- Open access (anyone can hold tokens)
- No special compliance needs

**Recommendation:** `MYieldToOne`

**Why:** Simplest model for treasury yield collection. Anyone can call `claimYield()` to mint accumulated yield to the designated recipient.

**Configuration:**
```solidity
yieldRecipient = 0x...treasury_multisig
```

---

## Example 2: Regulated Stablecoin

**Scenario:** A regulated financial institution issuing a compliant stablecoin needs the ability to freeze accounts and recover funds from sanctioned addresses.

**Requirements:**
- Single yield recipient
- Account freezing for sanctions compliance
- Ability to recover funds from frozen accounts
- OFAC compliance

**Recommendation:** `MYieldToOneForcedTransfer`

**Why:** Provides all MYieldToOne features plus forced transfer capability for regulatory compliance. Can seize tokens from frozen accounts when legally required.

**Configuration:**
```solidity
yieldRecipient = 0x...compliance_treasury
freezeManager = 0x...compliance_team
forcedTransferManager = 0x...legal_team
```

---

## Example 3: Yield-Bearing Stablecoin for DeFi

**Scenario:** A DeFi protocol wants to offer a yield-bearing stablecoin where all holders automatically earn yield. The protocol takes a 10% fee on yield.

**Requirements:**
- All holders earn yield
- Protocol fee on yield
- Deploying on Ethereum mainnet

**Recommendation:** `MYieldFee`

**Why:** Automatically distributes yield to all holders with a configurable global fee. No claiming required by users - balances grow automatically.

**Configuration:**
```solidity
feeRate = 1000  // 10% (in basis points)
feeRecipient = 0x...protocol_treasury
```

---

## Example 4: L2 Yield Token

**Scenario:** Same as Example 3, but deploying on Arbitrum to reduce gas costs for users.

**Requirements:**
- All holders earn yield
- Protocol fee on yield
- Deploying on Arbitrum

**Recommendation:** `MSpokeYieldFee`

**Why:** Same functionality as MYieldFee but designed for L2 chains. Uses bridged index updates from L1 instead of real-time calculation.

**Configuration:**
```solidity
feeRate = 1000  // 10%
feeRecipient = 0x...protocol_treasury
rateOracle = 0x...arbitrum_rate_oracle
```

---

## Example 5: Institutional Platform

**Scenario:** A fintech company serving multiple institutional clients. Each client has a different fee arrangement based on their AUM. Only approved institutions can hold tokens.

**Requirements:**
- Whitelist-based access
- Different fee rates per client
- KYC/AML compliance (only approved entities)

**Recommendation:** `MEarnerManager`

**Why:** Provides granular control over who can hold tokens and individual fee rates per account. Perfect for B2B platforms with tiered client arrangements.

**Configuration:**
```solidity
// Whitelist institution A with 5% fee
setAccountInfo(institutionA, true, 500)

// Whitelist institution B with 2% fee (VIP rate)
setAccountInfo(institutionB, true, 200)

feeRecipient = 0x...platform_treasury
```

---

## Example 6: Multi-Collateral Stablecoin

**Scenario:** A protocol wants to bootstrap liquidity by accepting multiple stablecoins (USDC, DAI, USDT) as collateral in addition to M. Yield from M backing goes to the treasury.

**Requirements:**
- Single yield recipient
- Accept multiple collateral types
- 1:1 peg between all accepted assets
- Caps on non-M collateral

**Recommendation:** `JMIExtension`

**Why:** "Just Mint It" model allows users to deposit M or any approved stablecoin to mint tokens. Simplifies onboarding for users who don't yet hold M.

**Configuration:**
```solidity
yieldRecipient = 0x...treasury

// Allow USDC with 10M cap
setAssetCap(USDC, 10_000_000e6)

// Allow DAI with 5M cap
setAssetCap(DAI, 5_000_000e18)
```

**Important Note:** Yield only accrues on the M portion of backing. Non-M collateral should be periodically swapped to M using `replaceAssetWithM()` to maximize yield.

---

## Decision Summary

| If you need... | Choose... |
|----------------|-----------|
| Simple treasury yield | MYieldToOne |
| Treasury yield + compliance | MYieldToOneForcedTransfer |
| Yield for all holders (L1) | MYieldFee |
| Yield for all holders (L2) | MSpokeYieldFee |
| Per-client fee arrangements | MEarnerManager |
| Multiple collateral types | JMIExtension |
