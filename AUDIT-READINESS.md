# Seismic Audit-Readiness Plan

Branch under review: `feat/seismic` (standalone, never merges to `main`).
Work branch for all changes: `seismic-audit-readiness` (cut from `feat/seismic` at `0456c6e`).
Produced 2026-06-11 by a 8-agent analysis workflow (6 deep-dive dimensions + adversarial verification + completeness critic); every load-bearing claim below was independently re-verified (on-chain reads, reproduced test runs, reproduced build failures).

## Status — Wave 1 executed, Wave 2 in flight (2026-06-11)

Decisions taken: **JMIExtension in audit scope** (tests fixed + re-enabled); **encrypted `Approval(bytes)` overload** on the shielded approve path (native infra approve stays plaintext); **balanceOf gate extended** to `FREEZE_MANAGER_ROLE` (and `FORCED_TRANSFER_MANAGER_ROLE` on the FT subclass); **bootstrap window closed by check-reordering** (`ContractKeyNotSet` before the unregistered fallback — the initializer fold was rejected because initialize calldata travels in plaintext inside the CreateX proxy deploy and would leak the private key).

Done (P1 fixes, P2 sweep, P3.1–P3.5/P3.7 tests, P4 tooling/CI, P5.1–P5.5 scripts/docs, P6.1–P6.7/P6.9 package): see the branch history. Full unit suite 468/468 green incl. JMI 59/59; all deployables under EIP-170 (JMI margin 1,040 B).

Wave 2 (executed 2026-06-11/12): P3.6 landed — in-process Seismic integration suite (11 tests, real precompiles, no mocks), sanvil E2E (TxSeismic 0x4A key install, signed-read gating, off-chain decryption of a real on-chain event), `script/decrypt-transfer-event.py` (pure-stdlib, vector-pinned), read-only live-testnet checker, and the `reports/` evidence pack (yieldToOne contracts 100% line/branch/function coverage). On-chain: `configure-extension` executed (extension approved, Portal allowlisted; LimitOrderProtocol added later via the same target — not yet deployed on 5124). **Still pending**: `set-contract-key-seismic-testnet` (user hold — griefing window open until run; commands in RUNBOOK.md), the live-testnet shielded-transfer smoke after the key lands, frozen tag (`audit/seismic-v1`), mainnet custody (AUDIT-SCOPE.md trust-model TODOs), Envio/indexer confirmation for the `bytes`-overload events (P6.8), and the optional keypair derive-and-compare hardening in `setContractKey`.

---

## 0. Blast radius (verified)

- Diff vs `main` (merge-base `87a2f42`): **87 files, but only 18 carry real changes** — 69 are pragma-only (`0.8.26 → ^0.8.26`).
- Real diff concentrates in:
  - `src/projects/yieldToOne/MYieldToOne.sol` (+302 lines): `suint256` shielded balances, shielded SRC-20 transfer/approve pipeline, gated `balanceOf`/`allowance` reads, infra allowlist (native paths re-enabled for SwapFacility-immutable + admin allowlist), encrypted `Transfer(bytes)` events via per-recipient ECDH (precompiles `0x65` ECDH / `0x68` HKDF / `0x66` AES-GCM), `setContractKey` / `registerPublicKey`.
  - `src/projects/yieldToOne/interfaces/IMYieldToOne.sol` (+155).
  - `src/MExtension.sol` — exactly one behavioral line: `_revertIfInsufficientBalance` made `virtual` (verified sound; no impact on the other five extension types).
  - Tests/harnesses for MYieldToOne (+~950 lines), Makefile/test.sh/foundry.toml/.husky, `script/verify-seismic.py` (new), `scripts/seismic-env.sh` (new), `script/Config.sol` (chain 5124).
- `lib/common` bumped to branch `feat/erc20-virtual` (gitlink `a1fbf37`). **The whole delta vs tag `v1.5.1` is 12 lines in one file** (`ERC20ExtendedUpgradeable.sol`: entry points marked `virtual`). `suint256`/`sbytes32` are ssolc built-in types, not lib code.
- Live deployment (chain 5124): proxy `0xb3b2f21f9a6a5d698D9178986Fa4148260B5d018` ("Seismic Dollar"/USDS), impl `0x268b6e7e…`, ProxyAdmin `0x3471d211…` — **live with code on-chain** (a digest claim that it "was never deployed" was refuted by `eth_getCode`).

