// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IERC20 } from "../../../../lib/common/src/interfaces/IERC20.sol";

import { IAccessControl } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { Upgrades, UnsafeUpgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MYieldToOneForcedTransfer } from "../../../../src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";
import { IMYieldToOne } from "../../../../src/projects/yieldToOne/interfaces/IMYieldToOne.sol";

import { IForcedTransferable } from "../../../../src/components/forcedTransferable/IForcedTransferable.sol";
import { IArrayErrors } from "../../../../src/interfaces/IArrayErrors.sol";
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
                    forcedTransferManager
                ),
                mExtensionDeployOptions
            )
        );

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
                    address(0)
                )
            )
        );
    }

    /* ============ forceTransfer ============ */

    function test_forceTransfer_succeedsForManager() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(address(alice), amount);
        assertEq(mYieldToOneForcedTransfer.balanceOf(bob), 0);

        vm.prank(freezeManager);
        mYieldToOneForcedTransfer.freeze(alice);

        vm.prank(forcedTransferManager);
        mYieldToOneForcedTransfer.forceTransfer(alice, bob, amount);

        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.balanceOf(bob), amount);
    }

    function test_forceTransfer_revertsWhenNotFrozen() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(address(alice), amount);
        assertEq(mYieldToOneForcedTransfer.balanceOf(bob), 0);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, alice));
        vm.prank(forcedTransferManager);
        mYieldToOneForcedTransfer.forceTransfer(alice, bob, amount);

        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), amount);
        assertEq(mYieldToOneForcedTransfer.balanceOf(bob), 0);
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
        vm.expectRevert(IArrayErrors.ArrayLengthMismatch.selector);
        mYieldToOneForcedTransfer.forceTransfers(frozenAccounts, recipients, amounts);
    }

    function test_forceTransfer_revertsForNonManager() public {
        uint256 amount = 1_000e6;
        mYieldToOneForcedTransfer.setBalanceOf(address(alice), amount);
        assertEq(mYieldToOneForcedTransfer.balanceOf(bob), 0);

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

            assertEq(mYieldToOneForcedTransfer.balanceOf(alice), aliceBalance - transferAmount);
            assertEq(mYieldToOneForcedTransfer.balanceOf(bob), bobBalance + transferAmount);
        } else {
            vm.prank(forcedTransferManager);
            vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, alice));
            mYieldToOneForcedTransfer.forceTransfer(alice, bob, transferAmount);

            assertEq(mYieldToOneForcedTransfer.balanceOf(alice), aliceBalance);
            assertEq(mYieldToOneForcedTransfer.balanceOf(bob), bobBalance);
        }
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

        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), 0);
        assertEq(mYieldToOneForcedTransfer.balanceOf(bob), 0);
        assertEq(mYieldToOneForcedTransfer.balanceOf(carol), amount1);
        assertEq(mYieldToOneForcedTransfer.balanceOf(david), amount2);
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
        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), amount1);
        assertEq(mYieldToOneForcedTransfer.balanceOf(bob), amount2);
        assertEq(mYieldToOneForcedTransfer.balanceOf(carol), 0);
        assertEq(mYieldToOneForcedTransfer.balanceOf(david), 0);
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
                assertEq(mYieldToOneForcedTransfer.balanceOf(frozenAccounts[i]), initialBalances[i] - amounts[i]);
                assertEq(mYieldToOneForcedTransfer.balanceOf(recipients[i]), amounts[i]);
            }
        } else {
            vm.prank(forcedTransferManager);
            vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, frozenAccounts[0]));
            mYieldToOneForcedTransfer.forceTransfers(frozenAccounts, recipients, amounts);

            for (uint256 i = 0; i < numOfAccounts; i++) {
                assertEq(mYieldToOneForcedTransfer.balanceOf(frozenAccounts[i]), initialBalances[i]);
                assertEq(mYieldToOneForcedTransfer.balanceOf(recipients[i]), 0);
            }
        }
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
        assertEq(mYieldToOneForcedTransfer.balanceOf(yieldRecipient), yield);
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
        assertEq(mYieldToOneForcedTransfer.balanceOf(yieldRecipient), 0);
        assertEq(mYieldToOneForcedTransfer.balanceOf(alice), 0);
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
