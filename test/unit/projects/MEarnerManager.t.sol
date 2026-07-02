// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IAccessControl } from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { Upgrades, UnsafeUpgrades } from "../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMExtension } from "../../../src/interfaces/IMExtension.sol";
import { IMEarnerManager } from "../../../src/projects/earnerManager/IMEarnerManager.sol";
import { IArrayErrors } from "../../../src/interfaces/IArrayErrors.sol";
import { ISwapFacility } from "../../../src/swap/interfaces/ISwapFacility.sol";

import { IPausable } from "../../../src/components/pausable/IPausable.sol";
import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../../lib/common/src/interfaces/IERC20Extended.sol";

import { MEarnerManagerHarness } from "../../harness/MEarnerManagerHarness.sol";
import { BaseUnitTest } from "../../utils/BaseUnitTest.sol";

contract MEarnerManagerUnitTests is BaseUnitTest {
    MEarnerManagerHarness public mEarnerManager;

    uint128 public startIndex = 11e11;

    function setUp() public override {
        super.setUp();

        mToken.setCurrentIndex(startIndex);

        mEarnerManager = MEarnerManagerHarness(
            Upgrades.deployTransparentProxy(
                "MEarnerManagerHarness.sol:MEarnerManagerHarness",
                admin,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    admin,
                    earnerManager,
                    feeRecipient,
                    pauser
                ),
                mExtensionDeployOptions
            )
        );

        // Made mEarnerManager the earner, so it can be used in SwapFacility
        registrar.setEarner(address(mEarnerManager), true);
        mEarnerManager.enableEarning();

        // Whitelist SwapFacility
        mEarnerManager.setAccountOf(address(swapFacility), 0, 0, true, 0);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mEarnerManager.ONE_HUNDRED_PERCENT(), 10_000);
        assertEq(mEarnerManager.feeRecipient(), feeRecipient);
        assertTrue(mEarnerManager.hasRole(PAUSER_ROLE, pauser));
        assertTrue(mEarnerManager.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mEarnerManager.hasRole(EARNER_MANAGER_ROLE, earnerManager));
    }

    function test_initialize_zeroAdmin() external {
        address implementation = address(new MEarnerManagerHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMEarnerManager.ZeroAdmin.selector);
        MEarnerManagerHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    address(0),
                    earnerManager,
                    feeRecipient,
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroEarnerManager() external {
        address implementation = address(new MEarnerManagerHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMEarnerManager.ZeroEarnerManager.selector);
        MEarnerManagerHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    admin,
                    address(0),
                    feeRecipient,
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroFeeRecipient() external {
        address implementation = address(new MEarnerManagerHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMEarnerManager.ZeroFeeRecipient.selector);
        MEarnerManagerHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    admin,
                    earnerManager,
                    address(0),
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroPauser() external {
        address implementation = address(new MEarnerManagerHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IPausable.ZeroPauser.selector);
        MEarnerManagerHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    admin,
                    earnerManager,
                    feeRecipient,
                    address(0)
                )
            )
        );
    }

    /* ============ setAccountInfo ============ */

    function test_setAccountInfo_zeroYieldRecipient() external {
        vm.expectRevert(IMEarnerManager.ZeroAccount.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(address(0), true, 1000);
    }

    function test_setAccountInfo_invalidFeeRate() external {
        vm.expectRevert(IMEarnerManager.InvalidFeeRate.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 10_001);
    }

    function test_setAccountInfo_invalidAccountInfo() external {
        vm.expectRevert(IMEarnerManager.InvalidAccountInfo.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, false, 9_000);
    }

    function test_setAccountInfo_onlyEarnerManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, EARNER_MANAGER_ROLE)
        );

        vm.prank(alice);
        mEarnerManager.setAccountInfo(alice, true, 10_001);
    }

    function test_setAccountInfo_whitelistAccount() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, false, 0);

        assertFalse(mEarnerManager.isWhitelisted(alice));
        assertEq(mEarnerManager.feeRateOf(alice), 0);

        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(alice, true, 1_000);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 1_000);

        assertTrue(mEarnerManager.isWhitelisted(alice));
        assertEq(mEarnerManager.feeRateOf(alice), 1_000);
    }

    function test_setAccountInfo_unwhitelistAccount() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 1_000);

        uint256 yield = mEarnerManager.accruedYieldOf(alice);
        uint256 fee = mEarnerManager.accruedFeeOf(alice);

        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(alice, false, 0);

        vm.expectEmit();
        emit IMEarnerManager.YieldClaimed(alice, yield);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, yield + fee);

        vm.expectEmit();
        emit IMEarnerManager.FeeClaimed(alice, feeRecipient, fee);

        vm.expectEmit();
        emit IERC20.Transfer(alice, feeRecipient, fee);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, false, 0);

        assertEq(mEarnerManager.isWhitelisted(alice), false);
        assertEq(mEarnerManager.feeRateOf(alice), 10_000);

        assertEq(mEarnerManager.balanceOf(alice), 1_000e6 + yield);
        assertEq(mEarnerManager.balanceOf(feeRecipient), fee);
    }

    function test_setAccountInfo_rewhitelistAccount() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 1_000);

        uint256 yield = mEarnerManager.accruedYieldOf(alice);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, false, 0);

        assertEq(mEarnerManager.isWhitelisted(alice), false);
        assertEq(mEarnerManager.balanceOf(alice), 1_000e6 + yield);
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);

        mToken.setCurrentIndex(12e11);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, fee);
        assertEq(yieldNetOfFees, 0);

        uint256 aliceBalanceBefore = mEarnerManager.balanceOf(alice);
        uint256 feeRecipientBalanceBefore = mEarnerManager.balanceOf(feeRecipient);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 1_000);

        // Alice balance didn't change, fee recipient received fee
        assertEq(mEarnerManager.balanceOf(alice), aliceBalanceBefore);
        assertEq(mEarnerManager.balanceOf(feeRecipient), feeRecipientBalanceBefore + fee);
    }

    function test_setAccountInfo_changeFee() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 1_000);

        uint256 yield = mEarnerManager.accruedYieldOf(alice);
        uint256 fee = mEarnerManager.accruedFeeOf(alice);

        // yield is claimed when changing fee rate
        vm.expectEmit();
        emit IMEarnerManager.YieldClaimed(alice, yield);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 2_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 2_000);

        assertEq(mEarnerManager.balanceOf(alice), 1_000e6 + yield);
        assertEq(mEarnerManager.balanceOf(feeRecipient), fee);
    }

    function test_setAccountInfo_noAction() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, false, 0);
        mEarnerManager.setAccountOf(bob, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), false);
        assertEq(mEarnerManager.feeRateOf(alice), 0);

        assertEq(mEarnerManager.isWhitelisted(bob), true);
        assertEq(mEarnerManager.feeRateOf(bob), 1_000);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, false, 0);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(bob, true, 1_000);

        // No changes
        assertEq(mEarnerManager.isWhitelisted(alice), false);
        assertEq(mEarnerManager.feeRateOf(alice), 0);

        assertEq(mEarnerManager.isWhitelisted(bob), true);
        assertEq(mEarnerManager.feeRateOf(bob), 1_000);
    }

    /* ============ setAccountInfo batch ============ */
    function test_setAccountInfo_batch_onlyEarnerManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, EARNER_MANAGER_ROLE)
        );

        vm.prank(alice);
        mEarnerManager.setAccountInfo(new address[](0), new bool[](0), new uint16[](0));
    }

    function test_setAccountInfo_batch_arrayLengthZero() external {
        vm.expectRevert(IMEarnerManager.ArrayLengthZero.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(new address[](0), new bool[](2), new uint16[](2));
    }

    function test_setAccountInfo_batch_arrayLengthMismatch() external {
        vm.expectRevert(IArrayErrors.ArrayLengthMismatch.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(new address[](1), new bool[](2), new uint16[](2));

        vm.expectRevert(IArrayErrors.ArrayLengthMismatch.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(new address[](2), new bool[](1), new uint16[](2));

        vm.expectRevert(IArrayErrors.ArrayLengthMismatch.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(new address[](2), new bool[](2), new uint16[](1));
    }

    function test_setAccountInfo_batch() external {
        address[] memory accounts_ = new address[](2);
        accounts_[0] = alice;
        accounts_[1] = bob;

        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = true;

        uint16[] memory feeRates = new uint16[](2);
        feeRates[0] = 1;
        feeRates[1] = 10_000;

        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(alice, true, 1);

        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(bob, true, 10_000);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(accounts_, statuses, feeRates);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 1);

        assertEq(mEarnerManager.isWhitelisted(bob), true);
        assertEq(mEarnerManager.feeRateOf(bob), 10_000);
    }

    /* ============ setFeeRecipient ============ */

    function test_setFeeRecipient_onlyEarnerManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, EARNER_MANAGER_ROLE)
        );

        vm.prank(alice);
        mEarnerManager.setFeeRecipient(alice);
    }

    function test_setFeeRecipient_zeroFeeRecipient() external {
        vm.expectRevert(IMEarnerManager.ZeroFeeRecipient.selector);

        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(address(0));
    }

    function test_setFeeRecipient_noUpdate() external {
        assertEq(mEarnerManager.feeRecipient(), feeRecipient);

        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(feeRecipient);

        assertEq(mEarnerManager.feeRecipient(), feeRecipient);
    }

    function test_setFeeRecipient() external {
        assertEq(mEarnerManager.feeRecipient(), feeRecipient);

        assertEq(mEarnerManager.feeRateOf(feeRecipient), 0);

        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.expectEmit();
        emit IMEarnerManager.FeeRecipientSet(newFeeRecipient);

        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(newFeeRecipient);

        assertEq(mEarnerManager.feeRecipient(), newFeeRecipient);
        assertEq(mEarnerManager.feeRateOf(newFeeRecipient), 0);
    }

    /* ============ claimFor ============ */

    function test_claimFor_zeroAccount() external {
        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.ZeroAccount.selector));
        mEarnerManager.claimFor(address(0));
    }

    function test_claimFor_noYield() external {
        mEarnerManager.setAccountOf(alice, 1_900e6, 1_000e6, true, 1_000);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, 0);
        assertEq(fee, 0);
        assertEq(yieldNetOfFees, 0);

        assertEq(mEarnerManager.accruedYieldOf(alice), 0);
        assertEq(mEarnerManager.accruedFeeOf(alice), 0);

        (yieldWithFee, fee, yieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(yieldWithFee, 0);
        assertEq(fee, 0);
        assertEq(yieldNetOfFees, 0);
    }

    function test_claimFor() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.isWhitelisted(feeRecipient), true);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 10e6);
        assertEq(yieldNetOfFees, 90e6);

        // Sanity check
        assertEq(yieldWithFee, fee + yieldNetOfFees);

        assertEq(mEarnerManager.accruedYieldOf(alice), 90e6);
        assertEq(mEarnerManager.accruedFeeOf(alice), 10e6);

        vm.expectEmit();
        emit IMEarnerManager.YieldClaimed(alice, yieldNetOfFees);

        vm.expectEmit();
        emit IMEarnerManager.FeeClaimed(alice, feeRecipient, fee);

        (yieldWithFee, fee, yieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 10e6);
        assertEq(yieldNetOfFees, 90e6);

        // Yield + fees were claimed
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);
        assertEq(mEarnerManager.accruedFeeOf(alice), 0);

        // Balances were updated
        assertEq(mEarnerManager.balanceOf(alice), 1_000e6 + yieldNetOfFees);
        assertEq(mEarnerManager.balanceOf(feeRecipient), fee);
    }

    function test_claimFor_feeRecipient() external {
        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(alice);

        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 0);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 0e6);
        assertEq(yieldNetOfFees, 100e6);

        assertEq(mEarnerManager.accruedYieldOf(alice), 100e6);
        assertEq(mEarnerManager.accruedFeeOf(alice), 0e6);

        (yieldWithFee, fee, yieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 0e6);
        assertEq(yieldNetOfFees, 100e6);
    }

    function test_claimFor_fee_100() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 10_000);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 100e6);
        assertEq(yieldNetOfFees, 0e6);

        assertEq(mEarnerManager.accruedYieldOf(alice), 0e6);
        assertEq(mEarnerManager.accruedFeeOf(alice), 100e6);

        (yieldWithFee, fee, yieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 100e6);
        assertEq(yieldNetOfFees, 0e6);
    }

    function test_claimFor_multipleAccounts() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);
        mEarnerManager.setAccountOf(bob, 1_000e6, 1_000e6, true, 2_000);
        mEarnerManager.setAccountOf(carol, 1_000e6, 1_000e6, true, 3_000);
        mEarnerManager.setAccountOf(charlie, 1_000e6, 1_000e6, true, 4_000);
        mEarnerManager.setAccountOf(david, 1_000e6, 1_000e6, true, 5_000);

        address[] memory accounts = new address[](6);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = carol;
        accounts[3] = charlie;
        accounts[4] = david;
        accounts[5] = makeAddr("not-whitelisted");

        (uint256[] memory yieldWithFees, uint256[] memory fees, uint256[] memory yieldNetOfFees) = mEarnerManager
            .claimFor(accounts);

        // alice
        assertEq(yieldWithFees[0], 100e6);
        assertEq(fees[0], 10e6);
        assertEq(yieldNetOfFees[0], 90e6);

        // bob
        assertEq(yieldWithFees[1], 100e6);
        assertEq(fees[1], 20e6);
        assertEq(yieldNetOfFees[1], 80e6);

        // carol
        assertEq(yieldWithFees[2], 100e6);
        assertEq(fees[2], 30e6);
        assertEq(yieldNetOfFees[2], 70e6);

        // charlie
        assertEq(yieldWithFees[3], 100e6);
        assertEq(fees[3], 40e6);
        assertEq(yieldNetOfFees[3], 60e6);

        assertEq(yieldWithFees[4], 100e6);
        assertEq(fees[4], 50e6);
        assertEq(yieldNetOfFees[4], 50e6);

        // Not whitelisted account
        assertEq(yieldWithFees[5], 0);
        assertEq(fees[5], 0);
        assertEq(yieldNetOfFees[5], 0);

        // Yield + fees were claimed
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);
        assertEq(mEarnerManager.accruedFeeOf(alice), 0);
        assertEq(mEarnerManager.accruedYieldOf(bob), 0);
        assertEq(mEarnerManager.accruedFeeOf(bob), 0);
        assertEq(mEarnerManager.accruedYieldOf(carol), 0);
        assertEq(mEarnerManager.accruedFeeOf(carol), 0);
        assertEq(mEarnerManager.accruedYieldOf(charlie), 0);
        assertEq(mEarnerManager.accruedFeeOf(charlie), 0);
        assertEq(mEarnerManager.accruedYieldOf(david), 0);
        assertEq(mEarnerManager.accruedFeeOf(david), 0);

        // Balances were updated
        assertEq(mEarnerManager.balanceOf(alice), 1_000e6 + yieldNetOfFees[0]);
        assertEq(mEarnerManager.balanceOf(bob), 1_000e6 + yieldNetOfFees[1]);
        assertEq(mEarnerManager.balanceOf(carol), 1_000e6 + yieldNetOfFees[2]);
        assertEq(mEarnerManager.balanceOf(charlie), 1_000e6 + yieldNetOfFees[3]);
        assertEq(mEarnerManager.balanceOf(david), 1_000e6 + yieldNetOfFees[4]);

        // Fee recipient balance should be the sum of all fees
        assertEq(mEarnerManager.balanceOf(feeRecipient), 10e6 + 20e6 + 30e6 + 40e6 + 50e6);
    }

    /* ============ _approve ============ */

    function test_approve_notWhitelistedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, alice));

        vm.prank(alice);
        mEarnerManager.approve(bob, 1_000e6);
    }

    /* ============ _wrap ============ */

    function test_wrap_notWhitelistedAccount() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, alice));

        vm.prank(address(swapFacility));
        mEarnerManager.wrap(alice, amount);
    }

    function test_wrap_notWhitelistedRecipient() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, bob));

        vm.prank(address(swapFacility));
        mEarnerManager.wrap(bob, amount);
    }

    function test_wrap_paused() public {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(address(swapFacility), amount);

        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        vm.prank(pauser);
        mEarnerManager.pause();

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(swapFacility.msgSender.selector), abi.encode(bob));

        vm.prank(address(swapFacility));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mEarnerManager.wrap(bob, 1);
    }

    function test_wrap_insufficientAmount() external {
        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        mEarnerManager.wrap(alice, 0);
    }

    function test_wrap_invalidRecipient() external {
        mToken.setBalanceOf(alice, 1_000);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(address(swapFacility));
        mEarnerManager.wrap(address(0), 1_000e6);
    }

    function test_wrap_EarningIsNotEnabled() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        // Disable earning
        mEarnerManager.disableEarning();

        vm.expectRevert(IMExtension.EarningIsDisabled.selector);

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mEarnerManager), amount, alice);
    }

    function test_wrap() external {
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        // M tokens are transferred from Alice to SwapFacility then to MEarnerManager
        mToken.setBalanceOf(address(swapFacility), 2_000);

        assertEq(mToken.balanceOf(address(swapFacility)), 2_000);
        assertEq(mEarnerManager.totalSupply(), 0);
        assertEq(mEarnerManager.balanceOf(alice), 0);
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 1_000);

        vm.prank(address(swapFacility));
        mEarnerManager.wrap(alice, 1_000);

        assertEq(mToken.balanceOf(address(mEarnerManager)), 1_000);
        assertEq(mEarnerManager.totalSupply(), 1_000);
        assertEq(mEarnerManager.balanceOf(alice), 1_000);
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectEmit();
        emit IERC20.Transfer(address(0), bob, 1_000);

        vm.prank(address(swapFacility));
        mEarnerManager.wrap(bob, 1_000);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(address(mEarnerManager)), 2_000);
        assertEq(mEarnerManager.totalSupply(), 2_000);
        assertEq(mEarnerManager.balanceOf(bob), 1_000);
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);

        // simulate yield accrual by increasing index
        mToken.setCurrentIndex(12e11);
        assertEq(mEarnerManager.balanceOf(bob), 1_000);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(bob);
        assertEq(yieldWithFee, 90);
        assertEq(fee, 9);
        assertEq(yieldNetOfFees, 81);
    }

    function testFuzz_wrap(uint128 index, uint256 balance, uint256 wrapAmount) external {
        index = uint128(bound(index, EXP_SCALED_ONE, 10_000000000000));
        mToken.setCurrentIndex(index);

        uint256 max = _getMaxAmount(index);
        balance = bound(balance, 0, max);
        wrapAmount = bound(wrapAmount, 0, max - balance);

        if (wrapAmount > balance) {
            return;
        }

        mToken.setBalanceOf(address(swapFacility), balance);
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        if (wrapAmount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        }

        vm.prank(address(swapFacility));
        mEarnerManager.wrap(alice, wrapAmount);

        if (wrapAmount == 0) return;

        assertEq(mEarnerManager.balanceOf(alice), wrapAmount);
    }

    /* ============ _unwrap ============ */
    function test_unwrap_notWhitelistedAccount() external {
        mEarnerManager.setAccountOf(address(swapFacility), 1_000e6, 1_000e6, false, 1_000);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, alice));

        vm.prank(address(swapFacility));
        mEarnerManager.unwrap(alice, 1_000e6);
    }

    function test_unwrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        mEarnerManager.unwrap(alice, 0);
    }

    function test_unwrap_paused() public {
        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(alice, true, 1_000);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 1_000);

        vm.prank(pauser);
        mEarnerManager.pause();

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(swapFacility.msgSender.selector), abi.encode(alice));

        vm.prank(address(swapFacility));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mEarnerManager.unwrap(alice, 1);
    }

    function test_unwrap_insufficientBalance() external {
        mEarnerManager.setAccountOf(address(swapFacility), 999, 999, true, 1_000);
        mEarnerManager.setAccountOf(alice, 999, 999, true, 1_000);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(
            abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, address(swapFacility), 999, 1_000)
        );

        vm.prank(address(swapFacility));
        mEarnerManager.unwrap(alice, 1_000);
    }

    function test_unwrap() external {
        mToken.setBalanceOf(address(mEarnerManager), 1000);
        mEarnerManager.setAccountOf(address(swapFacility), 1_000, 1_000, true, 1_000);
        mEarnerManager.setAccountOf(alice, 1_000, 1_000, true, 1_000);
        mEarnerManager.setTotalSupply(1_000);
        mEarnerManager.setTotalPrincipal(1_000);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(mEarnerManager.balanceOf(alice), 1_000);
        assertEq(mEarnerManager.totalSupply(), 1_000);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 1);

        vm.prank(address(swapFacility));
        mEarnerManager.unwrap(alice, 1);

        assertEq(mEarnerManager.totalSupply(), 999);
        assertEq(mEarnerManager.balanceOf(address(swapFacility)), 999);

        // M token is transferred to swap facility and then to Alice
        assertEq(mToken.balanceOf(address(swapFacility)), 1);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 499);

        vm.prank(address(swapFacility));
        mEarnerManager.unwrap(alice, 499);

        assertEq(mEarnerManager.totalSupply(), 500);
        assertEq(mEarnerManager.balanceOf(address(swapFacility)), 500);
        assertEq(mToken.balanceOf(address(swapFacility)), 500);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 500);

        vm.prank(address(swapFacility));
        mEarnerManager.unwrap(alice, 500);

        assertEq(mEarnerManager.totalSupply(), 0);
        assertEq(mEarnerManager.balanceOf(address(swapFacility)), 0);
        assertEq(mToken.balanceOf(address(swapFacility)), 1000);
    }

    function testFuzz_unwrap(uint128 index, uint256 balance, uint256 unwrapAmount) external {
        index = uint128(bound(index, EXP_SCALED_ONE, 10_000000000000));
        mToken.setCurrentIndex(index);

        uint256 max = _getMaxAmount(index);
        balance = bound(balance, 0, max);
        unwrapAmount = bound(unwrapAmount, 0, max);

        uint112 principal = _getPrincipal(balance, index);
        mEarnerManager.setAccountOf(address(swapFacility), balance, principal, true, 1_000);
        mEarnerManager.setAccountOf(alice, balance, principal, true, 1_000);
        mEarnerManager.setTotalSupply(balance);
        mEarnerManager.setTotalPrincipal(principal);

        mToken.setBalanceOf(address(mEarnerManager), balance);

        uint256 actualBalance = mEarnerManager.balanceOf(alice);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        if (unwrapAmount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        } else if (unwrapAmount > actualBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMExtension.InsufficientBalance.selector,
                    address(swapFacility),
                    actualBalance,
                    unwrapAmount
                )
            );
        }

        vm.prank(address(swapFacility));
        mEarnerManager.unwrap(alice, unwrapAmount);

        if (unwrapAmount == 0 || unwrapAmount > actualBalance) return;

        assertEq(mEarnerManager.balanceOf(address(swapFacility)), actualBalance - unwrapAmount);
        assertEq(mToken.balanceOf(address(swapFacility)), unwrapAmount);
    }

    /* ============ _transfer ============ */
    function test_transfer_insufficientBalance() external {
        uint256 amount = 1_000e6;

        mEarnerManager.setAccountOf(alice, amount, _getPrincipal(amount, startIndex), true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, amount, amount + 1));

        vm.prank(alice);
        mEarnerManager.transfer(bob, amount + 1);
    }

    function test_transfer_paused() public {
        uint256 amount = 1_000e6;

        mEarnerManager.setAccountOf(alice, amount, _getPrincipal(amount, startIndex), true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        vm.prank(pauser);
        mEarnerManager.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(alice);
        mEarnerManager.transfer(bob, 1);
    }

    function test_transfer_notWhitelistedSender() external {
        mEarnerManager.setAccountOf(alice, 0, 0, false, 0);

        // Alice is not whitelisted, cannot transfer her tokens
        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, alice));

        vm.prank(alice);
        mEarnerManager.transfer(bob, 1_000e6);
    }

    function test_transfer_notWhitelistedApprovedSender() external {
        uint256 amount = 1_000e6;

        mEarnerManager.setAccountOf(alice, amount, _getPrincipal(amount, startIndex), true, 1_000);
        mEarnerManager.setAccountOf(carol, 0, 0, true, 0);

        // Alice allows Carol to transfer tokens on her behalf
        vm.prank(alice);
        mEarnerManager.approve(carol, amount);

        mEarnerManager.setAccountOf(carol, 0, 0, false, 0);

        // Reverts cause Carol is frozen and cannot transfer tokens on Alice's behalf
        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, carol));

        vm.prank(carol);
        mEarnerManager.transferFrom(alice, bob, amount);
    }

    function test_transfer_notWhitelistedRecipient() external {
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, bob));

        vm.prank(alice);
        mEarnerManager.transfer(bob, 1_000e6);
    }

    function test_transfer_invalidRecipient() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, 0));

        vm.prank(alice);
        mEarnerManager.transfer(address(0), 1_000e6);
    }

    function test_transfer() external {
        uint256 amount = 1_000e6;

        mEarnerManager.setAccountOf(alice, amount, _getPrincipal(amount, startIndex), true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount);

        vm.prank(alice);
        mEarnerManager.transfer(bob, amount);

        assertEq(mEarnerManager.balanceOf(alice), 0);
        assertEq(mEarnerManager.balanceOf(bob), amount);
    }

    function testFuzz_transfer(uint128 index, uint256 aliceBalance, uint256 transferAmount) external {
        index = uint128(bound(index, EXP_SCALED_ONE, 10_000000000000));
        mToken.setCurrentIndex(index);

        aliceBalance = bound(aliceBalance, 0, _getMaxAmount(index));
        transferAmount = bound(transferAmount, 0, _getMaxAmount(index));

        mEarnerManager.setAccountOf(alice, aliceBalance, _getPrincipal(aliceBalance, index), true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        if (transferAmount > aliceBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, aliceBalance, transferAmount)
            );
        }

        vm.prank(alice);
        mEarnerManager.transfer(bob, transferAmount);

        if (transferAmount > aliceBalance) return;

        assertEq(mEarnerManager.balanceOf(alice), aliceBalance - transferAmount);
        assertEq(mEarnerManager.balanceOf(bob), transferAmount);
    }

    /* ============ enableEarning ============ */

    function test_enableEarning_earningEnabled() external {
        vm.expectRevert(IMEarnerManager.EarningCannotBeReenabled.selector);
        mEarnerManager.enableEarning();
    }

    function test_enableEarning() external {
        // Disable earning first to be able to re-enable it
        mEarnerManager.setWasEarningEnabled(false);

        mToken.setCurrentIndex(1_210000000000);

        vm.expectEmit();
        emit IMExtension.EarningEnabled(1_210000000000);

        mEarnerManager.enableEarning();

        assertEq(mEarnerManager.isEarningEnabled(), true);
        assertEq(mEarnerManager.wasEarningEnabled(), true);
        assertEq(mEarnerManager.disableIndex(), 0);
    }

    /* ============ disableEarning ============ */

    function test_disableEarning_earningIsDisabled() external {
        mEarnerManager.disableEarning();

        vm.expectRevert(IMExtension.EarningIsDisabled.selector);
        mEarnerManager.disableEarning();
    }

    function test_disableEarning_earningWasNotEnabled() external {
        mEarnerManager.setWasEarningEnabled(false);

        vm.expectRevert(IMExtension.EarningIsDisabled.selector);
        mEarnerManager.disableEarning();
    }

    function test_disableEarning() external {
        mToken.setCurrentIndex(12e11);

        assertEq(mEarnerManager.currentIndex(), 12e11);

        vm.expectEmit();
        emit IMExtension.EarningDisabled(12e11);

        mEarnerManager.disableEarning();

        assertEq(mEarnerManager.isEarningEnabled(), false);
        assertEq(mEarnerManager.disableIndex(), 12e11);
        assertEq(mEarnerManager.currentIndex(), 12e11);

        mToken.setCurrentIndex(13e11);

        assertEq(mEarnerManager.currentIndex(), 12e11);
    }
}