---

## P0 — Time-sensitive operational items (live-testnet exposure, do first)

The live token is deployed but **unconfigured and key-less** (all verified by read-only on-chain calls):

1. **Build `script/set-contract-key.sh` + `make set-contract-key-seismic-testnet`** — answers the deploy-coherence question: **YES, a new tool is needed, and it must NOT be a Foundry script.** `sforge script` has no `--seismic` broadcast, so a `.s.sol` calling `setContractKey` would publish the contract's secp256k1 private key in plaintext calldata, permanently (one-shot, no rotation). The only safe vehicle is `scast send --seismic` (TxSeismic type 0x4A; verified locally that scast encodes `setContractKey(sbytes32,bytes)`, selector `0x5b4b03e8`). Script shape: preflight (refuse if `contractPublicKey()` non-empty) → keygen (`cast wallet new`, derive 33-byte compressed pubkey, pause for 1Password archival) → `scast send --seismic` → postflight assert. Header comment must state the plaintext-leak hazard.
2. **Run it against the live proxy.** `contractPublicKey()` returns `0x` today. Because `registerPublicKey` is permissionless and `_emitEncryptedTransfer` reverts `ContractKeyNotSet` for registered recipients, **anyone can today put the live token in a state where shielded transfers to them revert** — open griefing window until the key is set. (On-chain action — needs explicit go-ahead.)
3. **Add `script/ConfigureSeismicExtension.s.sol` + make target** — `SwapFacility.isApprovedExtension(USDS) == false` and the infra allowlist is empty, so nobody can wrap and Portal/LimitOrderProtocol have no access. Plain txs, so a normal sforge script is the right vehicle here. (Mirrors the deleted `ConfigureSwapFacility.s.sol` pattern.)
4. **Commit the 5124 deployment record**: write `deployments/5124.json` (repo convention — 21 other chains are committed) and recover/regenerate `broadcast/DeployYieldToOneForcedTransfer.s.sol/5124/run-*.json` (only `dry-run/` exists; `make verify-…-seismic-testnet` currently exits "no broadcast runs").
5. **Wire the post-deploy chain into a committed runbook**: deploy → verify (exists) → configure-extension → set-contract-key, once per derived instance (USDS now, JMIExtension later), with the ordering note that set-contract-key must precede user onboarding.

---

## P1 — Contract-level fixes & decisions (freeze the audit diff)

Small diffs + explicit decisions; everything here is what an external auditor would otherwise find first.

**Likely bug (fix):**
- `setContractKey` accepts `sbytes32(0)` as private key → bypasses the one-shot guard (guard compares stored key to zero), emits `ContractKeySet`, sets the public key, yet the contract still behaves key-less and a second call succeeds — breaking documented one-shot semantics and stranding off-chain clients. Add a zero-check revert + test.

**Hardening (recommended):**
- Validate pubkey compression prefix (`0x02`/`0x03`) in `setContractKey`/`registerPublicKey`; today any 33-byte blob registers, and an off-curve key makes every shielded transfer TO that account revert `PrecompileFailed` — self-inflicted (or deliberate) inbound-transfer DoS.
- Optional: derive-and-compare the pubkey from the privkey inside `setContractKey` so a mismatched keypair is rejected at install (one-shot + no rotation makes a mismatch permanent).
- Bootstrap window: between `initialize()` and `setContractKey()`, transfers to unregistered recipients succeed (empty-ciphertext fallback fires before the key check) while transfers to registered recipients revert — inconsistent partial availability that also leaks who is registered. Pick one: fold the keypair into `initialize()` (preferred), reorder the key check before the fallback, or accept + runbook-enforce immediate post-deploy key install.

