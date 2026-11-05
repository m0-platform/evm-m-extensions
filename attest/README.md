# M0 nonce 22 with native Forge Attest capture

This integration adds only a claim, workflow and instructions. It does not change
existing contracts, proposal scripts, Foundry configuration, dependency gitlinks
or CI workflows. The claim reproduces historical upstream commit
`9e194fa9410edaaa467a324a55fa07af0e65f5a8` directly, without an adapter, capture
helper, JSON writer or additional executable code in this repository.

The claim runs the original `ProposeTransferSwapFacilityOwner` script directly
with `capture = "safe-utils"`. Forge Attest captures its curl POST request outside
the producer checkout and returns HTTP 201 locally. The supported transport never
forwards the request. It checks the endpoint Safe and request nonce, rejects
missing, repeated or unclaimed proposals, and verifies the raw request, canonical
transaction and Safe hash through the existing reader and independent derivations.

The original script requires `PRIVATE_KEY` to sign its request locally. The claim
supplies public test key `1`, not an owner key. No proposal is submitted and no
owner approval is created. Do not use `--broadcast` or `--attest` for this demo.
Capture adapts the reviewed bare-curl transport; it is not a network sandbox.

Use Foundry 1.8.1 and an Ethereum archive RPC:

```bash
git clone https://github.com/crossecute/forge-attest ../m0-forge-attest
git -C ../m0-forge-attest checkout 27727236af75dda63698d86ef3984b5206309634
export MAINNET_RPC_URL='YOUR_ETHEREUM_ARCHIVE_RPC_URL'
../m0-forge-attest/attest.sh --config "$PWD/attest-nonce22.toml" --require-live --json
```

The original per-call simulation runs at Ethereum block 23834855. The required
service comparison checks the already-executed nonce 22 record. Cast, Solidity
and the service must agree on:

`0xab7012df75fc7907ace6cb632bc3865ded2956c33fa2aab2d4b3d85167d485a6`.

Full signed Safe execution and extra post-state assertions are not part of this
demo. Transaction equality does not authenticate the original operator's build
revision or establish whether the permissions change is appropriate.

See the [M0 case study](https://github.com/crossecute/research/blob/main/case-studies/m0/M0_Forge_Attest_Case_Study.md)
for the transaction's three calls, evidence and verification scope.
