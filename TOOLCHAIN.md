# Toolchain Pins (Seismic branch)

This branch builds only with Seismic's Foundry/solc forks. The pins below are the exact
versions that produced the deployed Seismic-testnet bytecode and that the audit must be
reproduced with. `scripts/seismic-env.sh` puts the repo-local install (`.seismic-toolchain/`,
git-ignored) on `PATH`.

## Pinned versions

| Tool                      | Version                                  | Commit                                     | Source / release                                                |
| ------------------------- | ---------------------------------------- | ------------------------------------------ | --------------------------------------------------------------- |
| `sforge`                  | `1.3.5-v0.2.0`                           | `6065731fd5a1367603f6adac38f2fa174cbd66b8` | `SeismicSystems/seismic-foundry`, release tag `v0.2.0`          |
| `scast`                   | `1.3.5-v0.2.0`                           | `6065731fd5a1367603f6adac38f2fa174cbd66b8` | same release                                                     |
| `sanvil`                  | `1.3.5-v0.2.0`                           | `6065731fd5a1367603f6adac38f2fa174cbd66b8` | same release                                                     |
| `ssolc`                   | `0.8.31-develop.2026.4.29+commit.cd9163d8` | `cd9163d8d7926fee2e2d3fe1f9609548e0414bf1` | `SeismicSystems/seismic-solidity`, release tag `cd9163d`        |
| `sfoundryup` (installer)  | `0.1.0`                                  | —                                          | `seismic-foundry` branch `seismic`, `sfoundryup/install`        |

Explorer-facing compiler label: **`v0.8.31+commit.cd9163d8`** — the socialscan verify API
rejects the full prerelease string, so `script/verify-seismic.py` submits
`v<major.minor.patch>+commit.<hash>` with the `-develop.<date>` tag stripped.

## Pinned install

Verified working 2026-06-11 (clean `FOUNDRY_DIR`, attestation SHA-256 checks pass):

```bash
source scripts/seismic-env.sh   # sets FOUNDRY_DIR=.seismic-toolchain + PATH
curl -L -H "Accept: application/vnd.github.v3.raw" \
  "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
sfoundryup -i v0.2.0
```

`sfoundryup -i v0.2.0` downloads the prebuilt `sforge`/`scast`/`sanvil` for release tag
`v0.2.0` and verifies each binary's SHA-256 against the release's sigstore attestation.
This is the most pinned invocation the installer supports for binaries.
(`sfoundryup -C 6065731fd5a1367603f6adac38f2fa174cbd66b8` builds the same commit from
source, but needs `cargo` and — unlike the binary path — installs no `ssolc` at all.)

### ssolc pinning gap

`sfoundryup` has **no flag to pin ssolc**: every binary install fetches the *latest*
`seismic-solidity` release at install time. As of 2026-06-11 the latest release is
`cd9163d` — exactly our pin — so a fresh install currently reproduces the toolchain.
Once Seismic publishes a newer ssolc, pin it manually:

```bash
# <os>-<arch>: linux-x86_64 | linux-arm64 | macos-arm64 | macos-14-x86_64 ...
curl -fsSL -o /tmp/ssolc.tar.gz \
  "https://github.com/SeismicSystems/seismic-solidity/releases/download/cd9163d/ssolc-macos-arm64.tar.gz"
tar -xzf /tmp/ssolc.tar.gz -C /tmp && install -m 755 /tmp/solc/solc "$FOUNDRY_DIR/bin/ssolc"
ssolc --version   # must report 0.8.31-develop.2026.4.29+commit.cd9163d8
```

Note: `solc_version = "0.8.26"` in `foundry.toml` does not select the compiler for
seismic builds — `sforge` uses the `ssolc` binary from the toolchain install. The pin
above is therefore the only thing fixing the compiler.

## Platform trust assumption

The pre-release solc fork and the mercury EVM are a **trusted-but-unaudited platform
assumption**. The deployed bytecode depends on a `-develop` prerelease compiler, a custom
EVM revision (shielded `suint256`/`sbytes32` storage, `eth_getFlaggedStorageAt`, signed
reads), and Seismic precompiles (`0x65` ECDH, `0x66` AES-GCM, `0x68` HKDF). None of these
have public third-party audits; they are out of scope for the contract audit and recorded
as platform assumptions in [AUDIT-SCOPE.md](AUDIT-SCOPE.md).

## Dependency pin: lib/common

The audit pin for `lib/common` is the **git submodule gitlink**
`a1fbf37b0ab10b0f8e71223793a0fd6af77b527d` (branch `feat/erc20-virtual`; 12-line delta vs
tag `v1.5.1`, embedded in [AUDIT-SCOPE.md](AUDIT-SCOPE.md)). `foundry.lock` records the
same rev. The `branch = feat/erc20-virtual` field in `.gitmodules` is a **moving
pointer** consumed by `git submodule update --remote` and `forge update` — do **not** run
either before the audit handoff, or the gitlink may silently advance past the pin.