**Decisions to make and document (either path is fine, silence is not):**
- **Cleartext `Approval` event**: `_shieldedApprove` stores the allowance shielded but emits standard `Approval` with the exact amount — allowances are fully public, contradicting the shielded-allowance design. Accept-and-document, or add an encrypted `Approval(address,address,bytes)` overload mirroring the Transfer treatment.
- **`forceTransfer` cleartext amounts**: seizure emits plaintext `Transfer` + `ForcedTransfer`, revealing a frozen holder's (partial) balance. Compliance transparency may want exactly this — decide and write it down (event-shape table in `IMYieldToOne`: which emits are cleartext-by-design vs shielded).
- **Compliance observability hole** (critic finding, high): `forceTransfer` takes an explicit amount, but `FREEZE_MANAGER`/`FORCED_TRANSFER_MANAGER` are not in the `balanceOf` gate — in production the compliance operator has no sanctioned way to learn how much to seize (unit tests mask this via a harness-only getter). Options: seize-full-balance variant, extend the gate to those roles, or formally allowlist a compliance reader. Add a test that uses only production-visible interfaces.
- **ssolc Warning 10311 side-channels** (3 sites: allowance check, sender-balance check, unwrap balance check): revert-vs-success lets an authorized spender binary-search balances/allowances. Inherent to revert-on-insufficient ERC-20 semantics on shielded storage — add an inline `// NOTE:` at each site + scope-doc entry; confirm the recommended idiom with Seismic. Do not ship the warnings undocumented.

---

## P2 — Comment / NatSpec style sweep (user ask #1)

Two trim commits (`8f8faed`, `2cb7a6c`) got the worst; **~150–170 over-verbose lines remain, plus ~25 missing `@param` lines to add back**. House style calibrated from main: tests nearly comment-free; internal functions = one-line `@dev` + full `@param`s; interfaces carry the NatSpec, implementations `@inheritdoc` only.

Per-file checklist (biggest wins first; full line references in the workflow digest):
1. `test/unit/projects/yieldToOne/MYieldToOne.t.sol` (~60 lines): main has 3 comment lines, branch has ~76 — nearly every test opens by restating its own name. Delete all narration; keep the precompile-mock note and the unregistered-recipient setup note; rename the 6 prose section banners to contract-element names.
2. `src/projects/yieldToOne/MYieldToOne.sol` (~25 lines + doc correctness): rewrite 11 internal-function `@dev` paragraphs to main's one-line `@dev` + `@param` idiom (**`_update` regressed — it lost the `@param`s it had on main**); delete the L219–222 design-rationale paragraph under the section divider; delete restating inline comments (L169, 178, 200, 213, 619) and the brittle "slot 8" cross-reference; shrink struct-field tutorials (L21–34) to three one-liners; fold bespoke dividers into main's generic sections.
3. `IMYieldToOne.sol` (~25 lines): errors to 1–2-line uniform prefix; rotation rationale stated once (in `setContractKey`), not twice; `Transfer(bytes)` event essay → 2-line `@notice` + 1-line indexer `@dev`; fix `@return` style on the suint256 overloads.
4. Makefile + foundry.toml (~16 lines): collapse the seismic banner and near-duplicate target comments; compress the `[profile.seismic]` 8-line tutorial to header + EOL comments.
5. Shell/python tooling (~40 lines, lowest audit relevance): `seismic-env.sh` 29-line header → purpose/usage/3-step install; `.husky/pre-commit` 4-line preamble → 1; `verify-seismic.py` docstring WHY/WHAT essay → 3–4 lines (keep USAGE/ENV).
6. Integration/FT tests + harnesses (~8 lines).
7. Finish: `sforge build --force` + unit suite green, single style commit citing `8f8faed`/`2cb7a6c` as prior art.

---

## P3 — Test suite repair & new shielded coverage (user ask #2)

**Current state (all empirically reproduced):**
- Configured seismic unit run: **369/369 green** across 11 suites (~1 min). MYieldToOne 88/88 + ForcedTransfer 23/23 — re-verified independently (111/111).
- **But the green is partly config-manufactured**: `foundry.toml` seismic `no_match_path` silently excludes `JMIExtension.t.sol` (52 tests) and all of `test/integration/**`. Forced under seismic, JMI = 39 pass / **13 fail** — 12× gated-`balanceOf` `Unauthorized`, 1× stale pause-vs-`UseShieldedTransfer` ordering. All 13 are stale pre-shielding API tests, not contract bugs. The `foundry.toml` comment "JMI runs under the default profile" is **false on this branch** (default profile compiles under neither stock forge nor ssolc-on-cancun) — so JMIExtension, which is in the deployable seismic build (the EIP-170 / `optimizer_runs=800` fix exists because of it), has **zero runnable tests**.
- Integration suite unrunnable everywhere: excluded under seismic, uncompilable under default, mainnet fork RPC rejects `eth_getFlaggedStorageAt`. Two latent bugs already in it (a `uint256` `transfer` call that reverts `UseShieldedTransfer`; ungated `balanceOf` reads in `MExtensionSystem.t.sol`).
- CI: all three workflows red on PR #116 (stock forge, dies at compile). No CI runs the seismic suite at all.
- Suite-health: no invariant tests anywhere (`make invariant` points at a nonexistent dir); encrypted-event pipeline covered only by concrete tests with mocked precompiles; bare `sforge test` without `--force` breaks all OZ-Upgrades suites (partial build-info).

