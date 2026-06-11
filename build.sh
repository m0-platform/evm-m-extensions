#!/usr/bin/env bash
set -e

sizes=false

while getopts p:s flag; do
	case "${flag}" in
	p) profile=${OPTARG} ;;
	s) sizes=true ;;
	esac
done

export FOUNDRY_PROFILE=$profile

# Use the Seismic-flavored forge for the seismic profile (mercury EVM, ssolc).
# Stock forge can't parse shielded types like suint256.
if [ "$FOUNDRY_PROFILE" = "seismic" ]; then
	forge_bin=sforge
else
	forge_bin=forge
fi

echo Using profile: $FOUNDRY_PROFILE
echo Forge binary: $forge_bin

if [ "$sizes" = false ]; then
	"$forge_bin" build --skip '*/test/**' '*/script/**' --extra-output-files abi
else
	"$forge_bin" build --skip '*/test/**' '*/script/**' --extra-output-files abi --sizes
fi
