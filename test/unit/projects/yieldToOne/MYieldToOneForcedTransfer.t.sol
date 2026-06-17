// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Vm } from "../../../../lib/forge-std/src/Vm.sol";

import { IERC20 } from "../../../../lib/common/src/interfaces/IERC20.sol";

import { IAccessControl } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { Upgrades, UnsafeUpgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MYieldToOneForcedTransfer } from "../../../../src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";
import { IMYieldToOne } from "../../../../src/projects/yieldToOne/interfaces/IMYieldToOne.sol";

import { IForcedTransferable } from "../../../../src/components/forcedTransferable/IForcedTransferable.sol";
import { IFreezable } from "../../../../src/components/freezable/IFreezable.sol";

import { MYieldToOneForcedTransferHarness } from "../../../harness/MYieldToOneForcedTransferHarness.sol";
import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract MYieldToOneForcedTransferUnitTest is BaseUnitTest {
    MYieldToOneForcedTransferHarness public mYieldToOneForcedTransfer;

    string public constant NAME = "HALO USD";
    string public constant SYMBOL = "HALO USD";

    function setUp() public override {
        super.setUp();

        mYieldToOneForcedTransfer = MYieldToOneForcedTransferHarness(
            Upgrades.deployTransparentProxy(
                "MYieldToOneForcedTransferHarness.sol:MYieldToOneForcedTransferHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldToOneForcedTransfer.initialize.selector,
                    NAME,
                    SYMBOL,
                    yieldRecipient,
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    pauser,
                    forcedTransferManager,
                    allowlistAdmin
                ),
                mExtensionDeployOptions
            )
        );

        vm.prank(allowlistAdmin);
        mYieldToOneForcedTransfer.grantRole(ALLOWLIST_MANAGER_ROLE, admin);

        registrar.setEarner(address(mYieldToOneForcedTransfer), true);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mYieldToOneForcedTransfer.name(), NAME);
        assertEq(mYieldToOneForcedTransfer.symbol(), SYMBOL);
        assertEq(mYieldToOneForcedTransfer.decimals(), 6);
        assertEq(mYieldToOneForcedTransfer.mToken(), address(mToken));
        assertEq(mYieldToOneForcedTransfer.swapFacility(), address(swapFacility));
        assertEq(mYieldToOneForcedTransfer.yieldRecipient(), yieldRecipient);

        assertTrue(mYieldToOneForcedTransfer.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldToOneForcedTransfer.hasRole(FREEZE_MANAGER_ROLE, freezeManager));
        assertTrue(mYieldToOneForcedTransfer.hasRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager));
        assertTrue(mYieldToOneForcedTransfer.hasRole(PAUSER_ROLE, pauser));
        assertTrue(mYieldToOneForcedTransfer.hasRole(FORCED_TRANSFER_MANAGER_ROLE, forcedTransferManager));
    }

    function test_initialize_zeroForcedTransferManager() external {
        address implementation = address(new MYieldToOneForcedTransferHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IForcedTransferable.ZeroForcedTransferManager.selector);
        mYieldToOneForcedTransfer = MYieldToOneForcedTransferHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldToOneForcedTransfer.initialize.selector,
                    NAME,
                    SYMBOL,
                    yieldRecipient,
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    pauser,
                    address(0),
                    allowlistAdmin
                )
            )
        );
    }

    /* ============ forceTransfer ============ */

    function test_forceTransfer_succeedsForManager() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(address(alice), amount);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), 0);

        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freeze(alice);

        vm.prank(forcedTransferManager);
        mYieldToOneForcedTransfer.forceTransfer(alice, bob, amount);

        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), amount);
    }

    function test_forceTransfer_revertsWhenNotFrozen() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(address(alice), amount);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), 0);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, alice));
        vm.prank(forcedTransferManager);
        mYieldToOneForcedTransfer.forceTransfer(alice, bob, amount);

        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), amount);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), 0);
    }

    function test_forceTransfer_arrayLengthMismatch() public {
        address[] memory frozenAccounts = new address[](2);
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](2);

        frozenAccounts[0] = alice;
        frozenAccounts[1] = bob;
        amounts[0] = 1_000e6;
        amounts[1] = 2_000e6;
        recipients[0] = carol;

        vm.prank(forcedTransferManager);
        vm.expectRevert(IForcedTransferable.ArrayLengthMismatch.selector);
        mYieldToOneForcedTransfer.forceTransfers(frozenAccounts, recipients, amounts);
    }

    function test_forceTransfer_revertsForNonManager() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(address(alice), amount);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), 0);

        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freeze(alice);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                bob,
                FORCED_TRANSFER_MANAGER_ROLE
            )
        );
        mYieldToOneForcedTransfer.forceTransfer(alice, bob, amount);
    }

    function testFuzz_forceTransfer(bool frozen, uint256 supply, uint256 aliceBalance, uint256 transferAmount) public {
        supply = bound(supply, 1, type(uint240).max);
        aliceBalance = bound(aliceBalance, 1, supply);
        transferAmount = bound(transferAmount, 1, aliceBalance);
        uint256 bobBalance = supply - aliceBalance;

        if (bobBalance == 0) return;

        mYieldToOneForcedTransfer.setBalanceOf(alice, aliceBalance);
        mYieldToOneForcedTransfer.setBalanceOf(bob, bobBalance);

        if (frozen) {
            vm.prank(freezeManager);
            mYieldToOneForcedTransfer.freeze(alice);

            vm.prank(forcedTransferManager);
            mYieldToOneForcedTransfer.forceTransfer(alice, bob, transferAmount);

            assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), aliceBalance - transferAmount);
            assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), bobBalance + transferAmount);
        } else {
            vm.prank(forcedTransferManager);
            vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, alice));
            mYieldToOneForcedTransfer.forceTransfer(alice, bob, transferAmount);

            assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), aliceBalance);
            assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), bobBalance);
        }
    }

    function test_forceTransfer_registeredRecipient_emitsPlaintextOnly() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOneForcedTransfer.registerPublicKey(_validPubKey(0xBB));

        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freeze(alice);

        assertEq(mYieldToOneForcedTransfer.getEncryptedEventNonce(), 0);

        vm.recordLogs();

        vm.prank(forcedTransferManager);
        mYieldToOneForcedTransfer.forceTransfer(alice, bob, amount);

        assertEq(mYieldToOneForcedTransfer.getEncryptedEventNonce(), 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Transfer(address,address,bytes32,bytes)");
        bytes32 plaintextTopic = keccak256("Transfer(address,address,uint256)");
        bytes32 forcedTopic = keccak256("ForcedTransfer(address,address,address,uint256)");

        bool foundBytes;
        bool foundPlaintext;
        bool foundForced;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(mYieldToOneForcedTransfer)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
            } else if (logs[i].topics[0] == plaintextTopic) {
                foundPlaintext = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), alice);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), bob);
                assertEq(abi.decode(logs[i].data, (uint256)), amount);
            } else if (logs[i].topics[0] == forcedTopic) {
                foundForced = true;
            }
        }

        assertTrue(foundPlaintext, "missing plaintext Transfer(uint256) emit on forceTransfer");
        assertTrue(foundForced, "missing ForcedTransfer emit");
        assertFalse(foundBytes, "forceTransfer leaked into encrypted-bytes Transfer overload");

        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), amount);
    }

    function test_forceTransfer_worksWhilePaused() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(alice, amount);

        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freeze(alice);

        vm.prank(pauser);
        mYieldToOneForcedTransfer.pause();

        vm.prank(forcedTransferManager);
        mYieldToOneForcedTransfer.forceTransfer(alice, bob, amount);

        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), amount);
    }

    /* ============ forceTransfers ============ */

    function test_forceTransfers_succeedsForManager() public {
        uint256 amount1 = 1_000e6;
        uint256 amount2 = 2_000e6;
        address[] memory frozenAccounts = new address[](2);
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        frozenAccounts[0] = alice;
        frozenAccounts[1] = bob;
        recipients[0] = carol;
        recipients[1] = david;
        amounts[0] = amount1;
        amounts[1] = amount2;

        mYieldToOneForcedTransfer.setBalanceOf(alice, amount1);
        mYieldToOneForcedTransfer.setBalanceOf(bob, amount2);

        address[] memory toFreeze = new address[](2);
        toFreeze[0] = alice;
        toFreeze[1] = bob;
        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freezeAccounts(toFreeze);

        vm.prank(forcedTransferManager);
        mYieldToOneForcedTransfer.forceTransfers(frozenAccounts, recipients, amounts);

        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(carol), amount1);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(david), amount2);
    }

    function test_forceTransfers_revertsWhenNotFrozen() public {
        uint256 amount1 = 1_000e6;
        uint256 amount2 = 2_000e6;
        address[] memory frozenAccounts = new address[](2);
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        frozenAccounts[0] = alice;
        frozenAccounts[1] = bob;
        recipients[0] = carol;
        recipients[1] = david;
        amounts[0] = amount1;
        amounts[1] = amount2;

        mYieldToOneForcedTransfer.setBalanceOf(alice, amount1);
        mYieldToOneForcedTransfer.setBalanceOf(bob, amount2);

        // Only freeze alice, bob is not frozen
        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freeze(alice);

        vm.prank(forcedTransferManager);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, bob));
        mYieldToOneForcedTransfer.forceTransfers(frozenAccounts, recipients, amounts);

        // alice and bob's balance should remain unchanged
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), amount1);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), amount2);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(carol), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(david), 0);
    }

    function test_forceTransfers_revertsForNonManager() public {
        uint256 amount1 = 1_000e6;
        uint256 amount2 = 2_000e6;
        address[] memory frozenAccounts = new address[](2);
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        frozenAccounts[0] = alice;
        frozenAccounts[1] = bob;
        recipients[0] = carol;
        recipients[1] = david;
        amounts[0] = amount1;
        amounts[1] = amount2;

        mYieldToOneForcedTransfer.setBalanceOf(alice, amount1);
        mYieldToOneForcedTransfer.setBalanceOf(bob, amount2);

        address[] memory toFreeze = new address[](2);
        toFreeze[0] = alice;
        toFreeze[1] = bob;
        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freezeAccounts(toFreeze);

        vm.prank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                carol,
                FORCED_TRANSFER_MANAGER_ROLE
            )
        );
        mYieldToOneForcedTransfer.forceTransfers(frozenAccounts, recipients, amounts);
    }

    function testFuzz_forceTransfers(bool frozen, uint256 supply, uint256 numOfAccounts) public {
        numOfAccounts = bound(numOfAccounts, 2, 50);
        supply = bound(supply, numOfAccounts, type(uint240).max);

        // Distribute supply among accounts
        address[] memory frozenAccounts = new address[](numOfAccounts);
        uint256[] memory initialBalances = new uint256[](numOfAccounts);
        address[] memory recipients = new address[](numOfAccounts);
        uint256[] memory amounts = new uint256[](numOfAccounts);

        uint256 remainingSupply = supply;
        for (uint256 i = 0; i < numOfAccounts; i++) {
            address from = address(uint160(i + 1));
            address to = address(uint160(i + 100));
            frozenAccounts[i] = from;
            recipients[i] = to;

            // Generate a pseudo-random balance for each account
            uint256 rand = uint256(keccak256(abi.encodePacked(supply, numOfAccounts, i)));
            uint256 maxBalance = remainingSupply - (numOfAccounts - i - 1);
            uint256 balance = bound(rand, 1, maxBalance);
            mYieldToOneForcedTransfer.setBalanceOf(from, balance);
            initialBalances[i] = balance;

            // Generate a pseudo-random transfer amount for each account
            uint256 randTransfer = uint256(keccak256(abi.encodePacked(balance, i, "transfer")));
            amounts[i] = bound(randTransfer, 1, balance);
            remainingSupply -= balance;
        }

        if (frozen) {
            vm.prank(freezeManager);
            mYieldToOneForcedTransfer.freezeAccounts(frozenAccounts);

            for (uint256 i = 0; i < numOfAccounts; i++) {
                vm.expectEmit(true, true, true, true);
                emit IERC20.Transfer(frozenAccounts[i], recipients[i], amounts[i]);
                emit IForcedTransferable.ForcedTransfer(
                    frozenAccounts[i],
                    recipients[i],
                    forcedTransferManager,
                    amounts[i]
                );
            }

            vm.prank(forcedTransferManager);
            mYieldToOneForcedTransfer.forceTransfers(frozenAccounts, recipients, amounts);

            for (uint256 i = 0; i < numOfAccounts; i++) {
                assertEq(mYieldToOneForcedTransfer.getBalanceOf(frozenAccounts[i]), initialBalances[i] - amounts[i]);
                assertEq(mYieldToOneForcedTransfer.getBalanceOf(recipients[i]), amounts[i]);
            }
        } else {
            vm.prank(forcedTransferManager);
            vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, frozenAccounts[0]));
            mYieldToOneForcedTransfer.forceTransfers(frozenAccounts, recipients, amounts);

            for (uint256 i = 0; i < numOfAccounts; i++) {
                assertEq(mYieldToOneForcedTransfer.getBalanceOf(frozenAccounts[i]), initialBalances[i]);
                assertEq(mYieldToOneForcedTransfer.getBalanceOf(recipients[i]), 0);
            }
        }
    }

    /* ============ transferFrom (native) ============ */

    function test_nativeTransferFrom_allowlistedCaller() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(alice, amount);

        vm.prank(admin);
        mYieldToOneForcedTransfer.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOneForcedTransfer.approve(carol, amount);

        assertEq(mYieldToOneForcedTransfer.getShieldedAllowance(alice, carol), amount);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount);

        vm.prank(carol);
        mYieldToOneForcedTransfer.transferFrom(alice, bob, amount);

        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), amount);
        assertEq(mYieldToOneForcedTransfer.getShieldedAllowance(alice, carol), 0);
    }

    function test_nativeTransferFrom_nonInfraCallerReverts() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(alice, amount);
        mYieldToOneForcedTransfer.setShieldedAllowance(alice, carol, amount);

        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);

        vm.prank(carol);
        mYieldToOneForcedTransfer.transferFrom(alice, bob, amount);
    }

    /* ============ transferWithAuthorization / receiveWithAuthorization (ERC-3009, inherited) ============ */

    function test_authorizationTransfersRevert() public {
        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);
        mYieldToOneForcedTransfer.transferWithAuthorization(alice, bob, 1_000e6, 0, type(uint256).max, bytes32(0), "");

        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);
        mYieldToOneForcedTransfer.receiveWithAuthorization(alice, bob, 1_000e6, 0, type(uint256).max, bytes32(0), "");
    }

    /* ============ balanceOf ============ */

    function test_balanceOf_allowlistedInfraCanReadAnyHolder() public {
        mYieldToOneForcedTransfer.setBalanceOf(alice, 1_000e6);

        vm.prank(admin);
        mYieldToOneForcedTransfer.setAllowlisted(carol, true);

        vm.prank(carol);
        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_holderCanRead() public {
        mYieldToOneForcedTransfer.setBalanceOf(alice, 1_000e6);

        vm.prank(alice);
        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_freezeManagerCanRead() public {
        mYieldToOneForcedTransfer.setBalanceOf(alice, 1_000e6);

        vm.prank(freezeManager);
        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_forcedTransferManagerCanRead() public {
        mYieldToOneForcedTransfer.setBalanceOf(alice, 1_000e6);

        vm.prank(forcedTransferManager);
        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_unauthorized() public {
        mYieldToOneForcedTransfer.setBalanceOf(alice, 1_000e6);

        vm.expectRevert(IMYieldToOne.Unauthorized.selector);
        vm.prank(bob);
        mYieldToOneForcedTransfer.balanceOf(alice);
    }

    function test_forceTransfer_seizureSizedByBalanceOf() public {
        mYieldToOneForcedTransfer.setBalanceOf(alice, 1_000e6);

        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freeze(alice);

        vm.prank(forcedTransferManager);
        uint256 seized = mYieldToOneForcedTransfer.balanceOf(alice);

        assertEq(seized, 1_000e6);

        vm.prank(forcedTransferManager);
        mYieldToOneForcedTransfer.forceTransfer(alice, bob, seized);

        vm.prank(forcedTransferManager);
        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), 0);

        vm.prank(forcedTransferManager);
        assertEq(mYieldToOneForcedTransfer.balanceOf(bob), seized);
    }

    /* ============ Helpers ============ */

    function _validPubKey(bytes1 marker) internal pure returns (bytes memory) {
        bytes memory key = new bytes(33);
        key[0] = 0x02;
        for (uint256 i = 1; i < 33; ++i) {
            key[i] = marker;
        }
        return key;
    }

    function _mockPrecompiles() internal {
        vm.mockCall(address(0x65), bytes(""), abi.encode(bytes32(uint256(1))));
        vm.mockCall(address(0x68), bytes(""), abi.encode(bytes32(uint256(2))));
        vm.mockCall(address(0x66), bytes(""), hex"deadbeefcafebabe");
    }

    function _installContractKey() internal {
        vm.prank(admin);
        mYieldToOneForcedTransfer.setContractKey(sbytes32(bytes32(uint256(0xC0FFEE))), _validPubKey(0xAA));
    }

    /* ============ transfer / transferFrom / approve (shielded) ============ */

    function test_transfer_shieldedOverload() external {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOneForcedTransfer.registerPublicKey(_validPubKey(0xBB));

        vm.expectEmit(true, true, true, true);
        emit IMYieldToOne.Transfer(alice, bob, keccak256(_validPubKey(0xBB)), hex"deadbeefcafebabe");

        vm.prank(alice);
        mYieldToOneForcedTransfer.transfer(bob, suint256(amount));

        assertEq(mYieldToOneForcedTransfer.getEncryptedEventNonce(), 1);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), amount);
    }

    function test_transferFrom_shieldedOverload() external {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOneForcedTransfer.registerPublicKey(_validPubKey(0xBB));

        vm.prank(alice);
        mYieldToOneForcedTransfer.approve(carol, suint256(amount));

        vm.expectEmit(true, true, true, true);
        emit IMYieldToOne.Transfer(alice, bob, keccak256(_validPubKey(0xBB)), hex"deadbeefcafebabe");

        vm.prank(carol);
        mYieldToOneForcedTransfer.transferFrom(alice, bob, suint256(amount));

        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(bob), amount);
        assertEq(mYieldToOneForcedTransfer.getShieldedAllowance(alice, carol), 0);
    }

    function test_approve_shieldedOverload() external {
        uint256 amount = 1_000e6;

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOneForcedTransfer.registerPublicKey(_validPubKey(0xBB));

        vm.expectEmit(true, true, true, true);
        emit IMYieldToOne.Approval(alice, bob, keccak256(_validPubKey(0xBB)), hex"deadbeefcafebabe");

        vm.prank(alice);
        mYieldToOneForcedTransfer.approve(bob, suint256(amount));

        assertEq(mYieldToOneForcedTransfer.getEncryptedEventNonce(), 1);
        assertEq(mYieldToOneForcedTransfer.getShieldedAllowance(alice, bob), amount);
    }

    /* ============ claimYield ============ */

    function test_claimYield_noYield() external {
        vm.prank(alice);
        uint256 yield = mYieldToOneForcedTransfer.claimYield();

        assertEq(yield, 0);
    }

    function test_claimYield() external {
        uint256 yield = 500e6;

        mToken.setBalanceOf(address(mYieldToOneForcedTransfer), mYieldToOneForcedTransfer.totalSupply() + yield);

        assertEq(mYieldToOneForcedTransfer.yield(), yield);

        vm.expectEmit();
        emit IMYieldToOne.YieldClaimed(yield);

        assertEq(mYieldToOneForcedTransfer.claimYield(), yield);

        assertEq(mYieldToOneForcedTransfer.yield(), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(yieldRecipient), yield);
    }

    function test_claimYield_paused() external {
        mToken.setBalanceOf(address(mYieldToOneForcedTransfer), mYieldToOneForcedTransfer.totalSupply() + 500e6);

        vm.prank(pauser);
        mYieldToOneForcedTransfer.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mYieldToOneForcedTransfer.claimYield();
    }

    /* ============ setYieldRecipient ============ */

    function test_setYieldRecipient_onlyYieldRecipientManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                YIELD_RECIPIENT_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        mYieldToOneForcedTransfer.setYieldRecipient(alice);
    }

    function test_setYieldRecipient_zeroYieldRecipient() public {
        vm.expectRevert(IMYieldToOne.ZeroYieldRecipient.selector);

        vm.prank(yieldRecipientManager);
        mYieldToOneForcedTransfer.setYieldRecipient(address(0));
    }

    function test_setYieldRecipient_noUpdate() public {
        assertEq(mYieldToOneForcedTransfer.yieldRecipient(), yieldRecipient);

        vm.prank(yieldRecipientManager);
        mYieldToOneForcedTransfer.setYieldRecipient(yieldRecipient);

        assertEq(mYieldToOneForcedTransfer.yieldRecipient(), yieldRecipient);
    }

    function test_setYieldRecipient() public {
        assertEq(mYieldToOneForcedTransfer.yieldRecipient(), yieldRecipient);

        vm.expectEmit();
        emit IMYieldToOne.YieldRecipientSet(alice);

        vm.prank(yieldRecipientManager);
        mYieldToOneForcedTransfer.setYieldRecipient(alice);

        assertEq(mYieldToOneForcedTransfer.yieldRecipient(), alice);
    }

    function test_setYieldRecipient_doesNotClaimYield() public {
        uint256 accruedYield = 500;

        // Accrue yield for the previous recipient.
        mToken.setBalanceOf(address(mYieldToOneForcedTransfer), mYieldToOneForcedTransfer.totalSupply() + accruedYield);

        assertEq(mYieldToOneForcedTransfer.yield(), accruedYield);

        vm.expectEmit();
        emit IMYieldToOne.YieldRecipientSet(alice);

        vm.prank(yieldRecipientManager);
        mYieldToOneForcedTransfer.setYieldRecipient(alice);

        // Recipient is updated.
        assertEq(mYieldToOneForcedTransfer.yieldRecipient(), alice);

        // Previously accrued yield is NOT claimed: it remains with the contract,
        // neither recipient receives a mint, and yield() still reflects the full amount.
        assertEq(mYieldToOneForcedTransfer.yield(), accruedYield);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(yieldRecipient), 0);
        assertEq(mYieldToOneForcedTransfer.getBalanceOf(alice), 0);
    }

    function test_setYieldRecipient_paused() public {
        vm.prank(pauser);
        mYieldToOneForcedTransfer.pause();

        vm.expectEmit();
        emit IMYieldToOne.YieldRecipientSet(alice);

        vm.prank(yieldRecipientManager);
        mYieldToOneForcedTransfer.setYieldRecipient(alice);

        // Recipient update is independent of pause state since claimYield is no longer invoked.
        assertEq(mYieldToOneForcedTransfer.yieldRecipient(), alice);
    }
}