**Work items:**
1. Migrate the 13 stale JMI tests to the shielded API (harness `getBalanceOf`, suint256 overloads, `UseShieldedTransfer` expectations); remove `JMIExtension.t.sol` from `no_match_path`; fix the false foundry.toml comment. Add JMI gate/allowlist/native-revert tests. (If JMI is declared out of audit scope instead: remove it from the seismic build and say so — current state is the worst of both.)
2. Fix the latent integration-test failures now (cheap; prevents auditor confusion).
3. New unit tests (sforge, mocked precompiles): precompile-failure paths for 0x65/0x68/0x66 (`PrecompileFailed` per address — currently zero failure-path tests); ciphertext fidelity + `vm.expectCall` input pinning; nonce monotonicity; zero-amount both branches (note: 0-amount transfers run the full ECDH path and consume a nonce); unregistered-recipient + no-key ordering; self-transfer; address(0). Gating-matrix completion: frozen recipient/caller on native path, de-list re-blocks native entry points, **residual-allowance pin** (allowance granted while allowlisted remains spendable via shielded `transferFrom` after de-listing — pin as intended), shielded-path `transferFrom` fuzz + insufficient-balance zeroed payload, unwrap insufficient-balance payload. FT suite: `forceTransfer`-to-registered-recipient stays plaintext-only + nonce untouched (dual-emit regression class), shielded-overload smoke tests, forceTransfer-works-while-paused pin.
4. Zero-privkey `setContractKey` test (with the P1 fix).
5. Invariant/simulation suite (repo `testFuzz_full` idiom, sforge-only): random op sequences asserting `sum(getBalanceOf(actors)) == totalSupply()`, `mToken.balanceOf(ext) >= totalSupply()`, nonce monotonicity. The suint256 balance rewrite is the riskiest change on the branch and currently has no property coverage.
6. Seismic testnet/devnet integration suite (`test/integration/seismic/`) + small off-chain decryptor script: signed-read gating (plain `eth_call` zeroes msg.sender → `Unauthorized`), `setContractKey` via TxSeismic 0x4A, real ECDH/HKDF/AES-GCM round-trip decryption, off-curve-key behavior pin, SwapFacility wrap/unwrap E2E, allowlist-config assertion. Capture run output in the audit package.
7. Reproducible green baseline: set `force = true` in `[profile.seismic]` (or document `--force`); resolve the OZ `upgrades-core` validation flake from a pristine clone (two runs back-to-back; pre-build full build-info / pin `@openzeppelin/upgrades-core` / `unsafeSkipAllChecks` for unit profiles) — one digest saw nondeterministic failures, another saw deterministic green; settle it empirically and have the runbook cite a logged run.

---

## P4 — Makefile / tooling sforge migration (user ask #3)

The Makefile is ~10% migrated; `make build`, `make tests` (default), `make coverage`, `make gas-report`, `make slither` and ~60 deploy/upgrade/propose targets all invoke stock forge and die on `suint256` (verified: the **only blocker-severity finding** of the whole analysis — an auditor cloning the repo has no working build path and README has zero Seismic instructions).

