---
name: choose-extension
description: Helps developers choose the right M extension type for their use case. Use when someone asks which extension to use, wants to evaluate extension options, needs help deciding between MYieldToOne, MYieldFee, MEarnerManager, or other M extension types, or mentions "choose extension", "which extension", "extension for my use case".
---

# Choose Extension

Help developers select the appropriate M extension type through an interactive decision process.

## Instructions

When this skill is invoked, guide the developer through selecting the right M extension by asking questions about their requirements. Use the `AskUserQuestion` tool to ask questions step by step.

### Step 1: Yield Distribution Model

First, ask about yield distribution:

**Question:** "How should yield from the wrapped M tokens be distributed?"

**Options:**
1. **Single recipient** - All yield goes to one address (treasury, DAO, protocol)
2. **All token holders** - Every holder earns yield proportionally
3. **Whitelisted holders only** - Only approved addresses can hold tokens and earn yield

### Step 2: Follow-up Questions

Based on the answer to Step 1, ask relevant follow-up questions:

#### If "Single recipient":

Ask: "Do you need compliance features like forced transfers to recover tokens from frozen/sanctioned accounts?"

- **Yes, need forced transfers** - Ask about multi-asset collateral next
- **No forced transfers needed** - Ask about multi-asset collateral next

Then ask: "Do you need to accept multiple collateral types (e.g., USDC, DAI) in addition to M?"

- **Yes, multi-asset** - Recommend **JMIExtension**
- **No, M only** - If forced transfers needed: **MYieldToOneForcedTransfer**, otherwise: **MYieldToOne**

#### If "All token holders":

Ask: "Which chain are you deploying on?"

- **Ethereum mainnet (L1)** - Recommend **MYieldFee**
- **Layer 2 (Arbitrum, Optimism, Base, etc.)** - Recommend **MSpokeYieldFee**

#### If "Whitelisted holders only":

No further questions needed. Recommend **MEarnerManager**.

### Step 3: Provide Recommendation

After determining the appropriate extension, provide:

1. **The recommended extension** with a brief explanation
2. **Key features** of the recommended extension
3. **Required roles** to configure after deployment
4. **Link to the source file** for reference

### Extension Quick Reference

| Extension | Yield Model | Key Feature |
|-----------|-------------|-------------|
| `MYieldToOne` | Single recipient | Simple treasury model |
| `MYieldToOneForcedTransfer` | Single recipient | + Compliance/recovery |
| `MYieldFee` | All holders | Global fee, L1 |
| `MSpokeYieldFee` | All holders | Global fee, L2 |
| `MEarnerManager` | Whitelisted | Per-address fees |
| `JMIExtension` | Single recipient | Multi-asset collateral |

### Source File Locations

- `MYieldToOne`: `src/projects/yieldToOne/MYieldToOne.sol`
- `MYieldToOneForcedTransfer`: `src/projects/yieldToOne/MYieldToOneForcedTransfer.sol`
- `MYieldFee`: `src/projects/yieldToAllWithFee/MYieldFee.sol`
- `MSpokeYieldFee`: `src/projects/yieldToAllWithFee/MSpokeYieldFee.sol`
- `MEarnerManager`: `src/projects/earnerManager/MEarnerManager.sol`
- `JMIExtension`: `src/projects/jmi/JMIExtension.sol`

## Supporting Documentation

For detailed comparisons, see [COMPARISON.md](./COMPARISON.md).
For real-world use case examples, see [EXAMPLES.md](./EXAMPLES.md).
