#!/usr/bin/env bash
# Seismic toolchain env — puts the repo-local sforge/ssolc/sanvil install at .seismic-toolchain/ (git-ignored) on PATH.
#
# Usage:  source scripts/seismic-env.sh
#         (any bash/zsh shell; lasts until the shell exits; sforge auto-uses FOUNDRY_PROFILE=seismic)
#
# Install:  1. source scripts/seismic-env.sh
#           2. curl -L -H "Accept: application/vnd.github.v3.raw" "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
#           3. sfoundryup   (fetches sforge/ssolc/sanvil into $FOUNDRY_DIR/bin; check with sforge --version)

# Resolve repo root from this script's own path (works when sourced from any cwd).
__SEISMIC_ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SEISMIC_REPO_ROOT="$(cd "$__SEISMIC_ENV_SH_DIR/.." && pwd)"

export FOUNDRY_DIR="$SEISMIC_REPO_ROOT/.seismic-toolchain"
export FOUNDRY_BIN_DIR="$FOUNDRY_DIR/bin"

# Only prepend if not already present (avoids growing PATH on repeated sources).
case ":$PATH:" in
    *":$FOUNDRY_BIN_DIR:"*) ;;
    *) export PATH="$FOUNDRY_BIN_DIR:$PATH" ;;
esac

# Pin FOUNDRY_PROFILE=seismic for sforge (mercury EVM, shielded types); stock `forge` is untouched; override per-call with `FOUNDRY_PROFILE=default sforge ...`.
sforge() {
    FOUNDRY_PROFILE="${FOUNDRY_PROFILE:-seismic}" command sforge "$@"
}

# Surface a one-line confirmation so the user knows the env is active.
if [ -x "$FOUNDRY_BIN_DIR/sforge" ]; then
    echo "seismic-env: ready — $($FOUNDRY_BIN_DIR/sforge --version 2>/dev/null | head -1) (sforge auto-uses FOUNDRY_PROFILE=seismic)"
else
    echo "seismic-env: FOUNDRY_DIR=$FOUNDRY_DIR (binaries not yet installed — run sfoundryup)"
fi

unset __SEISMIC_ENV_SH_DIR
