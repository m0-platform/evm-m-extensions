// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Vm } from "../../../../lib/forge-std/src/Vm.sol";

import { IERC20 } from "../../../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../../../lib/common/src/interfaces/IERC20Extended.sol";

import { IAccessControl } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { Upgrades, UnsafeUpgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MYieldToOne } from "../../../../src/projects/yieldToOne/MYieldToOne.sol";
import { IMYieldToOne } from "../../../../src/projects/yieldToOne/interfaces/IMYieldToOne.sol";
import { IMExtension } from "../../../../src/interfaces/IMExtension.sol";

import { IFreezable } from "../../../../src/components/freezable/IFreezable.sol";
import { IPausable } from "../../../../src/components/pausable/IPausable.sol";

import { ISwapFacility } from "../../../../src/swap/interfaces/ISwapFacility.sol";

import { MYieldToOneHarness } from "../../../harness/MYieldToOneHarness.sol";

import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract MYieldToOneUnitTests is BaseUnitTest {
    MYieldToOneHarness public mYieldToOne;

    string public constant NAME = "HALO USD";
    string public constant SYMBOL = "HALO USD";

    function setUp() public override {
        super.setUp();

        mYieldToOne = MYieldToOneHarness(
            Upgrades.deployTransparentProxy(
                "MYieldToOneHarness.sol:MYieldToOneHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldToOne.initialize.selector,
                    NAME,
                    SYMBOL,
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
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mYieldToOne.name(), NAME);
        assertEq(mYieldToOne.symbol(), SYMBOL);
        assertEq(mYieldToOne.decimals(), 6);
        assertEq(mYieldToOne.mToken(), address(mToken));
        assertEq(mYieldToOne.swapFacility(), address(swapFacility));
        assertEq(mYieldToOne.yieldRecipient(), yieldRecipient);

        assertTrue(mYieldToOne.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldToOne.hasRole(FREEZE_MANAGER_ROLE, freezeManager));
        assertTrue(mYieldToOne.hasRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager));
        assertTrue(mYieldToOne.hasRole(PAUSER_ROLE, pauser));
    }

    function test_initialize_zeroYieldRecipient() external {
        address implementation = address(new MYieldToOneHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMYieldToOne.ZeroYieldRecipient.selector);
        MYieldToOneHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldToOne.initialize.selector,
                    NAME,
                    SYMBOL,
                    address(0),
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroAdmin() external {
        address implementation = address(new MYieldToOneHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMYieldToOne.ZeroAdmin.selector);
        MYieldToOneHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldToOne.initialize.selector,
                    NAME,
                    SYMBOL,
                    address(yieldRecipient),
                    address(0),
                    freezeManager,
                    yieldRecipientManager,
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroYieldRecipientManager() external {
        address implementation = address(new MYieldToOneHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMYieldToOne.ZeroYieldRecipientManager.selector);
        MYieldToOneHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldToOne.initialize.selector,
                    NAME,
                    SYMBOL,
                    address(yieldRecipient),
                    admin,
                    freezeManager,
                    address(0),
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroPauser() external {
        address implementation = address(new MYieldToOneHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IPausable.ZeroPauser.selector);
        mYieldToOne = MYieldToOneHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldToOne.initialize.selector,
                    NAME,
                    SYMBOL,
                    yieldRecipient,
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    address(0)
                )
            )
        );
    }

    /* ============ setAllowlisted ============ */

    function test_setAllowlisted_onlyAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );

        vm.prank(alice);
        mYieldToOne.setAllowlisted(bob, true);
    }

    function test_setAllowlisted_zeroAllowlistAccount() public {
        vm.expectRevert(IMYieldToOne.ZeroAllowlistAccount.selector);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(address(0), true);
    }

    function test_setAllowlisted_noUpdate() public {
        vm.recordLogs();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, false);

        assertEq(vm.getRecordedLogs().length, 0);
        assertFalse(mYieldToOne.isAllowlisted(bob));
    }

    function test_setAllowlisted_noUpdateAfterSet() public {
        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, true);

        assertTrue(mYieldToOne.isAllowlisted(bob));

        vm.recordLogs();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, true);

        assertEq(vm.getRecordedLogs().length, 0);
        assertTrue(mYieldToOne.isAllowlisted(bob));
    }

    function test_setAllowlisted() public {
        assertFalse(mYieldToOne.isAllowlisted(bob));

        vm.expectEmit();
        emit IMYieldToOne.AllowlistSet(bob, true);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, true);

        assertTrue(mYieldToOne.isAllowlisted(bob));

        vm.expectEmit();
        emit IMYieldToOne.AllowlistSet(bob, false);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, false);

        assertFalse(mYieldToOne.isAllowlisted(bob));
    }

    /* ============ setAllowlisted (batch) ============ */

    function test_setAllowlisted_batchOnlyAdmin() public {
        address[] memory infra = new address[](2);
        infra[0] = bob;
        infra[1] = carol;

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );

        vm.prank(alice);
        mYieldToOne.setAllowlisted(infra, true);
    }

    function test_setAllowlisted_batchZeroAllowlistAccount() public {
        address[] memory infra = new address[](2);
        infra[0] = bob;
        infra[1] = address(0);

        vm.expectRevert(IMYieldToOne.ZeroAllowlistAccount.selector);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(infra, true);
    }

    function test_setAllowlisted_batch() public {
        address[] memory infra = new address[](3);
        infra[0] = bob;
        infra[1] = carol;
        infra[2] = david;

        vm.expectEmit();
        emit IMYieldToOne.AllowlistSet(bob, true);
        vm.expectEmit();
        emit IMYieldToOne.AllowlistSet(carol, true);
        vm.expectEmit();
        emit IMYieldToOne.AllowlistSet(david, true);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(infra, true);

        assertTrue(mYieldToOne.isAllowlisted(bob));
        assertTrue(mYieldToOne.isAllowlisted(carol));
        assertTrue(mYieldToOne.isAllowlisted(david));

        vm.prank(admin);
        mYieldToOne.setAllowlisted(infra, false);

        assertFalse(mYieldToOne.isAllowlisted(bob));
        assertFalse(mYieldToOne.isAllowlisted(carol));
        assertFalse(mYieldToOne.isAllowlisted(david));
    }

    /* ============ isAllowlisted ============ */

    function test_isAllowlisted_swapFacilityNotAllowlisted() public view {
        assertFalse(mYieldToOne.isAllowlisted(address(swapFacility)));
    }

    /* ============ approve (shielded) ============ */

    function test_approve_frozenAccount() public {
        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(1_000e6));
    }

    function test_approve_frozenSpender() public {
        vm.prank(freezeManager);
        mYieldToOne.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(1_000e6));
    }

    function test_approve_writesShieldedStorage() public {
        uint256 amount = 1_000e6;

        _installContractKey();

        // bob has no registered key => empty-ciphertext fallback emit on the bytes overload.
        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Approval(alice, bob, bytes(""));

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(amount));

        assertEq(mYieldToOne.getShieldedAllowance(alice, bob), amount);
    }

    function test_approve_inheritedPathReverts() public {
        vm.expectRevert(IMYieldToOne.UseShieldedApprove.selector);

        vm.prank(alice);
        mYieldToOne.approve(bob, 1_000e6);
    }

    function test_approve_permitReverts() public {
        vm.expectRevert(IMYieldToOne.UseShieldedApprove.selector);
        mYieldToOne.permit(alice, bob, 1_000e6, type(uint256).max, 0, bytes32(0), bytes32(0));

        vm.expectRevert(IMYieldToOne.UseShieldedApprove.selector);
        mYieldToOne.permit(alice, bob, 1_000e6, type(uint256).max, "");
    }

    /* ============ approve (native) ============ */

    function test_nativeApprove_nonInfraSpenderReverts() public {
        vm.expectRevert(IMYieldToOne.UseShieldedApprove.selector);

        vm.prank(alice);
        mYieldToOne.approve(bob, 1_000e6);
    }

    function test_nativeApprove_allowlistedSpender() public {
        uint256 amount = 1_000e6;

        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, true);

        vm.expectEmit();
        emit IERC20.Approval(alice, bob, amount);

        vm.prank(alice);
        mYieldToOne.approve(bob, amount);

        assertEq(mYieldToOne.getShieldedAllowance(alice, bob), amount);
    }

    function test_nativeApprove_swapFacilitySpender() public {
        uint256 amount = 1_000e6;

        vm.expectEmit();
        emit IERC20.Approval(alice, address(swapFacility), amount);

        vm.prank(alice);
        mYieldToOne.approve(address(swapFacility), amount);

        assertEq(mYieldToOne.getShieldedAllowance(alice, address(swapFacility)), amount);
    }

    function test_nativeApprove_frozenAccount() public {
        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, true);

        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        mYieldToOne.approve(bob, 1_000e6);
    }

    function test_nativeApprove_frozenSpender() public {
        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, true);

        vm.prank(freezeManager);
        mYieldToOne.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        mYieldToOne.approve(bob, 1_000e6);
    }

    function test_nativeApprove_delistedSpenderReverts() public {
        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, true);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, false);

        vm.expectRevert(IMYieldToOne.UseShieldedApprove.selector);

        vm.prank(alice);
        mYieldToOne.approve(bob, 1_000e6);
    }

    /* ============ transferFrom (native) ============ */

    function test_nativeTransferFrom_nonInfraCallerReverts() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);
        mYieldToOne.setShieldedAllowance(alice, carol, amount);

        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);
    }

    function test_nativeTransferFrom_allowlistedCaller() public {
        uint256 amount = 1_000e6;
        uint256 allowanceAmount = 1_500e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(allowanceAmount));

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount);

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), allowanceAmount - amount);
    }

    function test_nativeTransferFrom_swapFacilityCaller() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(alice);
        mYieldToOne.approve(address(swapFacility), suint256(amount));

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount);

        vm.prank(address(swapFacility));
        mYieldToOne.transferFrom(alice, bob, amount);

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
        assertEq(mYieldToOne.getShieldedAllowance(alice, address(swapFacility)), 0);
    }

    function test_nativeTransferFrom_infiniteAllowanceNoDecrement() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(type(uint256).max));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);

        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), type(uint256).max);
    }

    function test_nativeTransferFrom_insufficientAllowance() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount - 1));

        // Allowance is reported as 0 in the revert to avoid leaking the shielded value.
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAllowance.selector, carol, 0, amount));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);
    }

    function test_nativeTransferFrom_paused() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount));

        vm.prank(pauser);
        mYieldToOne.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);
    }

    function test_nativeTransferFrom_frozenAccount() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount));

        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);
    }

    function test_nativeTransferFrom_frozenRecipient() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);
        mYieldToOne.setShieldedAllowance(alice, carol, amount);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(freezeManager);
        mYieldToOne.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);
    }

    function test_nativeTransferFrom_frozenCaller() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);
        mYieldToOne.setShieldedAllowance(alice, carol, amount);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(freezeManager);
        mYieldToOne.freeze(carol);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, carol));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);
    }

    function test_nativeTransferFrom_delistedCallerReverts() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);
        mYieldToOne.setShieldedAllowance(alice, carol, amount);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, false);

        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);
    }

    function test_nativeTransferFrom_shieldedApproveSpentByNativePath() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, amount);

        assertEq(mYieldToOne.getBalanceOf(bob), amount);
        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), 0);
    }

    function test_nativeApprove_spentByShieldedTransferFrom() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOne.approve(carol, amount);

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));

        assertEq(mYieldToOne.getBalanceOf(bob), amount);
        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), 0);
    }

    function testFuzz_nativeTransferFrom(uint256 supply, uint256 aliceBalance, uint256 transferAmount) external {
        supply = bound(supply, 1, type(uint240).max);
        aliceBalance = bound(aliceBalance, 1, supply);
        transferAmount = bound(transferAmount, 1, aliceBalance);
        uint256 bobBalance = supply - aliceBalance;

        if (bobBalance == 0) return;

        mYieldToOne.setBalanceOf(alice, aliceBalance);
        mYieldToOne.setBalanceOf(bob, bobBalance);
        mYieldToOne.setShieldedAllowance(alice, carol, transferAmount);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, transferAmount);

        assertEq(mYieldToOne.getBalanceOf(alice), aliceBalance - transferAmount);
        assertEq(mYieldToOne.getBalanceOf(bob), bobBalance + transferAmount);
        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), 0);
    }

    /* ============ balanceOf ============ */

    function test_balanceOf_holderCanRead() public {
        mYieldToOne.setBalanceOf(alice, 1_000e6);

        vm.prank(alice);
        assertEq(mYieldToOne.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_unauthorized() public {
        mYieldToOne.setBalanceOf(alice, 1_000e6);

        vm.expectRevert(IMYieldToOne.Unauthorized.selector);
        vm.prank(bob);
        mYieldToOne.balanceOf(alice);
    }

    function test_balanceOf_swapFacilityCanRead() public {
        mYieldToOne.setBalanceOf(alice, 1_000e6);

        vm.prank(address(swapFacility));
        assertEq(mYieldToOne.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_allowlistedInfraCanReadAnyHolder() public {
        mYieldToOne.setBalanceOf(alice, 1_000e6);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(carol);
        assertEq(mYieldToOne.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_freezeManagerCanRead() public {
        mYieldToOne.setBalanceOf(alice, 1_000e6);

        vm.prank(freezeManager);
        assertEq(mYieldToOne.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_removingFromAllowlistReblocks() public {
        mYieldToOne.setBalanceOf(alice, 1_000e6);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(carol);
        assertEq(mYieldToOne.balanceOf(alice), 1_000e6);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, false);

        vm.expectRevert(IMYieldToOne.Unauthorized.selector);
        vm.prank(carol);
        mYieldToOne.balanceOf(alice);
    }

    /* ============ allowance ============ */

    function test_allowance_unauthorized() public {
        _installContractKey();

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(500e6));

        vm.expectRevert(IMYieldToOne.Unauthorized.selector);
        vm.prank(carol);
        mYieldToOne.allowance(alice, bob);
    }

    function test_allowance_ownerCanRead() public {
        _installContractKey();

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(500e6));

        vm.prank(alice);
        assertEq(mYieldToOne.allowance(alice, bob), 500e6);
    }

    function test_allowance_spenderCanRead() public {
        _installContractKey();

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(500e6));

        vm.prank(bob);
        assertEq(mYieldToOne.allowance(alice, bob), 500e6);
    }

    /* ============ _wrap ============ */

    function test_wrap_frozenAccount() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(address(swapFacility));
        mYieldToOne.wrap(bob, amount);
    }

    function test_wrap_frozenRecipient() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        vm.prank(freezeManager);
        mYieldToOne.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(address(swapFacility));
        mYieldToOne.wrap(bob, amount);
    }

    function test_wrap_paused() public {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(address(swapFacility), amount);

        vm.prank(pauser);
        mYieldToOne.pause();

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(swapFacility.msgSender.selector), abi.encode(bob));

        vm.prank(address(swapFacility));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mYieldToOne.wrap(bob, 1);
    }

    function test_wrap() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(address(swapFacility), amount);

        vm.expectCall(
            address(mToken),
            abi.encodeWithSelector(mToken.transferFrom.selector, address(swapFacility), address(mYieldToOne), amount)
        );

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, amount);

        vm.prank(address(swapFacility));
        mYieldToOne.wrap(alice, amount);

        assertEq(mYieldToOne.getBalanceOf(alice), amount);
        assertEq(mYieldToOne.totalSupply(), amount);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(address(mYieldToOne)), amount);
    }

    /* ============ _unwrap ============ */
    function test_unwrap_frozenAccount() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(address(swapFacility));
        mYieldToOne.unwrap(alice, amount);
    }

    function test_unwrap_paused() public {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(address(swapFacility), amount);

        vm.prank(pauser);
        mYieldToOne.pause();

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(swapFacility.msgSender.selector), abi.encode(alice));

        vm.prank(address(swapFacility));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mYieldToOne.unwrap(alice, 1);
    }

    function test_unwrap_insufficientBalance() external {
        uint256 amount = 1_000e6;

        mYieldToOne.setBalanceOf(address(swapFacility), amount - 1);
        mYieldToOne.setTotalSupply(amount - 1);

        // Balance is reported as 0 in the revert to avoid leaking the shielded value.
        vm.expectRevert(
            abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, address(swapFacility), 0, amount)
        );

        vm.prank(address(swapFacility));
        mYieldToOne.unwrap(alice, amount);
    }

    function test_unwrap() external {
        uint256 amount = 1_000e6;

        mYieldToOne.setBalanceOf(address(swapFacility), amount);
        mYieldToOne.setTotalSupply(amount);

        mToken.setBalanceOf(address(mYieldToOne), amount);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 1e6);

        vm.prank(address(swapFacility));
        mYieldToOne.unwrap(alice, 1e6);

        assertEq(mYieldToOne.totalSupply(), 999e6);
        assertEq(mYieldToOne.getBalanceOf(address(swapFacility)), 999e6);
        assertEq(mToken.balanceOf(address(swapFacility)), 1e6);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 499e6);

        vm.prank(address(swapFacility));
        mYieldToOne.unwrap(alice, 499e6);

        assertEq(mYieldToOne.totalSupply(), 500e6);
        assertEq(mYieldToOne.getBalanceOf(address(swapFacility)), 500e6);
        assertEq(mToken.balanceOf(address(swapFacility)), 500e6);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 500e6);

        vm.prank(address(swapFacility));
        mYieldToOne.unwrap(alice, 500e6);

        assertEq(mYieldToOne.totalSupply(), 0);
        assertEq(mYieldToOne.getBalanceOf(address(swapFacility)), 0);

        // M tokens are sent to SwapFacility and then forwarded to Alice
        assertEq(mToken.balanceOf(address(swapFacility)), amount);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 0);
    }

    /* ============ transfer (shielded) ============ */
    function test_transfer_frozenSpender() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        // Alice allows Carol to transfer tokens on her behalf (shielded approve).
        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount));

        vm.prank(freezeManager);
        mYieldToOne.freeze(carol);

        // Reverts because Carol (the spender / msg.sender) is frozen.
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, carol));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));
    }

    function test_transfer_frozenAccount() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_transfer_frozenRecipient() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        vm.prank(freezeManager);
        mYieldToOne.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_transfer_paused() public {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        vm.prank(pauser);
        mYieldToOne.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(1));
    }

    function test_transfer() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Transfer(alice, bob, bytes(""));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
    }

    function test_transfer_insufficientBalance() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount - 1);

        _installContractKey();

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 0, amount));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_transfer_selfTransfer() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Transfer(alice, alice, bytes(""));

        vm.prank(alice);
        mYieldToOne.transfer(alice, suint256(amount));

        assertEq(mYieldToOne.getBalanceOf(alice), amount);
    }

    function test_transfer_invalidRecipient() external {
        mYieldToOne.setBalanceOf(alice, 1_000e6);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(alice);
        mYieldToOne.transfer(address(0), suint256(1_000e6));
    }

    function test_transfer_inheritedPathReverts() external {
        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);

        vm.prank(alice);
        mYieldToOne.transfer(bob, 1_000e6);
    }

    function testFuzz_transfer(uint256 supply, uint256 aliceBalance, uint256 transferAmount) external {
        supply = bound(supply, 1, type(uint240).max);
        aliceBalance = bound(aliceBalance, 1, supply);
        transferAmount = bound(transferAmount, 1, aliceBalance);
        uint256 bobBalance = supply - aliceBalance;

        if (bobBalance == 0) return;

        mYieldToOne.setBalanceOf(alice, aliceBalance);
        mYieldToOne.setBalanceOf(bob, bobBalance);

        _installContractKey();

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(transferAmount));

        assertEq(mYieldToOne.getBalanceOf(alice), aliceBalance - transferAmount);
        assertEq(mYieldToOne.getBalanceOf(bob), bobBalance + transferAmount);
    }

    /* ============ transferFrom (shielded) ============ */

    function test_transferFrom_finiteAllowanceDecrements() external {
        uint256 amount = 1_000e6;
        uint256 allowanceAmount = 1_500e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(allowanceAmount));

        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Transfer(alice, bob, bytes(""));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), allowanceAmount - amount);
    }

    function test_transferFrom_infiniteAllowanceNoDecrement() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(type(uint256).max));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));

        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), type(uint256).max);
    }

    function test_transferFrom_insufficientAllowance() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount - 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAllowance.selector, carol, 0, amount));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));
    }

    function test_transferFrom_noAllowance() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAllowance.selector, carol, 0, amount));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));
    }

    function test_transferFrom_insufficientBalance() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount - 1);
        mYieldToOne.setShieldedAllowance(alice, carol, amount);

        _installContractKey();

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 0, amount));

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));
    }

    function test_shieldedTransferFrom_spenderDelistedAfterApprove_stillSpends() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, true);

        vm.prank(alice);
        mYieldToOne.approve(carol, amount);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(carol, false);

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), 0);
    }

    function testFuzz_transferFrom(
        uint256 supply,
        uint256 aliceBalance,
        uint256 transferAmount,
        bool infiniteAllowance
    ) external {
        supply = bound(supply, 1, type(uint240).max);
        aliceBalance = bound(aliceBalance, 1, supply);
        transferAmount = bound(transferAmount, 1, aliceBalance);
        uint256 bobBalance = supply - aliceBalance;

        if (bobBalance == 0) return;

        mYieldToOne.setBalanceOf(alice, aliceBalance);
        mYieldToOne.setBalanceOf(bob, bobBalance);
        mYieldToOne.setShieldedAllowance(alice, carol, infiniteAllowance ? type(uint256).max : transferAmount);

        _installContractKey();

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(transferAmount));

        assertEq(mYieldToOne.getBalanceOf(alice), aliceBalance - transferAmount);
        assertEq(mYieldToOne.getBalanceOf(bob), bobBalance + transferAmount);
        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), infiniteAllowance ? type(uint256).max : 0);
    }

    function test_transferFrom_inheritedPathReverts() external {
        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, 1_000e6);
    }

    /* ============ yield ============ */
    function test_yield() external {
        assertEq(mYieldToOne.yield(), 0);

        mToken.setBalanceOf(address(mYieldToOne), 1_500e6);
        mYieldToOne.setTotalSupply(1_000e6);

        assertEq(mYieldToOne.yield(), 500e6);
    }

    function testFuzz_yield(uint256 mBalance, uint256 totalSupply) external {
        mBalance = bound(mBalance, 0, type(uint240).max);
        totalSupply = bound(totalSupply, 0, mBalance);

        mToken.setBalanceOf(address(mYieldToOne), mBalance);
        mYieldToOne.setTotalSupply(totalSupply);

        assertEq(mYieldToOne.yield(), mBalance - totalSupply);
    }

    /* ============ claimYield ============ */
    function test_claimYield_noYield() external {
        vm.prank(alice);
        uint256 yield = mYieldToOne.claimYield();

        assertEq(yield, 0);
    }

    function test_claimYield() external {
        uint256 yield = 500e6;

        mToken.setBalanceOf(address(mYieldToOne), 1_500e6);
        mYieldToOne.setTotalSupply(1_000e6);

        assertEq(mYieldToOne.yield(), yield);

        vm.expectEmit();
        emit IMYieldToOne.YieldClaimed(yield);

        assertEq(mYieldToOne.claimYield(), yield);

        assertEq(mYieldToOne.yield(), 0);

        assertEq(mToken.balanceOf(address(mYieldToOne)), 1_500e6);
        assertEq(mYieldToOne.totalSupply(), 1_500e6);

        assertEq(mToken.balanceOf(yieldRecipient), 0);
        assertEq(mYieldToOne.getBalanceOf(yieldRecipient), yield);
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
        mYieldToOne.setYieldRecipient(alice);
    }

    function test_setYieldRecipient_zeroYieldRecipient() public {
        vm.expectRevert(IMYieldToOne.ZeroYieldRecipient.selector);

        vm.prank(yieldRecipientManager);
        mYieldToOne.setYieldRecipient(address(0));
    }

    function test_setYieldRecipient_noUpdate() public {
        assertEq(mYieldToOne.yieldRecipient(), yieldRecipient);

        vm.prank(yieldRecipientManager);
        mYieldToOne.setYieldRecipient(yieldRecipient);

        assertEq(mYieldToOne.yieldRecipient(), yieldRecipient);
    }

    function test_setYieldRecipient() public {
        assertEq(mYieldToOne.yieldRecipient(), yieldRecipient);

        vm.expectEmit();
        emit IMYieldToOne.YieldRecipientSet(alice);

        vm.prank(yieldRecipientManager);
        mYieldToOne.setYieldRecipient(alice);

        assertEq(mYieldToOne.yieldRecipient(), alice);
    }

    function test_setYieldRecipient_claimYield() public {
        assertEq(mYieldToOne.yieldRecipient(), yieldRecipient);

        mToken.setBalanceOf(address(mYieldToOne), mYieldToOne.totalSupply() + 500);

        vm.expectEmit();
        emit IMYieldToOne.YieldClaimed(500);

        vm.prank(yieldRecipientManager);
        mYieldToOne.setYieldRecipient(alice);

        assertEq(mYieldToOne.yieldRecipient(), alice);
        assertEq(mYieldToOne.yield(), 0);
        assertEq(mYieldToOne.getBalanceOf(yieldRecipient), 500);
    }

    /* ============ Helpers ============ */

    /// @dev Returns a 33-byte compressed-secp256k1-shaped public key; contents are arbitrary.
    function _validPubKey(bytes1 marker) internal pure returns (bytes memory) {
        bytes memory key = new bytes(33);
        key[0] = 0x02; // compressed-secp256k1 even-Y prefix
        for (uint256 i = 1; i < 33; ++i) {
            key[i] = marker;
        }
        return key;
    }

    /// @dev Mocks the Seismic precompiles (0x65 ECDH, 0x68 HKDF, 0x66 AES-GCM) with distinct outputs.
    function _mockPrecompiles() internal {
        vm.mockCall(address(0x65), bytes(""), abi.encode(bytes32(uint256(1))));
        vm.mockCall(address(0x68), bytes(""), abi.encode(bytes32(uint256(2))));
        vm.mockCall(address(0x66), bytes(""), hex"deadbeefcafebabe");
    }

    /// @dev Installs the contract keypair through the admin path.
    function _installContractKey() internal {
        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(0xC0FFEE))), _validPubKey(0xAA));
    }

    /* ============ setContractKey ============ */

    function test_setContractKey_onlyAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );

        vm.prank(alice);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(1))), _validPubKey(0xAA));
    }

    function test_setContractKey_oneShot() public {
        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(0xC0FFEE))), _validPubKey(0xAA));

        vm.expectRevert(IMYieldToOne.ContractKeyAlreadySet.selector);

        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(0xBEEF))), _validPubKey(0xBB));
    }

    function test_setContractKey_invalidLength_short() public {
        bytes memory tooShort = new bytes(32);

        vm.expectRevert(IMYieldToOne.InvalidPublicKeyLength.selector);

        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(1))), tooShort);
    }

    function test_setContractKey_invalidLength_long() public {
        bytes memory tooLong = new bytes(34);

        vm.expectRevert(IMYieldToOne.InvalidPublicKeyLength.selector);

        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(1))), tooLong);
    }

    function test_setContractKey_zeroPrivateKey() public {
        vm.expectRevert(IMYieldToOne.ZeroPrivateKey.selector);

        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(0)), _validPubKey(0xAA));
    }

    function test_setContractKey_invalidPrefix() public {
        bytes memory pubKey = _validPubKey(0xAA);
        pubKey[0] = 0x04;

        vm.expectRevert(IMYieldToOne.InvalidPublicKeyPrefix.selector);

        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(1))), pubKey);
    }

    function test_setContractKey_emitsContractKeySet() public {
        bytes memory pubKey = _validPubKey(0xAA);

        assertEq(mYieldToOne.contractPublicKey(), bytes(""));

        vm.expectEmit();
        emit IMYieldToOne.ContractKeySet(pubKey);

        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(0xC0FFEE))), pubKey);

        assertEq(mYieldToOne.contractPublicKey(), pubKey);
    }

    /* ============ registerPublicKey ============ */

    function test_registerPublicKey_writesStorage() public {
        bytes memory pubKey = _validPubKey(0xBB);

        assertEq(mYieldToOne.publicKeyOf(alice), bytes(""));

        vm.prank(alice);
        mYieldToOne.registerPublicKey(pubKey);

        assertEq(mYieldToOne.publicKeyOf(alice), pubKey);
    }

    function test_registerPublicKey_idempotentOverwrite() public {
        bytes memory firstKey = _validPubKey(0xBB);
        bytes memory secondKey = _validPubKey(0xCC);

        vm.prank(alice);
        mYieldToOne.registerPublicKey(firstKey);

        assertEq(mYieldToOne.publicKeyOf(alice), firstKey);

        vm.prank(alice);
        mYieldToOne.registerPublicKey(secondKey);

        assertEq(mYieldToOne.publicKeyOf(alice), secondKey);
    }

    function test_registerPublicKey_invalidLength_short() public {
        bytes memory tooShort = new bytes(32);

        vm.expectRevert(IMYieldToOne.InvalidPublicKeyLength.selector);

        vm.prank(alice);
        mYieldToOne.registerPublicKey(tooShort);
    }

    function test_registerPublicKey_invalidLength_long() public {
        bytes memory tooLong = new bytes(34);

        vm.expectRevert(IMYieldToOne.InvalidPublicKeyLength.selector);

        vm.prank(alice);
        mYieldToOne.registerPublicKey(tooLong);
    }

    function test_registerPublicKey_invalidPrefix() public {
        bytes memory pubKey = _validPubKey(0xBB);
        pubKey[0] = 0x04;

        vm.expectRevert(IMYieldToOne.InvalidPublicKeyPrefix.selector);

        vm.prank(alice);
        mYieldToOne.registerPublicKey(pubKey);
    }

    function test_registerPublicKey_emitsPublicKeyRegistered() public {
        vm.expectEmit();
        emit IMYieldToOne.PublicKeyRegistered(alice);

        vm.prank(alice);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));
    }

    /* ============ _encryptAmount ============ */

    function test_shieldedTransfer_registeredRecipient_emitsBytesPayload() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        bytes memory recipientKey = _validPubKey(0xBB);
        vm.prank(bob);
        mYieldToOne.registerPublicKey(recipientKey);

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);

        vm.recordLogs();

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 1);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Transfer(address,address,bytes)");
        bytes32 plaintextTopic = keccak256("Transfer(address,address,uint256)");

        bool foundBytes;
        bool foundPlaintext;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(mYieldToOne)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), alice);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), bob);
                bytes memory payload = abi.decode(logs[i].data, (bytes));
                assertGt(payload.length, 0);
            } else if (logs[i].topics[0] == plaintextTopic) {
                foundPlaintext = true;
            }
        }

        assertTrue(foundBytes, "missing Transfer(address,address,bytes) emit");
        assertFalse(foundPlaintext, "plaintext Transfer(uint256) emitted on shielded path");

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
    }

    function test_shieldedTransferFrom_registeredRecipient_emitsBytesPayload() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);

        vm.recordLogs();

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 1);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Transfer(address,address,bytes)");
        bytes32 plaintextTopic = keccak256("Transfer(address,address,uint256)");

        bool foundBytes;
        bool foundPlaintext;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(mYieldToOne)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), alice);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), bob);
                bytes memory payload = abi.decode(logs[i].data, (bytes));
                assertGt(payload.length, 0);
            } else if (logs[i].topics[0] == plaintextTopic) {
                foundPlaintext = true;
            }
        }

        assertTrue(foundBytes, "missing Transfer(address,address,bytes) emit");
        assertFalse(foundPlaintext, "plaintext Transfer(uint256) emitted on shielded path");
    }

    function test_shieldedTransfer_ciphertextMatchesPrecompileOutput() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Transfer(alice, bob, hex"deadbeefcafebabe");

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_shieldedTransfer_forwardsContractAndRecipientKeysToEcdh() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        bytes memory recipientKey = _validPubKey(0xBB);

        vm.prank(bob);
        mYieldToOne.registerPublicKey(recipientKey);

        vm.expectCall(address(0x65), abi.encodePacked(bytes32(uint256(0xC0FFEE)), recipientKey));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_shieldedTransfer_reregisteredKeyForwardedToEcdh() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        bytes memory firstKey = _validPubKey(0xBB);
        bytes memory secondKey = _validPubKey(0xCC);

        vm.prank(bob);
        mYieldToOne.registerPublicKey(firstKey);

        vm.prank(bob);
        mYieldToOne.registerPublicKey(secondKey);

        vm.expectCall(address(0x65), abi.encodePacked(bytes32(uint256(0xC0FFEE)), firstKey), 0);
        vm.expectCall(address(0x65), abi.encodePacked(bytes32(uint256(0xC0FFEE)), secondKey), 1);

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_shieldedTransfer_zeroAmount_registeredRecipient() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Transfer(alice, bob, hex"deadbeefcafebabe");

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(0));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 1);
        assertEq(mYieldToOne.getBalanceOf(alice), amount);
        assertEq(mYieldToOne.getBalanceOf(bob), 0);
    }

    function test_shieldedTransfer_unregisteredRecipient_emitsEmptyBytesAndSucceeds() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        // Key IS set: the ContractKeyNotSet check fires before the unregistered-recipient fallback.
        _installContractKey();

        // Precompiles are intentionally not mocked: the fallback path must not call them.
        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Transfer(alice, bob, bytes(""));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
    }

    function test_shieldedTransfer_zeroAmount_unregisteredRecipient() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Transfer(alice, bob, bytes(""));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(0));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);
        assertEq(mYieldToOne.getBalanceOf(alice), amount);
        assertEq(mYieldToOne.getBalanceOf(bob), 0);
    }

    function test_shieldedTransfer_contractKeyNotSet_reverts() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.expectRevert(IMYieldToOne.ContractKeyNotSet.selector);

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_shieldedTransfer_contractKeyNotSet_unregisteredRecipient_reverts() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        // Reverts even for an unregistered recipient so success cannot leak who is registered.
        vm.expectRevert(IMYieldToOne.ContractKeyNotSet.selector);

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));

        assertEq(mYieldToOne.getBalanceOf(alice), amount);
        assertEq(mYieldToOne.getBalanceOf(bob), 0);
        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);
    }

    /* ============ _ecdh / _hkdf / _aesGcmEncrypt ============ */

    function test_shieldedTransfer_ecdhPrecompileFails() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.mockCallRevert(address(0x65), bytes(""), bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IMYieldToOne.PrecompileFailed.selector, address(0x65)));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_shieldedTransfer_hkdfPrecompileFails() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.mockCall(address(0x65), bytes(""), abi.encode(bytes32(uint256(1))));
        vm.mockCallRevert(address(0x68), bytes(""), bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IMYieldToOne.PrecompileFailed.selector, address(0x68)));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_shieldedTransfer_aesGcmPrecompileFails() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.mockCall(address(0x65), bytes(""), abi.encode(bytes32(uint256(1))));
        vm.mockCall(address(0x68), bytes(""), abi.encode(bytes32(uint256(2))));
        vm.mockCallRevert(address(0x66), bytes(""), bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IMYieldToOne.PrecompileFailed.selector, address(0x66)));

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount));
    }

    function test_shieldedApprove_ecdhPrecompileFails() external {
        _installContractKey();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.mockCallRevert(address(0x65), bytes(""), bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IMYieldToOne.PrecompileFailed.selector, address(0x65)));

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(1_000e6));
    }

    /* ============ encryptedEventNonce ============ */

    function test_encryptedEventNonce_sharedAcrossTransferAndApprove() external {
        mYieldToOne.setBalanceOf(alice, 3_000e6);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(1_000e6));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 1);

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(500e6));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 2);

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(1_000e6));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 3);
    }

    /* ============ _shieldedApprove ============ */

    function test_shieldedApprove_registeredSpender_emitsBytesPayload() external {
        uint256 amount = 1_000e6;

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);

        vm.recordLogs();

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(amount));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 1);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Approval(address,address,bytes)");
        bytes32 plaintextTopic = keccak256("Approval(address,address,uint256)");

        bool foundBytes;
        bool foundPlaintext;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(mYieldToOne)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), alice);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), bob);
                bytes memory payload = abi.decode(logs[i].data, (bytes));
                assertGt(payload.length, 0);
            } else if (logs[i].topics[0] == plaintextTopic) {
                foundPlaintext = true;
            }
        }

        assertTrue(foundBytes, "missing Approval(address,address,bytes) emit");
        assertFalse(foundPlaintext, "plaintext Approval(uint256) emitted on shielded path");

        assertEq(mYieldToOne.getShieldedAllowance(alice, bob), amount);
    }

    function test_shieldedApprove_unregisteredSpender_emitsEmptyBytes() external {
        uint256 amount = 1_000e6;

        _installContractKey();

        vm.expectEmit(true, true, false, true);
        emit IMYieldToOne.Approval(alice, bob, bytes(""));

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(amount));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);
        assertEq(mYieldToOne.getShieldedAllowance(alice, bob), amount);
    }

    function test_shieldedApprove_contractKeyNotSet_reverts() external {
        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.expectRevert(IMYieldToOne.ContractKeyNotSet.selector);
        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(1_000e6));

        vm.expectRevert(IMYieldToOne.ContractKeyNotSet.selector);
        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(1_000e6));
    }

    function test_nativeApprove_emitsPlaintext() external {
        uint256 amount = 1_000e6;

        _installContractKey();
        _mockPrecompiles();

        vm.prank(admin);
        mYieldToOne.setAllowlisted(bob, true);

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.recordLogs();

        vm.prank(alice);
        mYieldToOne.approve(bob, amount);

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Approval(address,address,bytes)");
        bytes32 plaintextTopic = keccak256("Approval(address,address,uint256)");

        bool foundBytes;
        bool foundPlaintext;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(mYieldToOne)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
            } else if (logs[i].topics[0] == plaintextTopic) {
                foundPlaintext = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), alice);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), bob);
                assertEq(abi.decode(logs[i].data, (uint256)), amount);
            }
        }

        assertTrue(foundPlaintext, "missing plaintext Approval(uint256) emit on infra path");
        assertFalse(foundBytes, "infra path leaked into encrypted-bytes Approval overload");
    }

    /* ============ _shieldedTransfer (plaintext emit) ============ */

    function test_nativeTransferFrom_registeredRecipient_emitsPlaintextOnly() external {
        uint256 amount = 1_000e6;
        mYieldToOne.setBalanceOf(alice, amount);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        vm.prank(alice);
        mYieldToOne.approve(address(swapFacility), suint256(amount));

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);

        vm.recordLogs();

        vm.prank(address(swapFacility));
        mYieldToOne.transferFrom(alice, bob, amount);

        assertEq(mYieldToOne.getEncryptedEventNonce(), 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Transfer(address,address,bytes)");
        bytes32 plaintextTopic = keccak256("Transfer(address,address,uint256)");

        bool foundBytes;
        bool foundPlaintext;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(mYieldToOne)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
            } else if (logs[i].topics[0] == plaintextTopic) {
                foundPlaintext = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), alice);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), bob);
                uint256 emittedAmount = abi.decode(logs[i].data, (uint256));
                assertEq(emittedAmount, amount);
            }
        }

        assertTrue(foundPlaintext, "missing plaintext Transfer(uint256) emit on infra path");
        assertFalse(foundBytes, "infra path leaked into encrypted-bytes Transfer overload");
    }

    /* ============ _mint / _burn ============ */

    function test_mint_emitsPlaintextOnly() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(address(swapFacility), amount);

        _installContractKey();
        _mockPrecompiles();

        vm.prank(alice);
        mYieldToOne.registerPublicKey(_validPubKey(0xBB));

        uint256 nonceBefore = mYieldToOne.getEncryptedEventNonce();

        vm.recordLogs();

        vm.prank(address(swapFacility));
        mYieldToOne.wrap(alice, amount);

        assertEq(mYieldToOne.getEncryptedEventNonce(), nonceBefore);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Transfer(address,address,bytes)");
        bytes32 plaintextTopic = keccak256("Transfer(address,address,uint256)");

        bool foundBytes;
        bool foundPlaintextMint;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(mYieldToOne)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
            } else if (logs[i].topics[0] == plaintextTopic) {
                if (address(uint160(uint256(logs[i].topics[1]))) == address(0)) {
                    foundPlaintextMint = true;
                    assertEq(address(uint160(uint256(logs[i].topics[2]))), alice);
                    assertEq(abi.decode(logs[i].data, (uint256)), amount);
                }
            }
        }

        assertTrue(foundPlaintextMint, "missing plaintext Transfer(0, recipient, amount) on mint");
        assertFalse(foundBytes, "mint leaked into encrypted-bytes Transfer overload");
    }

    function test_burn_emitsPlaintextOnly() external {
        uint256 amount = 1_000e6;

        mYieldToOne.setBalanceOf(address(swapFacility), amount);
        mYieldToOne.setTotalSupply(amount);

        mToken.setBalanceOf(address(mYieldToOne), amount);

        _installContractKey();
        _mockPrecompiles();

        // swapFacility registers a key to prove burn still bypasses the encrypted path.
        vm.prank(address(swapFacility));
        mYieldToOne.registerPublicKey(_validPubKey(0xCC));

        uint256 nonceBefore = mYieldToOne.getEncryptedEventNonce();

        vm.recordLogs();

        vm.prank(address(swapFacility));
        mYieldToOne.unwrap(alice, amount);

        assertEq(mYieldToOne.getEncryptedEventNonce(), nonceBefore);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Transfer(address,address,bytes)");
        bytes32 plaintextTopic = keccak256("Transfer(address,address,uint256)");

        bool foundBytes;
        bool foundPlaintextBurn;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(mYieldToOne)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
            } else if (logs[i].topics[0] == plaintextTopic) {
                if (address(uint160(uint256(logs[i].topics[2]))) == address(0)) {
                    foundPlaintextBurn = true;
                    assertEq(address(uint160(uint256(logs[i].topics[1]))), address(swapFacility));
                    assertEq(abi.decode(logs[i].data, (uint256)), amount);
                }
            }
        }

        assertTrue(foundPlaintextBurn, "missing plaintext Transfer(account, 0, amount) on burn");
        assertFalse(foundBytes, "burn leaked into encrypted-bytes Transfer overload");
    }
}