1. `profile ?= seismic` (Makefile:30) + repo-local PATH prepend + fail-loud guard ("run: source scripts/seismic-env.sh && sfoundryup") when sforge is absent. Do **not** auto-source seismic-env.sh from recipes ($0-resolution breaks under make's /bin/sh) and do **not** flip `[profile.default]` to mercury (breaks stock-forge `clean`/`update` and test.sh's name-based binary selection; `[profile.seismic]` inherits optimizer/ffi/build_info from default — load-bearing for deployed bytecode).
2. Shared `FORGE_BIN = $(if $(filter seismic,$(profile)),sforge,forge)`; apply to `build`/`sizes` (switch off `-p production`), `coverage` (verified working under sforge: MYieldToOne 100% lines / 97.8% branches scoped), `gas-report` (verified working). Generate lcov + gas + sizes artifacts for the audit package.
3. `make integration`: currently **vacuous green** (0 tests, exit 0) under seismic — make it fail loudly with the devnet pointer, or gate on `SEISMIC_DEVNET_RPC_URL`.
4. Bulk-delete dead targets (branch never merges back): `deploy-local`/`deploy-sepolia` (script doesn't exist), `invariant` (no dir), `deploy-yield-to-one` + `-sepolia`, forced-transfer `-citrea`/`-sepolia` variants (**now inherit sforge+mercury and would ship Seismic-only bytecode to normal EVM chains**), and the ~60 stock-forge deploy/upgrade/propose/execute blocks for non-Seismic chains. Fix `-local` (inherits broken `--verify --verifier ''` flags; needs `BROADCAST_ONLY_FLAGS` + sanvil note).
5. `slither`: not runnable on mercury/ssolc builds (crytic-compile can't ingest shielded types) — replace target body with a loud explanatory error; record in the scope doc ("last clean static-analysis baseline = merge-base 87a2f42 on main"), optionally attach a fresh main-branch slither report.
6. CI: replace the three red workflows with one `test-seismic.yml` (checkout w/ submodules, install **pinned** seismic toolchain, `make tests profile=seismic` + sizes check). `[profile.ci]` inherits cancun — give it `evm_version = "mercury"` + the seismic no_match_path or run CI with profile=seismic.
7. `.husky/pre-commit`: fail-fast install hint instead of silent stock-forge fallback (which dies in an inscrutable parse error); optionally drop `--force` from the pre-commit path for commit speed.
8. `package.json`: prune/repoint `compile`/`doc`/`slither`/`deploy-*` after migration. Lint stack verified seismic-clean (prettier + solhint parse shielded sources fine) — no work needed.
9. foundry.toml: comment documenting profile inheritance + that ssolc ignores `solc_version`; decide fate of `[profile.production]`.

---

## P5 — Deploy/execution script coherence (user ask #4)

Answered in P0 (yes — `set-contract-key` shell tool via `scast send --seismic`, plus the configure script). Remaining coherence items:
1. `.env.example`: add a `# Seismic` block (RPC/verifier URLs incl. full `command_api` path, mainnet placeholders, `SWAP_FACILITY`, set-contract-key inputs; key material itself → 1Password, never .env).
2. Key custody policy in the script header + runbook: fresh keypair per derived deployment; ECDH symmetry means recipients never need the contract privkey — the off-chain copy only lets M0 ops decrypt all payloads; loss degrades ops decryption only; rotation impossible.
3. `registerPublicKey` story: dapp/SDK concern (plain tx, pubkey is public); optional `make register-public-key-seismic-testnet` convenience for QA; infra contracts never need registration (empty-ciphertext fallback + gated balanceOf).
4. Seismic-mainnet go-live checklist: `SEISMIC_MAINNET_*` env vars AND `script/Config.sol` chain branch (currently fails closed in three places — good, but document).
5. JMIExtension-to-Seismic onboarding: move the 4-line Makefile variant pattern out of untracked CLAUDE.local.md into a committed comment/runbook; then configure-extension + set-contract-key for the new proxy.

---

## P6 — Audit package & vectors not in the original ask (completeness critic)

The code work above is necessary but **the audit package itself does not exist**:

1. **`AUDIT-SCOPE.md` + git tag** (e.g. `audit/seismic-v1`): frozen commit; in-scope list (MYieldToOne, MYieldToOneForcedTransfer, IMYieldToOne, the 1-line MExtension change, explicit JMI in/out decision, the 12-line lib/common delta **inline**); system-context table for live 5124 dependencies (M `0x866A2BF4…`, SwapFacility `0xB6807116…`, Portal, LimitOrderProtocol, CreateX) with source repo + commit (evm-m-suite-deployment `feat/seismic` c63e7a8 + upstream branches) and in/out-of-scope status; accepted-risk list (three 10311 sites, Approval-event decision, ERC-20 deviations); floating-pragma rationale sentence (converts a guaranteed SWC-103 finding into a documented decision).
2. **README rewrite**: it is verbatim main's — describes MYieldToOne as "includes a blacklist", carries the old audits' "In-Scope Extensions" heading, lists every chain except Seismic. Add the build/toolchain section (P4) + 5124 deployment table + "this branch never merges" banner.
3. **Pin the toolchain** (`TOOLCHAIN.md` or scope-doc section): sforge 1.3.5-v0.2.0 / ssolc `0.8.31-develop.2026.4.29+commit.cd9163d8` / seismic-foundry ref for sfoundryup — currently installed unpinned ("latest") and recorded only in untracked files; the audited bytecode depends on a pre-release compiler fork, which is itself a trust assumption for the scope doc (alongside TEE/precompiles).
4. **Fix `foundry.lock`**: tracked lock pins lib/common at `v1.5.0`/`613d2d9` while the gitlink is `a1fbf37` — a fresh forge-driven materialization could silently roll the dependency back. Also **pin lib/common to the SHA** (`.gitmodules` branch ref is a moving target); avoid `forge update` until handoff.
5. **Trust-model/roles doc**: every role + ProxyAdmin owner currently = one EOA (`0x12b1A422…`), recorded nowhere committed. On a privacy token, admin/upgrade authority = deanonymization authority (`setContractKey`, `setAllowlisted` ⇒ read any balance; implementation swap ⇒ dump all shielded state). Table of role → current testnet holder → intended mainnet custody.
6. **Prior-audit mapping** (`audits/README.md`): seven PDF reports cover main's unshielded code under stock solc — state explicitly that none cover the Seismic diff or ssolc-built bytecode (including recompiled "unchanged" contracts).
7. **ERC-20 deviations table**: third-party `balanceOf` reverts; `transfer(uint256)` always reverts; `approve(uint256)` infra-spender-only; both permits revert; second `Transfer(bytes)` event shape — integrators/auditors need this as spec, not NatSpec fragments.
8. **Monitoring/indexing note**: per-holder amounts exist only inside per-recipient ciphertexts; who runs the decryptor, with what key controls; what's observable without the key (supply, backing, infra flows, transfer graph via indexed topics); confirm Envio/subgraph indexers handle or deliberately ignore the `Transfer(bytes)` overload.
9. **Un-ignore the Seismic design docs** (`docs/seismic-src20-flow-diagrams.md`, encrypted-events review) into a tracked path — the auditor should receive the design rationale in-repo.
10. `.planning/` is gitignored ⇒ no audit impact; optionally refresh/delete. Migrate the load-bearing facts living only in CLAUDE.local.md (verify recipe, addresses, onboarding pattern) into the committed docs above.

---

## Conflicts found between analyses (resolved by independent verification)

| Claim | Resolution |
|---|---|
| "Proxy was never actually deployed" (security) vs live (deploy) | **Live.** `eth_getCode` non-empty for proxy + impl; `name()` = "Seismic Dollar"; `contractPublicKey()` = `0x`. The security agent was misled by the missing committed broadcast (itself a finding). |
| 369/369 deterministic green (tests) vs nondeterministic failures (coverage) | Unresolved — settle empirically from a pristine clone (P3.7). Likely variable: build-cache state vs the OZ upgrades-core ffi validation. |
| `.env` verifier URL fixed vs still truncated | Re-check once during P5.1; harmless either way (Makefile supplies the full URL). |

## Suggested execution order on `seismic-audit-readiness`

1. **P0** (ops exposure; needs your go-ahead for the on-chain txs) — small, independent, closes the live griefing window.
2. **P1** decisions + small contract diffs — they change the audit diff, so land before everything else freezes.
3. **P3.1–P3.5** test repair + new unit/invariant suites (validates P1 changes).
4. **P2** comment sweep (single style commit once the source is stable).
5. **P4** Makefile/CI migration + **P3.7** green-baseline proof.
6. **P3.6** testnet integration suite (needs P0 done so the deployed stack is usable).
7. **P6** audit package, tag the freeze commit last.
