# Audit Evidence Reports

Generated 2026-06-11 on branch `seismic-audit-readiness` at commit `55502a2`
(`fix(script): make LimitOrderProtocol optional in ConfigureSeismicExtension`) with the pinned
Seismic toolchain — `sforge 1.3.5-v0.2.0` (commit `6065731`) / `ssolc 0.8.31-develop.2026.4.29+commit.cd9163d8`,
`FOUNDRY_PROFILE=seismic` (mercury EVM, optimizer on, `optimizer_runs = 800`) via
`source scripts/seismic-env.sh`. All artifacts come from the
unit suite (`test/unit/**`, 468 tests, 0 failures); `test/integration/**` is excluded because
mainnet-fork RPCs lack `eth_getFlaggedStorageAt` (it runs on a Seismic devnet via `make integration`).

## Files

| File                   | Command                                                                                                                                                                                                                                                            | Contents                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| `coverage-summary.txt` | `FOUNDRY_PROFILE=seismic FOUNDRY_FORCE=false sforge coverage --report summary --report lcov --no-match-coverage '(script\|test\|lib)' --match-path 'test/unit/**' --skip 'test/integration/**'` (after a `sforge build --force` to pre-populate `out/` — see note) | Per-file line/statement/branch/function coverage for `src/**`                           |
| `coverage-lcov.info`   | same run (`lcov.info` renamed; the root `.gitignore` ignores the default name at any depth)                                                                                                                                                                        | Machine-readable LCOV for the 13 `src/**` files                                         |
| `gas-report.txt`       | `sforge test --match-path 'test/unit/**' --gas-report --force` (ANSI stripped)                                                                                                                                                                                     | Full unit-run log (468 named passing tests) + per-contract gas tables                   |
| `contract-sizes.txt`   | `sforge build --force --sizes` (table only)                                                                                                                                                                                                                        | Runtime/initcode sizes and EIP-170/EIP-3860 margins, all contracts incl. test harnesses |

Reproduction note for coverage: `sforge coverage` compiles in-memory without writing artifacts,
and the seismic profile's `force = true` wipes `out/` first — which breaks the 11 OZ-Upgrades-based
suites that `vm.readFile` harness artifacts from `out/` in `setUp`. Run `sforge build --force`
first, then coverage with `FOUNDRY_FORCE=false`. The `--skip 'test/integration/**'` is required
because the inline-config scanner rejects `test/integration/MExtensionSystem.t.sol`'s
`ci.fuzz.runs` annotation (no `ci` profile on this branch) even when `--match-path` excludes it.

## Headline numbers

Coverage (unit suite, `src/**`): **94.13% lines** (962/1022), 93.95% statements, 89.43% branches,
93.36% functions overall. The audit-scope yieldToOne contracts are at **100% on all four metrics**:
`MYieldToOne.sol` (185/185 lines, 24/24 branches, 46/46 funcs), `MYieldToOneForcedTransfer.sol`
(22/22 lines), and `JMIExtension.sol` (96/96 lines, 7/7 branches, 26/26 funcs). The sub-90% files
(`ReentrancyLock` 65%, `UniswapV3SwapAdapter` 67%) are swap periphery outside the audit scope.

EIP-170 (24,576 B runtime limit) margins for the deployables: **JMIExtension 23,536 B — 1,040 B
margin** (the tightest; the reason `optimizer_runs` is capped at 800), MYieldToOneForcedTransfer
20,579 B (3,997 B margin), MYieldToOne 18,886 B (5,690 B margin), MSpokeYieldFee 20,423 B (4,153 B),
MYieldFee 19,866 B (4,710 B), MEarnerManager 17,902 B (6,674 B), SwapFacility 13,425 B (11,151 B).
Test-only `JMIExtensionHarness` sits at a 352 B margin; it is never deployed.

Gas (shielded SRC-20 paths, measured on `MYieldToOneHarness` behind a transparent proxy):
`transfer(address,suint256)` median 65,798 / avg 64,497 over 268 calls;
`transferFrom(address,address,suint256)` median 92,552; `approve(address,suint256)` avg 35,154;
`setContractKey` 123,484.
