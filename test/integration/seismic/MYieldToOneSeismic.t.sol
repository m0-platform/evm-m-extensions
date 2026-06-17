// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Vm } from "../../../lib/forge-std/src/Vm.sol";
import { console } from "../../../lib/forge-std/src/console.sol";

import { Upgrades } from "../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MYieldToOne } from "../../../src/projects/yieldToOne/MYieldToOne.sol";
import { IMYieldToOne } from "../../../src/projects/yieldToOne/interfaces/IMYieldToOne.sol";

import { MYieldToOneHarness } from "../../harness/MYieldToOneHarness.sol";

import { BaseUnitTest } from "../../utils/BaseUnitTest.sol";

/// @dev Runs against the REAL Seismic precompiles (0x65 ECDH+KDF, 0x66/0x67 AES-GCM, 0x68 HKDF) — no mocks.
///      Requires sforge's seismic EVM (mercury); see README.md in this directory.
contract MYieldToOneSeismicIntegrationTests is BaseUnitTest {
    // Pinned precompile vectors, cross-validated off-chain (RFC 5869 HKDF-SHA256, AES-256-GCM,
    // libsecp256k1 ECDH) and reproduced by script/decrypt-transfer-event.py --self-test.
    bytes32 internal constant ECDH_VECTOR_OUT = 0xa59676edf7d8f47a0cc8ac42e29566d4a1763eeeba8794d6a196029a1477f147;
    bytes32 internal constant HKDF_VECTOR_OUT = 0xeb3cb17dcdc55d1119c98cac1e12bb13a95f81b50a0784750bdcf92787c4985e;
    bytes internal constant AES_VECTOR_OUT =
        hex"bae51be0c992f7c0c34d03a9431aebdc7732c399729054925a094d8f373d65c18c9eec49034da029df615639016e16c8";

    // Generator point G compressed (privkey 1's public key).
    bytes internal constant COMPRESSED_G = hex"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
    // 33 bytes, valid 0x02 prefix, x = 5 is not on secp256k1 (5^3 + 7 is a non-residue).
    bytes internal constant OFF_CURVE_KEY = hex"020000000000000000000000000000000000000000000000000000000000000005";

    bytes32 internal constant TRANSFER_BYTES_TOPIC = keccak256("Transfer(address,address,bytes32,bytes)");
    bytes32 internal constant APPROVAL_BYTES_TOPIC = keccak256("Approval(address,address,bytes32,bytes)");

    MYieldToOneHarness public mYieldToOne;

    Vm.Wallet public contractWallet;
    Vm.Wallet public recipientWallet;

    address public recipient;

    function setUp() public override {
        super.setUp();

        mYieldToOne = MYieldToOneHarness(
            Upgrades.deployTransparentProxy(
                "MYieldToOneHarness.sol:MYieldToOneHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldToOne.initialize.selector,
                    "Seismic Dollar",
                    "USDS",
                    yieldRecipient,
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    pauser
                ),
                mExtensionDeployOptions
            )
        );

        registrar.setEarner(address(mYieldToOne), true);

        contractWallet = vm.createWallet("seismic contract key");
        recipientWallet = vm.createWallet("seismic recipient key");
        recipient = recipientWallet.addr;

        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(contractWallet.privateKey)), _compressed(contractWallet));

        vm.prank(recipient);
        mYieldToOne.registerPublicKey(_compressed(recipientWallet));
    }

    /* ============ precompile semantics (pinned vectors) ============ */

    function test_precompile_ecdh_pinnedVector() external view {
        // 0x65 = ECDH + HKDF-SHA256(salt=none, info="aes-gcm key"): already a symmetric key, not a raw point.
        assertEq(_ecdh(bytes32(uint256(1)), COMPRESSED_G), ECDH_VECTOR_OUT);
    }

    function test_precompile_ecdh_symmetry() external view {
        assertEq(
            _ecdh(bytes32(contractWallet.privateKey), _compressed(recipientWallet)),
            _ecdh(bytes32(recipientWallet.privateKey), _compressed(contractWallet))
        );
    }

    function test_precompile_ecdh_offCurvePoint_fails() external view {
        (bool success, ) = address(0x65).staticcall(abi.encodePacked(bytes32(uint256(1)), OFF_CURVE_KEY));
        assertFalse(success);
    }

    function test_precompile_hkdf_pinnedVector() external view {
        // 0x68 = HKDF-SHA256(salt=none, info="seismic_hkdf_105"), 32-byte output.
        assertEq(_hkdf(bytes32(uint256(0xdeadbeef))), HKDF_VECTOR_OUT);
    }

    function test_precompile_aesGcm_pinnedVector_andInverse() external view {
        bytes32 key = bytes32(uint256(0x42));
        bytes12 nonce = bytes12(uint96(7));
        bytes memory plaintext = abi.encode(uint256(123456));

        // 0x66 = AES-256-GCM encrypt; output = ciphertext || 16-byte tag.
        bytes memory ciphertext = _aesGcmEncrypt(key, nonce, plaintext);
        assertEq(ciphertext, AES_VECTOR_OUT);

        // 0x67 = AES-256-GCM decrypt (inverse, tag-checked).
        assertEq(_aesGcmDecrypt(key, nonce, ciphertext), plaintext);
    }

    /* ============ shielded transfer: real-key decryption round-trip ============ */

    function test_shieldedTransfer_realKeys_recipientDecrypts() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);
        mYieldToOne.setTotalSupply(amount);

        vm.recordLogs();

        vm.prank(alice);
        mYieldToOne.transfer(recipient, suint256(amount));

        bytes memory ciphertext = _extractPayload(TRANSFER_BYTES_TOPIC, alice, recipient);

        // Contract-side determinism: re-derive the exact emit pipeline.
        bytes32 contractSideKey = _hkdf(_ecdh(bytes32(contractWallet.privateKey), _compressed(recipientWallet)));
        bytes12 nonce = bytes12(keccak256(abi.encode(alice, recipient, uint256(1))));
        assertEq(ciphertext, _aesGcmEncrypt(contractSideKey, nonce, abi.encode(amount)));

        // Recipient-side decryption: only the recipient's privkey + the public contract key.
        bytes32 recipientSideKey = _hkdf(_ecdh(bytes32(recipientWallet.privateKey), _compressed(contractWallet)));
        assertEq(recipientSideKey, contractSideKey);
        assertEq(abi.decode(_aesGcmDecrypt(recipientSideKey, nonce, ciphertext), (uint256)), amount);

        _logDecryptorVector(ciphertext);
    }

    function test_shieldedTransferFrom_realKeys_recipientDecrypts() external {
        uint256 amount = 250e6;
        mYieldToOne.setBalanceOf(alice, amount);
        mYieldToOne.setTotalSupply(amount);
        mYieldToOne.setShieldedAllowance(alice, carol, amount);

        vm.recordLogs();

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, recipient, suint256(amount));

        bytes memory ciphertext = _extractPayload(TRANSFER_BYTES_TOPIC, alice, recipient);

        // Nonce binds (sender, recipient), not the spender.
        bytes12 nonce = bytes12(keccak256(abi.encode(alice, recipient, uint256(1))));
        bytes32 key = _hkdf(_ecdh(bytes32(recipientWallet.privateKey), _compressed(contractWallet)));
        assertEq(abi.decode(_aesGcmDecrypt(key, nonce, ciphertext), (uint256)), amount);
    }

    function test_shieldedApprove_realKeys_spenderDecrypts() external {
        uint256 amount = 777e6;

        vm.recordLogs();

        vm.prank(alice);
        mYieldToOne.approve(recipient, suint256(amount));

        bytes memory ciphertext = _extractPayload(APPROVAL_BYTES_TOPIC, alice, recipient);

        bytes12 nonce = bytes12(keccak256(abi.encode(alice, recipient, uint256(1))));
        bytes32 key = _hkdf(_ecdh(bytes32(recipientWallet.privateKey), _compressed(contractWallet)));
        assertEq(abi.decode(_aesGcmDecrypt(key, nonce, ciphertext), (uint256)), amount);
    }

    function test_shieldedTransfer_sequentialNonces_uniqueCiphertexts() external {
        uint256 amount = 100e6;
        mYieldToOne.setBalanceOf(alice, 2 * amount);
        mYieldToOne.setTotalSupply(2 * amount);

        bytes32 key = _hkdf(_ecdh(bytes32(recipientWallet.privateKey), _compressed(contractWallet)));

        vm.recordLogs();
        vm.prank(alice);
        mYieldToOne.transfer(recipient, suint256(amount));
        bytes memory ciphertext1 = _extractPayload(TRANSFER_BYTES_TOPIC, alice, recipient);

        vm.recordLogs();
        vm.prank(alice);
        mYieldToOne.transfer(recipient, suint256(amount));
        bytes memory ciphertext2 = _extractPayload(TRANSFER_BYTES_TOPIC, alice, recipient);

        assertNotEq(keccak256(ciphertext1), keccak256(ciphertext2));

        bytes12 nonce1 = bytes12(keccak256(abi.encode(alice, recipient, uint256(1))));
        bytes12 nonce2 = bytes12(keccak256(abi.encode(alice, recipient, uint256(2))));
        assertEq(abi.decode(_aesGcmDecrypt(key, nonce1, ciphertext1), (uint256)), amount);
        assertEq(abi.decode(_aesGcmDecrypt(key, nonce2, ciphertext2), (uint256)), amount);
    }

    /* ============ off-curve registered key ============ */

    function test_shieldedTransfer_offCurveRegisteredKey_revertsPrecompileFailed() external {
        uint256 amount = 10e6;
        mYieldToOne.setBalanceOf(alice, amount);
        mYieldToOne.setTotalSupply(amount);

        // Passes the contract's shape check (33 bytes, 0x02 prefix) but is not a curve point.
        vm.prank(bob);
        mYieldToOne.registerPublicKey(OFF_CURVE_KEY);

        // Inbound transfers to that account revert deterministically — no garbage ciphertext.
        vm.expectRevert(abi.encodeWithSelector(IMYieldToOne.PrecompileFailed.selector, address(0x65)));
        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));

        // Self-inflicted only: re-registering a valid key restores transfers.
        vm.prank(bob);
        mYieldToOne.registerPublicKey(_compressed(recipientWallet));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
    }

    /* ============ wrap -> shielded transfer -> unwrap (SwapFacility E2E) ============ */

    function test_wrap_shieldedTransfer_unwrap_e2e() external {
        uint256 amount = 5_000e6;
        mToken.setBalanceOf(alice, amount);

        vm.prank(alice);
        mToken.approve(address(swapFacility), amount);

        vm.prank(alice);
        swapFacility.swapInM(address(mYieldToOne), amount, alice);

        assertEq(mYieldToOne.getBalanceOf(alice), amount);
        assertEq(mYieldToOne.totalSupply(), amount);

        vm.recordLogs();
        vm.prank(alice);
        mYieldToOne.transfer(recipient, suint256(amount));

        bytes memory ciphertext = _extractPayload(TRANSFER_BYTES_TOPIC, alice, recipient);
        bytes12 nonce = bytes12(keccak256(abi.encode(alice, recipient, uint256(1))));
        bytes32 key = _hkdf(_ecdh(bytes32(recipientWallet.privateKey), _compressed(contractWallet)));
        assertEq(abi.decode(_aesGcmDecrypt(key, nonce, ciphertext), (uint256)), amount);

        vm.prank(admin);
        swapFacility.grantRole(M_SWAPPER_ROLE, recipient);

        vm.prank(recipient);
        mYieldToOne.approve(address(swapFacility), amount);

        vm.prank(recipient);
        swapFacility.swapOutM(address(mYieldToOne), amount, recipient);

        assertEq(mYieldToOne.getBalanceOf(recipient), 0);
        assertEq(mYieldToOne.totalSupply(), 0);
        assertEq(mToken.balanceOf(recipient), amount);
    }

    /* ============ helpers ============ */

    function _ecdh(bytes32 privKey, bytes memory peerPubKey) internal view returns (bytes32) {
        (bool success, bytes memory result) = address(0x65).staticcall(abi.encodePacked(privKey, peerPubKey));
        require(success, "ecdh precompile failed");
        return abi.decode(result, (bytes32));
    }

    function _hkdf(bytes32 ikm) internal view returns (bytes32) {
        (bool success, bytes memory result) = address(0x68).staticcall(abi.encodePacked(ikm));
        require(success, "hkdf precompile failed");
        return abi.decode(result, (bytes32));
    }

    function _aesGcmEncrypt(bytes32 key, bytes12 nonce, bytes memory plaintext) internal view returns (bytes memory) {
        (bool success, bytes memory ciphertext) = address(0x66).staticcall(abi.encodePacked(key, nonce, plaintext));
        require(success, "aes-gcm encrypt precompile failed");
        return ciphertext;
    }

    function _aesGcmDecrypt(bytes32 key, bytes12 nonce, bytes memory ciphertext) internal view returns (bytes memory) {
        (bool success, bytes memory plaintext) = address(0x67).staticcall(abi.encodePacked(key, nonce, ciphertext));
        require(success, "aes-gcm decrypt precompile failed");
        return plaintext;
    }

    function _compressed(Vm.Wallet memory wallet) internal pure returns (bytes memory) {
        return abi.encodePacked(wallet.publicKeyY % 2 == 0 ? bytes1(0x02) : bytes1(0x03), bytes32(wallet.publicKeyX));
    }

    function _extractPayload(bytes32 topic, address from, address to) internal returns (bytes memory payload) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics[0] == topic &&
                logs[i].topics[1] == bytes32(uint256(uint160(from))) &&
                logs[i].topics[2] == bytes32(uint256(uint160(to)))
            ) {
                return abi.decode(logs[i].data, (bytes));
            }
        }
        revert("payload log not found");
    }

    function _logDecryptorVector(bytes memory ciphertext) internal view {
        console.log("script/decrypt-transfer-event.py test vector:");
        console.log("  --privkey (recipient)");
        console.logBytes32(bytes32(recipientWallet.privateKey));
        console.log("  --peer-pubkey (contract)");
        console.logBytes(_compressed(contractWallet));
        console.log("  --from");
        console.log(alice);
        console.log("  --to");
        console.log(recipient);
        console.log("  --nonce-counter 1");
        console.log("  --ciphertext");
        console.logBytes(ciphertext);
    }
}
