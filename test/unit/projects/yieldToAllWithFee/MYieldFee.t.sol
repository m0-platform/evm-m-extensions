// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IAccessControl } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { Upgrades, UnsafeUpgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IndexingMath } from "../../../../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../../../../lib/common/src/libs/UIntMath.sol";
import { ContinuousIndexingMath } from "../../../../lib/common/src/libs/ContinuousIndexingMath.sol";

import { IMExtension } from "../../../../src/interfaces/IMExtension.sol";
import { IMTokenLike } from "../../../../src/interfaces/IMTokenLike.sol";
import { IMYieldFee } from "../../../../src/projects/yieldToAllWithFee/interfaces/IMYieldFee.sol";
import { ISwapFacility } from "../../../../src/swap/interfaces/ISwapFacility.sol";

import { IPausable } from "../../../../src/components/pausable/IPausable.sol";
import { IFreezable } from "../../../../src/components/freezable/IFreezable.sol";
import { IERC20 } from "../../../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../../../lib/common/src/interfaces/IERC20Extended.sol";

import { MYieldFeeHarness } from "../../../harness/MYieldFeeHarness.sol";
import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract MYieldFeeUnitTests is BaseUnitTest {
    /// @dev Each principal rounding (down on mint, up on burn and transfer) loses less than `index / EXP_SCALED_ONE`.
    ///      The fuzz tests bound the index to `10 * EXP_SCALED_ONE` and round each account at most two times.
    uint256 internal constant MAX_ROUNDING_DELTA = 20;

    MYieldFeeHarness public mYieldFee;

    function setUp() public override {
        super.setUp();

        mYieldFee = MYieldFeeHarness(
            Upgrades.deployTransparentProxy(
                "MYieldFeeHarness.sol:MYieldFeeHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    "MYieldFee",
                    "MYF",
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    feeManager,
                    claimRecipientManager,
                    freezeManager,
                    pauser
                ),
                mExtensionDeployOptions
            )
        );

        registrar.setEarner(address(mYieldFee), true);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mYieldFee.ONE_HUNDRED_PERCENT(), 10_000);
        assertEq(mYieldFee.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.feeRate(), YIELD_FEE_RATE);
        assertEq(mYieldFee.feeRecipient(), feeRecipient);

        assertTrue(mYieldFee.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldFee.hasRole(FEE_MANAGER_ROLE, feeManager));
        assertTrue(mYieldFee.hasRole(CLAIM_RECIPIENT_MANAGER_ROLE, claimRecipientManager));
        assertTrue(mYieldFee.hasRole(PAUSER_ROLE, pauser));
        assertTrue(mYieldFee.hasRole(FREEZE_MANAGER_ROLE, freezeManager));
    }

    function test_initialize_zeroFeeRecipient() external {
        address implementation = address(new MYieldFeeHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMYieldFee.ZeroFeeRecipient.selector);
        MYieldFeeHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    "MYieldFee",
                    "MYF",
                    YIELD_FEE_RATE,
                    address(0),
                    admin,
                    feeManager,
                    claimRecipientManager,
                    freezeManager,
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroAdmin() external {
        address implementation = address(new MYieldFeeHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMYieldFee.ZeroAdmin.selector);
        MYieldFeeHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    "MYieldFee",
                    "MYF",
                    YIELD_FEE_RATE,
                    feeRecipient,
                    address(0),
                    feeManager,
                    claimRecipientManager,
                    freezeManager,
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroFeeManager() external {
        address implementation = address(new MYieldFeeHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMYieldFee.ZeroFeeManager.selector);
        MYieldFeeHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    "MYieldFee",
                    "MYF",
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    address(0),
                    claimRecipientManager,
                    freezeManager,
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroClaimRecipientManager() external {
        address implementation = address(new MYieldFeeHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IMYieldFee.ZeroClaimRecipientManager.selector);
        MYieldFeeHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    "MYieldFee",
                    "MYF",
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    feeManager,
                    address(0),
                    freezeManager,
                    pauser
                )
            )
        );
    }

    function test_initialize_zeroPauser() external {
        address implementation = address(new MYieldFeeHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IPausable.ZeroPauser.selector);
        MYieldFeeHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    "MYieldFee",
                    "MYF",
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    feeManager,
                    claimRecipientManager,
                    freezeManager,
                    address(0)
                )
            )
        );
    }

    function test_initialize_zeroFreezeManager() external {
        address implementation = address(new MYieldFeeHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IFreezable.ZeroFreezeManager.selector);
        MYieldFeeHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    "MYieldFee",
                    "MYF",
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    feeManager,
                    claimRecipientManager,
                    address(0),
                    pauser
                )
            )
        );
    }

    /* ============ claimYieldFor ============ */

    function test_claimYieldFor_zeroYieldRecipient() external {
        vm.expectRevert(IMYieldFee.ZeroAccount.selector);
        mYieldFee.claimYieldFor(address(0));
    }

    function test_claimYieldFor_noYield() external {
        assertEq(mYieldFee.claimYieldFor(alice), 0);
    }

    function test_claimYieldFor() external {
        uint240 yieldAmount = 79_230399;
        uint240 aliceBalance = 1_000e6;

        mToken.setBalanceOf(address(mYieldFee), yieldAmount);
        mYieldFee.setAccountOf(alice, aliceBalance, 1_000e6);
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        vm.expectEmit();
        emit IMYieldFee.YieldClaimed(alice, alice, yieldAmount);

        vm.prank(alice);
        assertEq(mYieldFee.claimYieldFor(alice), yieldAmount);

        aliceBalance += yieldAmount;

        assertEq(mYieldFee.balanceOf(alice), aliceBalance);
        assertEq(mYieldFee.accruedYieldOf(alice), 0);

        // 8.5% M Yield Fee index growth
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldFee.currentIndex(), 1_164738254609);

        yieldAmount = 85_507855;

        vm.expectEmit();
        emit IMYieldFee.YieldClaimed(alice, alice, yieldAmount);

        vm.prank(alice);
        assertEq(mYieldFee.claimYieldFor(alice), yieldAmount);

        aliceBalance += yieldAmount;

        assertEq(mYieldFee.balanceOf(alice), aliceBalance);
        assertEq(mYieldFee.accruedYieldOf(alice), 0);
    }

    function test_claimYieldFor_claimRecipient() external {
        uint240 yieldAmount = 79_230399;
        uint240 aliceBalance = 1_000e6;
        uint240 bobBalance = 0;
        uint240 carolBalance = 0;

        mToken.setBalanceOf(address(mYieldFee), yieldAmount);
        mYieldFee.setAccountOf(alice, aliceBalance, 1_000e6);
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        assertEq(mYieldFee.claimRecipientFor(alice), alice);

        vm.prank(claimRecipientManager);
        mYieldFee.setClaimRecipient(alice, bob);

        assertEq(mYieldFee.claimRecipientFor(alice), bob);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        assertEq(mYieldFee.accruedYieldOf(alice), yieldAmount);

        vm.expectEmit();
        emit IMYieldFee.YieldClaimed(alice, bob, yieldAmount);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), bob, yieldAmount);

        vm.prank(alice);
        assertEq(mYieldFee.claimYieldFor(alice), yieldAmount);

        bobBalance += yieldAmount;

        assertEq(mYieldFee.balanceOf(alice), aliceBalance);
        assertEq(mYieldFee.balanceOf(bob), bobBalance);
        assertEq(mYieldFee.accruedYieldOf(alice), 0);

        vm.prank(claimRecipientManager);
        mYieldFee.setClaimRecipient(alice, carol);

        // 8.5% M Yield Fee index growth
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldFee.currentIndex(), 1_164738254609);

        yieldAmount = 79_230399;
        uint240 bobYieldAmount = 6_277456;

        assertEq(mYieldFee.claimRecipientFor(alice), carol);

        assertEq(mYieldFee.accruedYieldOf(alice), yieldAmount);
        assertEq(mYieldFee.accruedYieldOf(bob), bobYieldAmount);

        vm.expectEmit();
        emit IMYieldFee.YieldClaimed(alice, carol, yieldAmount);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), carol, yieldAmount);

        vm.prank(alice);
        assertEq(mYieldFee.claimYieldFor(alice), yieldAmount);

        carolBalance += yieldAmount;

        assertEq(mYieldFee.balanceOf(alice), aliceBalance);
        assertEq(mYieldFee.balanceOf(bob), bobBalance);
        assertEq(mYieldFee.balanceOf(carol), carolBalance);

        assertEq(mYieldFee.accruedYieldOf(alice), 0);
        assertEq(mYieldFee.accruedYieldOf(bob), bobYieldAmount);
    }

    function testFuzz_claimYieldFor(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        _setupAccount(alice, balanceWithYield, balance);

        uint256 yieldAmount = mYieldFee.accruedYieldOf(alice);

        if (yieldAmount != 0) {
            vm.expectEmit();
            emit IMYieldFee.YieldClaimed(alice, alice, yieldAmount);
        }

        uint256 aliceBanceBefore = mYieldFee.balanceOf(alice);

        vm.prank(alice);
        assertEq(mYieldFee.claimYieldFor(alice), yieldAmount);

        assertEq(mYieldFee.balanceOf(alice), aliceBanceBefore + yieldAmount);
        assertEq(mYieldFee.accruedYieldOf(alice), 0);
    }

    /* ============ claimFee ============ */

    function test_claimFee_noYield() external {
        assertEq(mYieldFee.claimFee(), 0);
    }

    function test_claimFee() external {
        uint256 yieldFeeAmount = 20_769600;

        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        // 1_100e6 balance with yield without fee.
        mYieldFee.setTotalSupply(1_000e6);
        mYieldFee.setTotalPrincipal(1_000e6);
        assertEq(mYieldFee.totalAccruedYield(), 79_230399); // Should be 100 - 100 * 20% = 80 but it rounds down

        mToken.setBalanceOf(address(mYieldFee), 1_100e6);
        assertEq(mYieldFee.totalAccruedFee(), yieldFeeAmount);

        vm.expectEmit();
        emit IMYieldFee.FeeClaimed(alice, feeRecipient, yieldFeeAmount);

        vm.prank(alice);
        assertEq(mYieldFee.claimFee(), yieldFeeAmount);

        assertEq(mYieldFee.balanceOf(feeRecipient), yieldFeeAmount);
        assertEq(mYieldFee.totalAccruedFee(), 0);

        // 8.5% M Yield Fee index growth
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldFee.currentIndex(), 1_164738254609);

        assertEq(mYieldFee.totalAccruedYield(), 166_383838);

        uint256 secondYieldFeeAmount = 22_846561;

        // 1_210e6 balance with yield without fee.
        mToken.setBalanceOf(address(mYieldFee), 1_210e6);
        assertEq(mYieldFee.totalAccruedFee(), secondYieldFeeAmount);

        vm.expectEmit();
        emit IMYieldFee.FeeClaimed(alice, feeRecipient, secondYieldFeeAmount);

        vm.prank(alice);
        assertEq(mYieldFee.claimFee(), secondYieldFeeAmount);

        assertEq(mYieldFee.balanceOf(feeRecipient), yieldFeeAmount + secondYieldFeeAmount);
        assertEq(mYieldFee.totalAccruedFee(), 0);
    }

    function testFuzz_claimFee(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 totalSupplyWithYield,
        uint240 totalSupply,
        uint240 mBalance
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        uint240 maxAmount = _getMaxAmount(currentIndex);

        (totalSupplyWithYield, totalSupply) = _getFuzzedBalances(
            currentIndex,
            totalSupplyWithYield,
            totalSupply,
            maxAmount
        );

        _setupSupply(totalSupplyWithYield, totalSupply);
        mToken.setBalanceOf(address(mYieldFee), mBalance);

        uint256 projectedTotalSupply = mYieldFee.projectedTotalSupply();

        vm.assume(mBalance > projectedTotalSupply);

        uint256 totalAccruedFee = mBalance - projectedTotalSupply;

        vm.assume(uint256(totalSupplyWithYield) + totalAccruedFee <= maxAmount);

        uint256 yieldFeeAmount = mYieldFee.totalAccruedFee();

        if (yieldFeeAmount != 0) {
            vm.expectEmit();
            emit IMYieldFee.FeeClaimed(alice, feeRecipient, yieldFeeAmount);

            vm.expectEmit();
            emit IERC20.Transfer(address(0), feeRecipient, yieldFeeAmount);
        }

        uint256 feeRecipientBalanceBefore = mYieldFee.balanceOf(feeRecipient);

        vm.prank(alice);
        assertEq(mYieldFee.claimFee(), yieldFeeAmount);

        assertEq(mYieldFee.balanceOf(feeRecipient), feeRecipientBalanceBefore + yieldFeeAmount);
        assertEq(mYieldFee.totalSupply(), totalSupply + yieldFeeAmount);
        assertEq(mYieldFee.totalAccruedFee(), 0);
    }

    /* ============ enableEarning ============ */

    function test_enableEarning_earningIsEnabled() external {
        mYieldFee.setIsEarningEnabled(true);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.EarningIsEnabled.selector));
        mYieldFee.enableEarning();
    }

    function test_enableEarning() external {
        assertEq(mYieldFee.currentIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.latestRate(), 0);

        vm.expectEmit();
        emit IMExtension.EarningEnabled(EXP_SCALED_ONE);

        mYieldFee.enableEarning();

        assertEq(mYieldFee.currentIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.latestRate(), mYiedFeeEarnerRate);

        vm.warp(30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);
    }

    /* ============ disableEarning ============ */

    function test_disableEarning_earningIsDisabled() external {
        vm.expectRevert(IMExtension.EarningIsDisabled.selector);
        mYieldFee.disableEarning();
    }

    function test_disableEarning() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);
        mYieldFee.setLatestIndex(1_100000000000);

        assertEq(mYieldFee.currentIndex(), 1_100000000000);
        assertEq(mYieldFee.latestIndex(), 1_100000000000);
        assertEq(mYieldFee.latestRate(), mYiedFeeEarnerRate);

        vm.warp(30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_187153439146);

        vm.expectEmit();
        emit IMExtension.EarningDisabled(1_187153439146);

        mYieldFee.disableEarning();

        assertFalse(mYieldFee.isEarningEnabled());
        assertEq(mYieldFee.currentIndex(), 1_187153439146);
        assertEq(mYieldFee.latestIndex(), 1_187153439146);
        assertEq(mYieldFee.latestRate(), 0);

        vm.warp(30_057_038 * 2);

        // Index should not change
        assertEq(mYieldFee.currentIndex(), 1_187153439146);
        assertEq(mYieldFee.updateIndex(), 1_187153439146);

        // State should not change after updating the index
        assertEq(mYieldFee.currentIndex(), 1_187153439146);
        assertEq(mYieldFee.latestIndex(), 1_187153439146);
        assertEq(mYieldFee.latestRate(), 0);
    }

    /* ============ setFeeRate ============ */

    function test_setFeeRate_onlyYieldFeeManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, FEE_MANAGER_ROLE)
        );

        vm.prank(alice);
        mYieldFee.setFeeRate(0);
    }

    function test_setFeeRate_feeRateTooHigh() external {
        vm.expectRevert(
            abi.encodeWithSelector(IMYieldFee.FeeRateTooHigh.selector, ONE_HUNDRED_PERCENT + 1, ONE_HUNDRED_PERCENT)
        );

        vm.prank(feeManager);
        mYieldFee.setFeeRate(ONE_HUNDRED_PERCENT + 1);
    }

    function test_setFeeRate_noUpdate() external {
        assertEq(mYieldFee.feeRate(), YIELD_FEE_RATE);

        vm.prank(feeManager);
        mYieldFee.setFeeRate(YIELD_FEE_RATE);

        assertEq(mYieldFee.feeRate(), YIELD_FEE_RATE);
    }

    function test_setFeeRate() external {
        // Reset rate
        vm.prank(feeManager);
        mYieldFee.setFeeRate(0);

        vm.expectEmit();
        emit IMYieldFee.FeeRateSet(YIELD_FEE_RATE);

        vm.prank(feeManager);
        mYieldFee.setFeeRate(YIELD_FEE_RATE);

        assertEq(mYieldFee.feeRate(), YIELD_FEE_RATE);
    }

    /* ============ setFeeRecipient ============ */

    function test_setFeeRecipient_onlyFeeManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, FEE_MANAGER_ROLE)
        );

        vm.prank(alice);
        mYieldFee.setFeeRecipient(alice);
    }

    function test_setFeeRecipient_zeroFeeRecipient() external {
        vm.expectRevert(IMYieldFee.ZeroFeeRecipient.selector);

        vm.prank(feeManager);
        mYieldFee.setFeeRecipient(address(0));
    }

    function test_setFeeRecipient_noUpdate() external {
        assertEq(mYieldFee.feeRecipient(), feeRecipient);

        vm.prank(feeManager);
        mYieldFee.setFeeRecipient(feeRecipient);

        assertEq(mYieldFee.feeRecipient(), feeRecipient);
    }

    function test_setFeeRecipient() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        mToken.setBalanceOf(address(mYieldFee), 1_100e6);

        uint256 yieldFee = mYieldFee.totalAccruedFee();

        address newYieldFeeRecipient = makeAddr("newYieldFeeRecipient");

        vm.expectEmit();
        emit IMYieldFee.FeeClaimed(feeManager, feeRecipient, yieldFee);

        vm.expectEmit();
        emit IMYieldFee.FeeRecipientSet(newYieldFeeRecipient);

        vm.prank(feeManager);
        mYieldFee.setFeeRecipient(newYieldFeeRecipient);

        assertEq(mYieldFee.feeRecipient(), newYieldFeeRecipient);
    }

    /* ============ setClaimRecipient ============ */

    function test_setClaimRecipient_onlyClaimRecipientManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                CLAIM_RECIPIENT_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        mYieldFee.setClaimRecipient(alice, bob);
    }

    function test_setClaimRecipient_zeroAccount() external {
        vm.expectRevert(IMYieldFee.ZeroAccount.selector);

        vm.prank(claimRecipientManager);
        mYieldFee.setClaimRecipient(address(0), alice);
    }

    function test_setClaimRecipient_zeroClaimRecipient() external {
        vm.expectRevert(IMYieldFee.ZeroClaimRecipient.selector);

        vm.prank(claimRecipientManager);
        mYieldFee.setClaimRecipient(alice, address(0));
    }

    function test_setClaimRecipient() external {
        address newClaimRecipient = makeAddr("newClaimRecipient");
        assertEq(mYieldFee.claimRecipientFor(alice), alice);

        vm.expectEmit();
        emit IMYieldFee.ClaimRecipientSet(alice, newClaimRecipient); // default claim recipient is the account itself

        vm.prank(claimRecipientManager);
        mYieldFee.setClaimRecipient(alice, newClaimRecipient);

        assertEq(mYieldFee.claimRecipientFor(alice), newClaimRecipient);
    }

    function test_setClaimRecipient_claimYield() external {
        uint240 yieldAmount = 79_230399;
        uint240 aliceBalance = 1_000e6;

        mToken.setBalanceOf(address(mYieldFee), yieldAmount);
        mYieldFee.setAccountOf(alice, aliceBalance, 1_000e6);
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% index growth
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        vm.expectEmit();
        emit IMYieldFee.YieldClaimed(alice, alice, yieldAmount);

        vm.prank(claimRecipientManager);
        mYieldFee.setClaimRecipient(alice, bob);

        assertEq(mYieldFee.balanceOf(alice), aliceBalance + yieldAmount);
        assertEq(mYieldFee.accruedYieldOf(alice), 0);

        vm.prank(alice);
        uint256 yield = mYieldFee.claimYieldFor(alice);
        assertEq(yield, 0);
    }

    /* ============ currentIndex ============ */

    function test_currentIndex() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        uint256 expectedIndex = EXP_SCALED_ONE;
        assertEq(mYieldFee.currentIndex(), expectedIndex);

        uint256 nextTimestamp = vm.getBlockTimestamp() + 365 days;
        vm.warp(nextTimestamp);

        expectedCurrentIndex = _getCurrentIndex(EXP_SCALED_ONE, mYiedFeeEarnerRate, startTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        uint40 previousTimestamp = uint40(nextTimestamp);

        nextTimestamp = vm.getBlockTimestamp() + 365 days * 2;
        vm.warp(nextTimestamp);

        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);

        // Half the earner rate
        mToken.setEarnerRate(M_EARNER_RATE / 2);
        mYiedFeeEarnerRate = _getEarnerRate(M_EARNER_RATE / 2, YIELD_FEE_RATE);

        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.latestRate(), mYiedFeeEarnerRate);

        previousTimestamp = uint40(nextTimestamp);

        nextTimestamp = vm.getBlockTimestamp() + 365 days * 3;
        vm.warp(nextTimestamp);

        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        // Disable earning
        mYieldFee.disableEarning();

        previousTimestamp = uint40(nextTimestamp);

        nextTimestamp = vm.getBlockTimestamp() + 365 days * 4;
        vm.warp(nextTimestamp);

        // Index should not change
        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);

        // Re-enable earning
        mToken.setEarnerRate(M_EARNER_RATE);
        mYieldFee.enableEarning();

        mYiedFeeEarnerRate = _getEarnerRate(M_EARNER_RATE, YIELD_FEE_RATE);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        // Index was just re-enabled, so value should still be the same
        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);

        previousTimestamp = uint40(nextTimestamp);

        nextTimestamp = vm.getBlockTimestamp() + 365 days * 5;
        vm.warp(nextTimestamp);

        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);
        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);
    }

    function testFuzz_currentIndex(
        uint32 earnerRate,
        uint32 nextEarnerRate,
        uint16 feeRate,
        uint16 nextYieldFeeRate,
        bool isEarningEnabled,
        uint128 latestIndex,
        uint40 latestUpdateTimestamp,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        latestUpdateTimestamp = uint40(bound(latestUpdateTimestamp, 0, type(uint40).max - 2));
        nextTimestamp = uint40(bound(nextTimestamp, latestUpdateTimestamp + 1, type(uint40).max - 1));
        finalTimestamp = uint40(bound(finalTimestamp, nextTimestamp + 1, type(uint40).max));

        feeRate = _setupYieldFeeRate(feeRate);

        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(earnerRate));
        uint32 latestRate = mYieldFee.latestRate();

        mYieldFee.setIsEarningEnabled(isEarningEnabled);
        latestIndex = _setupLatestIndex(latestIndex);
        latestRate = _setupLatestRate(latestRate);

        vm.warp(latestUpdateTimestamp);
        mYieldFee.setLatestUpdateTimestamp(latestUpdateTimestamp);

        // No change in timestamp, so the index should be equal to the latest stored index
        assertEq(mYieldFee.currentIndex(), latestIndex);

        vm.warp(nextTimestamp);

        uint128 expectedIndex = isEarningEnabled
            ? _getCurrentIndex(latestIndex, latestRate, latestUpdateTimestamp)
            : latestIndex;

        assertEq(mYieldFee.currentIndex(), expectedIndex);

        // Update yield fee rate and M earner rate
        feeRate = _setupYieldFeeRate(nextYieldFeeRate);

        vm.mockCall(
            address(mToken),
            abi.encodeWithSelector(IMTokenLike.earnerRate.selector),
            abi.encode(nextEarnerRate)
        );

        latestRate = mYieldFee.latestRate();
        latestRate = _setupLatestRate(latestRate);

        vm.warp(finalTimestamp);

        // expectedIndex was saved as the latest index and nextTimestamp is the latest saved timestamp
        expectedIndex = isEarningEnabled ? _getCurrentIndex(expectedIndex, latestRate, nextTimestamp) : latestIndex;
        assertEq(mYieldFee.currentIndex(), expectedIndex);
    }

    /* ============ earnerRate ============ */

    function test_earnerRate_earningIsEnabled() external {
        uint32 mEarnerRate = 415;
        mYieldFee.setIsEarningEnabled(true);

        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(mEarnerRate));

        assertEq(mYieldFee.earnerRate(), _getEarnerRate(mEarnerRate, YIELD_FEE_RATE));
    }

    function test_earnerRate_earningIsDisabled() external {
        uint32 mEarnerRate = 415;
        mYieldFee.setIsEarningEnabled(false);

        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(mEarnerRate));

        assertEq(mYieldFee.earnerRate(), 0);
    }

    /* ============ _latestEarnerRateAccrualTimestamp ============ */

    function test_latestEarnerRateAccrualTimestamp() external {
        uint40 timestamp = uint40(22470340);

        vm.warp(timestamp);

        assertEq(mYieldFee.latestEarnerRateAccrualTimestamp(), timestamp);
    }

    /* ============ _currentEarnerRate ============ */

    function test_currentEarnerRate() external {
        uint32 earnerRate = 415;

        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(earnerRate));

        assertEq(mYieldFee.currentEarnerRate(), earnerRate);
    }

    /* ============ accruedYieldOf ============ */

    function test_accruedYieldOf() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        mYieldFee.setAccountOf(alice, 500, 500); // 550 balance with yield without fee.
        assertEq(mYieldFee.accruedYieldOf(alice), 39); // Should be 50 - 50 * 20% = 40 but it rounds down.

        mYieldFee.setAccountOf(alice, 1_000, 1_000); // 1_100 balance with yield without fee.
        assertEq(mYieldFee.accruedYieldOf(alice), 79); // Should be 100 - 100 * 20% = 80 but it rounds down.

        // 8.5% M Yield Fee index growth
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldFee.currentIndex(), 1_164738254609);

        assertEq(mYieldFee.accruedYieldOf(alice), 164); // Would be 210 - 210 * 20% = 168 if the index wasn't compounding.

        mYieldFee.setAccountOf(alice, 1_000, 1_500); // 1_885 balance with yield without fee.

        // Present balance at fee-adjusted index (1_747) - balance (1_000)
        assertEq(mYieldFee.accruedYieldOf(alice), 747);
    }

    function testFuzz_accruedYieldOf(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        uint112 principal = _setupAccount(alice, balanceWithYield, balance);
        (, uint240 expectedYield) = _getBalanceWithYield(balance, principal, currentIndex);

        assertEq(mYieldFee.accruedYieldOf(alice), expectedYield);

        vm.assume(finalTimestamp > nextTimestamp);

        vm.warp(finalTimestamp);

        (, expectedYield) = _getBalanceWithYield(balance, principal, mYieldFee.currentIndex());
        assertEq(mYieldFee.accruedYieldOf(alice), expectedYield);
    }

    /* ============ balanceOf ============ */

    function test_balanceOf() external {
        uint240 balance = 1_000e6;
        mYieldFee.setAccountOf(alice, balance, 800e6);

        assertEq(mYieldFee.balanceOf(alice), balance);
    }

    /* ============ balanceWithYieldOf ============ */

    function test_balanceWithYieldOf() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        mYieldFee.setAccountOf(alice, 500e6, 500e6); // 550 balance with yield without fee
        assertEq(mYieldFee.balanceWithYieldOf(alice), 500e6 + 39_615199); // Should be 540 but it rounds down

        mYieldFee.setAccountOf(alice, 1_000e6, 1_000e6); // 1_100 balance with yield without fee
        assertEq(mYieldFee.balanceWithYieldOf(alice), 1_000e6 + 79_230399); // Should be 1_080 but it rounds down

        // 8.5% M Yield Fee index growth
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldFee.currentIndex(), 1_164738254609);

        assertEq(mYieldFee.balanceWithYieldOf(alice), 1_000e6 + 164_738254); // Would be 1_168 if the index wasn't compounding

        mYieldFee.setAccountOf(alice, 1_000e6, 1_500e6); // 1_885 balance with yield without fee.

        // Present balance at fee-adjusted index (1_747)
        assertEq(mYieldFee.balanceWithYieldOf(alice), 1_000e6 + 747_107381);
    }

    function testFuzz_balanceWithYieldOf(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        uint112 principal = _setupAccount(alice, balanceWithYield, balance);
        (, uint240 expectedYield) = _getBalanceWithYield(balance, principal, currentIndex);

        assertEq(mYieldFee.balanceWithYieldOf(alice), balance + expectedYield);

        vm.assume(finalTimestamp > nextTimestamp);

        vm.warp(finalTimestamp);

        (, expectedYield) = _getBalanceWithYield(balance, principal, mYieldFee.currentIndex());
        assertEq(mYieldFee.balanceWithYieldOf(alice), balance + expectedYield);
    }

    /* ============ principalOf ============ */

    function test_principalOf() external {
        uint112 principal = 800e6;
        mYieldFee.setAccountOf(alice, 1_000e6, principal);

        assertEq(mYieldFee.principalOf(alice), principal);
    }

    /* ============ projectedTotalSupply ============ */

    function test_projectedTotalSupply() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        mYieldFee.setTotalPrincipal(1_000);
        mYieldFee.setTotalSupply(1_000);

        // Total supply + yield: 1_100
        // Yield fee: 20
        // Total supply + yield - yield fee: 1_080
        assertEq(mYieldFee.projectedTotalSupply(), 1_080);
    }

    /* ============ totalAccruedYield ============ */

    function test_totalAccruedYield() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        // 550 balance with yield without fee
        mYieldFee.setTotalSupply(500e6);
        mYieldFee.setTotalPrincipal(500e6);

        assertEq(mYieldFee.totalAccruedYield(), 39_615199); // Should be 40 but it rounds down

        // 1_100 balance with yield without fee.
        mYieldFee.setTotalSupply(1_000e6);
        mYieldFee.setTotalPrincipal(1_000e6);
        assertEq(mYieldFee.totalAccruedYield(), 79_230399); // Should be 80 but it rounds down

        // 8.5% M Yield Fee index growth
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldFee.currentIndex(), 1_164738254609);

        assertEq(mYieldFee.totalAccruedYield(), 164_738254); // Should be 168 if the index wasn't compounding

        // 1_885 balance with yield without fee
        mYieldFee.setTotalSupply(1_000e6);
        mYieldFee.setTotalPrincipal(1_500e6);

        // Present balance at fee-adjusted index (1_747) - balance (1_000)
        assertEq(mYieldFee.totalAccruedYield(), 747_107381);
    }

    function testFuzz_totalAccruedYield(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 totalSupplyWithYield,
        uint240 totalSupply,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (totalSupplyWithYield, totalSupply) = _getFuzzedBalances(
            currentIndex,
            totalSupplyWithYield,
            totalSupply,
            _getMaxAmount(currentIndex)
        );

        uint112 principal = _setupSupply(totalSupplyWithYield, totalSupply);
        (, uint240 expectedYield) = _getBalanceWithYield(totalSupply, principal, currentIndex);

        assertEq(mYieldFee.totalAccruedYield(), expectedYield);

        vm.assume(finalTimestamp > nextTimestamp);

        vm.warp(finalTimestamp);

        (, expectedYield) = _getBalanceWithYield(totalSupply, principal, mYieldFee.currentIndex());
        assertEq(mYieldFee.totalAccruedYield(), expectedYield);
    }

    /* ============ totalAccruedFee ============ */

    function test_totalAccruedFee() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        // 550 balance with yield without fee
        mYieldFee.setTotalSupply(500);
        mYieldFee.setTotalPrincipal(500);
        assertEq(mYieldFee.totalAccruedYield(), 39); // Should be 50 - 50 * 20% = 40 but it rounds down

        mToken.setBalanceOf(address(mYieldFee), 550);
        assertEq(mYieldFee.totalAccruedFee(), 10);
        assertEq(mYieldFee.totalAccruedYield() + mYieldFee.totalAccruedFee(), 49);

        // 1_100 balance with yield without fee.
        mYieldFee.setTotalSupply(1_000);
        mYieldFee.setTotalPrincipal(1_000);
        assertEq(mYieldFee.totalAccruedYield(), 79); // Should be 100 - 100 * 20% = 80 but it rounds down

        mToken.setBalanceOf(address(mYieldFee), 1_100);
        assertEq(mYieldFee.totalAccruedFee(), 20);
        assertEq(mYieldFee.totalAccruedYield() + mYieldFee.totalAccruedFee(), 99);

        // 8.5% M Yield Fee index growth
        vm.warp(startTimestamp + 30_057_038 * 2);
        assertEq(mYieldFee.currentIndex(), 1_164738254609);

        assertEq(mYieldFee.totalAccruedYield(), 164); // Should be 210 - 210 * 20% = 168 if the index wasn't compounding

        mToken.setBalanceOf(address(mYieldFee), 1_210);
        assertEq(mYieldFee.totalAccruedFee(), 45);
        assertEq(mYieldFee.totalAccruedYield() + mYieldFee.totalAccruedFee(), 209);

        // 1_885 balance with yield without fee
        mYieldFee.setTotalSupply(1_000);
        mYieldFee.setTotalPrincipal(1_500);

        // Present balance at fee-adjusted index (1_747) - balance (1_000)
        assertEq(mYieldFee.totalAccruedYield(), 747);

        mToken.setBalanceOf(address(mYieldFee), 1_885);
        assertEq(mYieldFee.totalAccruedFee(), 137);
        assertEq(mYieldFee.totalAccruedYield() + mYieldFee.totalAccruedFee(), 884);
    }

    function testFuzz_totalAccruedFee(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 totalSupplyWithYield,
        uint240 totalSupply,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (totalSupplyWithYield, totalSupply) = _getFuzzedBalances(
            currentIndex,
            totalSupplyWithYield,
            totalSupply,
            _getMaxAmount(currentIndex)
        );

        uint112 principal = _setupSupply(totalSupplyWithYield, totalSupply);
        (, uint240 expectedYield) = _getBalanceWithYield(totalSupply, principal, currentIndex);
        uint256 expectedFee = _getYieldFee(expectedYield, feeRate);

        mToken.setBalanceOf(address(mYieldFee), totalSupply + expectedYield + expectedFee);

        assertApproxEqAbs(mYieldFee.totalAccruedFee(), expectedFee, 9); // May round down in favor of the protocol

        vm.assume(finalTimestamp > nextTimestamp);

        vm.warp(finalTimestamp);

        (, expectedYield) = _getBalanceWithYield(totalSupply, principal, mYieldFee.currentIndex());
        expectedFee = _getYieldFee(expectedYield, feeRate);

        mToken.setBalanceOf(address(mYieldFee), totalSupply + expectedYield + expectedFee);

        assertApproxEqAbs(mYieldFee.totalAccruedFee(), expectedFee, 9);
    }

    /* ============ approve ============ */

    function test_approve_frozenAccount() public {
        vm.prank(freezeManager);
        mYieldFee.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(alice);
        mYieldFee.approve(bob, 1_000e6);
    }

    function test_approve_frozenSpender() public {
        vm.prank(freezeManager);
        mYieldFee.freeze(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));

        vm.prank(alice);
        mYieldFee.approve(bob, 1_000e6);
    }

    /* ============ wrap ============ */

    function test_wrap_paused() public {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(address(bob), amount);

        vm.prank(pauser);
        mYieldFee.pause();

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(swapFacility.msgSender.selector), abi.encode(bob));

        vm.prank(address(swapFacility));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mYieldFee.wrap(bob, 1);
    }

    function test_wrap_frozenAccount() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        vm.prank(freezeManager);
        mYieldFee.freeze(alice);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));

        vm.prank(address(swapFacility));
        mYieldFee.wrap(bob, amount);
    }

    function test_wrap_frozenRecipient() public {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(bob, amount);

        vm.prank(freezeManager);
        mYieldFee.freeze(bob);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(swapFacility.msgSender.selector), abi.encode(bob));

        vm.prank(address(swapFacility));
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));
        mYieldFee.wrap(bob, 1);
    }

    function test_wrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        mYieldFee.wrap(alice, 0);
    }

    function test_wrap_invalidRecipient() external {
        mToken.setBalanceOf(alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(address(swapFacility));
        mYieldFee.wrap(address(0), 1_000);
    }

    function test_wrap() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        mToken.setBalanceOf(address(swapFacility), 1_002);
        mToken.setBalanceOf(address(mYieldFee), 1_100);

        mYieldFee.setTotalPrincipal(1_000);
        mYieldFee.setTotalSupply(1_000);

        // Total supply + yield: 1_100
        // Alice balance with yield: 1_079
        // Fee: 20
        mYieldFee.setAccountOf(alice, 1_000, 1_000);

        assertEq(mYieldFee.principalOf(alice), 1_000);
        assertEq(mYieldFee.balanceOf(alice), 1_000);
        assertEq(mYieldFee.accruedYieldOf(alice), 79);
        assertEq(mYieldFee.balanceWithYieldOf(alice), 1_000 + 79);
        assertEq(mYieldFee.totalPrincipal(), 1_000);
        assertEq(mYieldFee.totalSupply(), 1_000);
        assertEq(mYieldFee.totalAccruedYield(), 79);
        assertEq(mYieldFee.projectedTotalSupply(), 1_080);
        assertEq(mToken.balanceOf(address(mYieldFee)), 1_100);
        assertEq(mYieldFee.totalAccruedFee(), 20);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 999);

        vm.prank(address(swapFacility));
        mYieldFee.wrap(alice, 999);

        // Balance round up in favor of user, but -1 taken out of yield
        assertEq(mYieldFee.principalOf(alice), 1_000 + 925);
        assertEq(mYieldFee.balanceOf(alice), 1_000 + 999);
        assertEq(mYieldFee.accruedYieldOf(alice), 78);
        assertEq(mYieldFee.balanceWithYieldOf(alice), 1_000 + 999 + 78);
        assertEq(mYieldFee.totalPrincipal(), 1_000 + 925);
        assertEq(mYieldFee.totalSupply(), 1_000 + 999);
        assertEq(mYieldFee.totalAccruedYield(), 78);
        assertEq(mYieldFee.projectedTotalSupply(), 2078);
        assertEq(mToken.balanceOf(address(mYieldFee)), 2_099);
        assertEq(mYieldFee.totalAccruedFee(), 21);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 1);

        vm.prank(address(swapFacility));
        mYieldFee.wrap(alice, 1);

        assertEq(mYieldFee.principalOf(alice), 1_000 + 925); // No change due to principal round down on wrap.
        assertEq(mYieldFee.balanceOf(alice), 1_000 + 999 + 1);
        assertEq(mYieldFee.accruedYieldOf(alice), 78 - 1);
        assertEq(mYieldFee.balanceWithYieldOf(alice), 1_000 + 999 + 78);
        assertEq(mYieldFee.totalPrincipal(), 1_000 + 925);
        assertEq(mYieldFee.totalSupply(), 1_000 + 999 + 1);
        assertEq(mYieldFee.totalAccruedYield(), 77);
        assertEq(mYieldFee.projectedTotalSupply(), 2_078);
        assertEq(mToken.balanceOf(address(mYieldFee)), 2_100);
        assertEq(mYieldFee.totalAccruedFee(), 22);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 2);

        vm.prank(address(swapFacility));
        mYieldFee.wrap(alice, 2);

        assertEq(mYieldFee.principalOf(alice), 1_000 + 926);
        assertEq(mYieldFee.balanceOf(alice), 1_000 + 999 + 1 + 2);
        assertEq(mYieldFee.balanceWithYieldOf(alice), 1_000 + 999 + 78 + 1);
        assertEq(mYieldFee.accruedYieldOf(alice), 78 - 1 - 1);
        assertEq(mYieldFee.totalPrincipal(), 1_000 + 926);
        assertEq(mYieldFee.totalSupply(), 1_000 + 999 + 1 + 2);
        assertEq(mYieldFee.totalAccruedYield(), 76);
        assertEq(mYieldFee.projectedTotalSupply(), 2_079);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(address(mYieldFee)), 2_099 + 1 + 2);
    }

    function testFuzz_wrap(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance,
        uint240 wrapAmount
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        _setupAccount(alice, balanceWithYield, balance);
        wrapAmount = uint240(bound(wrapAmount, 0, _getMaxAmount(currentIndex) - balanceWithYield));

        mToken.setBalanceOf(address(swapFacility), wrapAmount);

        if (wrapAmount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), alice, wrapAmount);
        }

        vm.prank(address(swapFacility));
        mYieldFee.wrap(alice, wrapAmount);

        if (wrapAmount == 0) return;

        balance += wrapAmount;

        // When wrapping, added principal for account is always rounded down in favor of the protocol.
        // So in our test we need to round down too to accurately calculate balanceWithYield.
        balanceWithYield = uint240(
            IndexingMath.getPresentAmountRoundedDown(
                IndexingMath.getPrincipalAmountRoundedDown(balanceWithYield, currentIndex) +
                    IndexingMath.getPrincipalAmountRoundedDown(wrapAmount, currentIndex),
                currentIndex
            )
        );

        uint256 aliceYield = balanceWithYield <= balance ? 0 : balanceWithYield - balance;
        uint256 yieldFee = _getYieldFee(aliceYield, feeRate);

        assertEq(mYieldFee.balanceOf(alice), balance);
        assertEq(mYieldFee.balanceOf(alice), mYieldFee.totalSupply());

        // Rounds down on wrap for alice and up for total principal.
        assertApproxEqAbs(mYieldFee.principalOf(alice), mYieldFee.totalPrincipal(), 1);

        assertEq(mYieldFee.balanceWithYieldOf(alice), balance + aliceYield);
        assertEq(mYieldFee.balanceWithYieldOf(alice), balance + mYieldFee.accruedYieldOf(alice));

        // Simulate M token balance.
        mToken.setBalanceOf(address(mYieldFee), balance + aliceYield + yieldFee);

        // May round down in favor of the protocol
        assertApproxEqAbs(mYieldFee.balanceWithYieldOf(alice), mYieldFee.projectedTotalSupply(), MAX_ROUNDING_DELTA);
        assertEq(mYieldFee.totalAccruedYield(), aliceYield);
        assertApproxEqAbs(mYieldFee.totalAccruedFee(), yieldFee, MAX_ROUNDING_DELTA);
    }

    /* ============ unwrap ============ */

    function test_unwrap_paused() public {
        mYieldFee.setAccountOf(address(alice), 1_000, 1_000);

        vm.prank(pauser);
        mYieldFee.pause();

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(swapFacility.msgSender.selector), abi.encode(alice));

        vm.prank(address(swapFacility));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mYieldFee.unwrap(alice, 1);
    }

    function test_unwrap_frozen() public {
        mYieldFee.setAccountOf(address(alice), 1_000, 1_000);

        vm.prank(freezeManager);
        mYieldFee.freeze(alice);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(swapFacility.msgSender.selector), abi.encode(alice));

        vm.prank(address(swapFacility));
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldFee.unwrap(alice, 1);
    }

    // function test_unwrap_insufficientAmount() external {
    //     vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
    //
    //     vm.prank(address(swapFacility));
    //     mYieldFee.unwrap(alice, 0);
    // }
    //
    // function test_unwrap_insufficientBalance() external {
    //     mYieldFee.setAccountOf(address(swapFacility), 999, 909);
    //
    //     vm.prank(alice);
    //     IERC20(address(mYieldFee)).approve(address(swapFacility), 1_000);
    //
    //     vm.expectRevert(
    //         abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, address(swapFacility), 999, 1_000)
    //     );
    //
    //     vm.prank(address(swapFacility));
    //     mYieldFee.unwrap(alice, 1_000);
    // }

    function test_unwrap() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        mToken.setBalanceOf(address(mYieldFee), 1_100);

        mYieldFee.setTotalPrincipal(1_000);
        mYieldFee.setTotalSupply(1_000);

        // Total supply + yield: 1_100
        // Alice balance with yield: 1_079
        // Fee: 21
        mYieldFee.setAccountOf(address(swapFacility), 1_000, 1_000); // 1_100 balance with yield without fee

        assertEq(mYieldFee.principalOf(address(swapFacility)), 1_000);
        assertEq(mYieldFee.balanceOf(address(swapFacility)), 1_000);
        assertEq(mYieldFee.accruedYieldOf(address(swapFacility)), 79);
        assertEq(mYieldFee.balanceWithYieldOf(address(swapFacility)), 1_000 + 79);
        assertEq(mYieldFee.totalPrincipal(), 1_000);
        assertEq(mYieldFee.totalSupply(), 1_000);
        assertEq(mYieldFee.totalAccruedYield(), 79);
        assertEq(mYieldFee.projectedTotalSupply(), 1_080);

        vm.prank(alice);
        mYieldFee.approve(address(swapFacility), 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 1);

        vm.prank(address(swapFacility));
        mYieldFee.unwrap(alice, 1);

        assertEq(mYieldFee.principalOf(address(swapFacility)), 1_000 - 1);
        assertEq(mYieldFee.balanceOf(address(swapFacility)), 1_000 - 1);
        assertEq(mYieldFee.accruedYieldOf(address(swapFacility)), 79);
        assertEq(mYieldFee.balanceWithYieldOf(address(swapFacility)), 1_000 + 79 - 1);
        assertEq(mYieldFee.totalPrincipal(), 999);
        assertEq(mYieldFee.totalSupply(), 1_000 - 1);
        assertEq(mYieldFee.totalAccruedYield(), 79);
        assertEq(mYieldFee.projectedTotalSupply(), 1_079);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 499);

        vm.prank(address(swapFacility));
        mYieldFee.unwrap(alice, 499);

        assertEq(mYieldFee.principalOf(address(swapFacility)), 1_000 - 1 - 463);
        assertEq(mYieldFee.balanceOf(address(swapFacility)), 1_000 - 1 - 499);
        assertEq(mYieldFee.accruedYieldOf(address(swapFacility)), 79 - 1);
        assertEq(mYieldFee.totalPrincipal(), 1_000 - 463 - 1);
        assertEq(mYieldFee.totalSupply(), 1_000 - 1 - 499);
        assertEq(mYieldFee.totalAccruedYield(), 78);
        assertEq(mYieldFee.projectedTotalSupply(), 1_080 - 499 - 2);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 500);

        vm.prank(address(swapFacility));
        mYieldFee.unwrap(alice, 500);

        assertEq(mYieldFee.principalOf(address(swapFacility)), 1_000 - 1 - 463 - 464); // 72
        assertEq(mYieldFee.balanceOf(address(swapFacility)), 1_000 - 1 - 499 - 500); // 0
        assertEq(mYieldFee.accruedYieldOf(address(swapFacility)), 77);
        assertEq(mYieldFee.totalPrincipal(), 1_000 - 464 - 463 - 1); // 72
        assertEq(mYieldFee.totalSupply(), 1_000 - 1 - 499 - 500); // 0
        assertEq(mYieldFee.totalAccruedYield(), 77);
        assertEq(mYieldFee.projectedTotalSupply(), 1_080 - 499 - 500 - 3);

        // M tokens are sent to SwapFacility and then forwarded to Alice
        assertEq(mToken.balanceOf(address(swapFacility)), 1000);
        assertEq(mToken.balanceOf(address(mYieldFee)), 100);
        assertEq(mToken.balanceOf(alice), 0);
    }

    function testFuzz_unwrap(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 balanceWithYield,
        uint240 balance,
        uint240 unwrapAmount
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (balanceWithYield, balance) = _getFuzzedBalances(
            currentIndex,
            balanceWithYield,
            balance,
            _getMaxAmount(currentIndex)
        );

        _setupAccount(address(swapFacility), balanceWithYield, balance);
        unwrapAmount = uint240(bound(unwrapAmount, 0, _getMaxAmount(currentIndex) - balanceWithYield));

        mToken.setBalanceOf(address(mYieldFee), balanceWithYield);

        vm.prank(alice);
        mYieldFee.approve(address(swapFacility), unwrapAmount);

        if (unwrapAmount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else if (unwrapAmount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMExtension.InsufficientBalance.selector,
                    address(swapFacility),
                    balance,
                    unwrapAmount
                )
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(swapFacility), address(0), unwrapAmount);
        }

        vm.prank(address(swapFacility));
        mYieldFee.unwrap(alice, unwrapAmount);

        if ((unwrapAmount == 0) || (unwrapAmount > balance)) return;

        balance -= unwrapAmount;

        uint112 balanceWithYieldPrincipal = IndexingMath.getPrincipalAmountRoundedDown(balanceWithYield, currentIndex);

        // When unwrapping, subtracted principal for account is always rounded up in favor of the protocol.
        // So in our test we need to round up too to accurately calculate balanceWithYield.
        balanceWithYield = uint240(
            IndexingMath.getPresentAmountRoundedDown(
                balanceWithYieldPrincipal -
                    UIntMath.min112(
                        IndexingMath.getPrincipalAmountRoundedUp(unwrapAmount, currentIndex),
                        balanceWithYieldPrincipal
                    ),
                currentIndex
            )
        );

        uint256 aliceYield = (balanceWithYield <= balance) ? 0 : balanceWithYield - balance;
        uint256 yieldFee = _getYieldFee(aliceYield, feeRate);

        assertEq(mYieldFee.balanceOf(address(swapFacility)), balance);
        assertEq(mYieldFee.balanceOf(address(swapFacility)), mYieldFee.totalSupply());

        // Rounds up on unwrap for alice and down for total principal.
        assertApproxEqAbs(mYieldFee.principalOf(address(swapFacility)), mYieldFee.totalPrincipal(), 1);

        assertEq(mYieldFee.balanceWithYieldOf(address(swapFacility)), balance + aliceYield);
        assertEq(
            mYieldFee.balanceWithYieldOf(address(swapFacility)),
            balance + mYieldFee.accruedYieldOf(address(swapFacility))
        );

        // Simulate M token balance.
        mToken.setBalanceOf(address(mYieldFee), balance + aliceYield + yieldFee);

        assertApproxEqAbs(
            mYieldFee.balanceWithYieldOf(address(swapFacility)),
            mYieldFee.projectedTotalSupply(),
            MAX_ROUNDING_DELTA
        );
        assertEq(mYieldFee.totalAccruedYield(), aliceYield);
        assertApproxEqAbs(mYieldFee.totalAccruedFee(), yieldFee, MAX_ROUNDING_DELTA);

        // M tokens are sent to SwapFacility and then forwarded to Alice
        assertEq(mToken.balanceOf(address(swapFacility)), unwrapAmount);
        assertEq(mToken.balanceOf(alice), 0);
    }

    /* ============ transfer ============ */

    function test_transfer_paused() public {
        mYieldFee.setAccountOf(alice, 1_000, 1_000);

        vm.prank(pauser);
        mYieldFee.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(alice);
        mYieldFee.transfer(bob, 1);
    }

    function test_transfer_frozen() public {
        vm.prank(freezeManager);
        mYieldFee.freeze(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldFee.transfer(bob, 1);
    }

    function test_transfer_invalidRecipient() external {
        mYieldFee.setAccountOf(alice, 1_000, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(alice);
        mYieldFee.transfer(address(0), 1_000);
    }

    function test_transfer_insufficientBalance_toSelf() external {
        mYieldFee.setAccountOf(alice, 999, 999);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 999, 1_000));

        vm.prank(alice);
        mYieldFee.transfer(alice, 1_000);
    }

    function test_transfer_insufficientBalance() external {
        mYieldFee.setAccountOf(alice, 999, 999);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 999, 1_000));

        vm.prank(alice);
        mYieldFee.transfer(bob, 1_000);
    }

    function test_transfer() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        mToken.setBalanceOf(alice, 1_002);
        mToken.setBalanceOf(address(mYieldFee), 1_500);

        mYieldFee.setTotalPrincipal(1_500);
        mYieldFee.setTotalSupply(1_500);

        // Total supply + yield: 1_100
        // Alice balance with yield: 1_079
        // Fee: 21
        mYieldFee.setAccountOf(alice, 1_000, 1_000);

        // Bob balance with yield: 539
        // Balance: 500
        // Yield: 50
        // Fee: 11
        mYieldFee.setAccountOf(bob, 500, 500);

        assertEq(mYieldFee.accruedYieldOf(alice), 79);
        assertEq(mYieldFee.accruedYieldOf(bob), 39);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, 500);

        vm.prank(alice);
        mYieldFee.transfer(bob, 500);

        assertEq(mYieldFee.principalOf(alice), 536);
        assertEq(mYieldFee.balanceOf(alice), 500);
        assertEq(mYieldFee.accruedYieldOf(alice), 78);

        assertEq(mYieldFee.principalOf(bob), 964);
        assertEq(mYieldFee.balanceOf(bob), 1_000);
        assertEq(mYieldFee.accruedYieldOf(bob), 40);

        assertEq(mYieldFee.totalSupply(), 1_500);

        // Principal is rounded up when adding and rounded down when subtracting.
        assertEq(mYieldFee.totalPrincipal(), 1_500);
        assertEq(mYieldFee.totalAccruedYield(), 79 + 39);
    }

    function test_transfer_toSelf() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        // 10% M token index growth, 7.9% M Yield Fee index growth because of the 20% fee.
        vm.warp(startTimestamp + 30_057_038);
        assertEq(mYieldFee.currentIndex(), 1_079230399224);

        mYieldFee.setTotalPrincipal(1_000);
        mYieldFee.setTotalSupply(1_000);
        mToken.setBalanceOf(address(mYieldFee), 1_125);

        // Total supply + yield: 1_125
        // Alice balance with yield: 1_100
        // Fee: 21
        mYieldFee.setAccountOf(alice, 1_000, 1_000);

        assertEq(mYieldFee.balanceOf(alice), 1_000);
        assertEq(mYieldFee.accruedYieldOf(alice), 79);

        vm.expectEmit();
        emit IERC20.Transfer(alice, alice, 500);

        vm.prank(alice);
        mYieldFee.transfer(alice, 500);

        assertEq(mYieldFee.principalOf(alice), 1_000);
        assertEq(mYieldFee.balanceOf(alice), 1_000);
        assertEq(mYieldFee.accruedYieldOf(alice), 79);

        assertEq(mYieldFee.totalPrincipal(), 1_000);
        assertEq(mYieldFee.totalSupply(), 1_000);
        assertEq(mYieldFee.totalAccruedYield(), 79);
        assertEq(mYieldFee.projectedTotalSupply(), 1_080);
    }

    function testFuzz_transfer(
        bool earningEnabled,
        uint16 feeRate,
        uint128 latestIndex,
        uint240 aliceBalanceWithYield,
        uint240 aliceBalance,
        uint240 bobBalanceWithYield,
        uint240 bobBalance,
        uint240 amount
    ) external {
        _setupYieldFeeRate(feeRate);

        uint128 currentIndex = _setupIndex(earningEnabled, latestIndex);
        (aliceBalanceWithYield, aliceBalance) = _getFuzzedBalances(
            currentIndex,
            aliceBalanceWithYield,
            aliceBalance,
            _getMaxAmount(currentIndex)
        );

        (bobBalanceWithYield, bobBalance) = _getFuzzedBalances(
            currentIndex,
            bobBalanceWithYield,
            bobBalance,
            _getMaxAmount(currentIndex) - aliceBalanceWithYield
        );

        _setupAccount(alice, aliceBalanceWithYield, aliceBalance);
        _setupAccount(bob, bobBalanceWithYield, bobBalance);

        amount = uint240(bound(amount, 0, _getMaxAmount(currentIndex) - bobBalanceWithYield));

        if (amount > aliceBalance) {
            vm.expectRevert(
                abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, aliceBalance, amount)
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(alice, bob, amount);
        }

        vm.prank(alice);
        mYieldFee.transfer(bob, amount);

        if (amount > aliceBalance) return;

        aliceBalance -= amount;
        bobBalance += amount;

        assertEq(mYieldFee.balanceOf(alice), aliceBalance);
        assertEq(mYieldFee.balanceOf(bob), bobBalance);
        assertEq(mYieldFee.totalSupply(), aliceBalance + bobBalance);
        assertEq(mYieldFee.totalSupply(), mYieldFee.balanceOf(alice) + mYieldFee.balanceOf(bob));

        uint112 aliceBalanceWithYieldPrincipal = IndexingMath.getPrincipalAmountRoundedDown(
            aliceBalanceWithYield,
            currentIndex
        );

        aliceBalanceWithYieldPrincipal =
            aliceBalanceWithYieldPrincipal -
            UIntMath.min112(
                IndexingMath.getPrincipalAmountRoundedUp(amount, currentIndex),
                aliceBalanceWithYieldPrincipal
            );

        // When subtracting, subtracted principal for account is always rounded up in favor of the protocol.
        // So in our test we need to round up too to accurately calculate aliceBalanceWithYield.
        aliceBalanceWithYield = uint240(
            IndexingMath.getPresentAmountRoundedDown(aliceBalanceWithYieldPrincipal, currentIndex)
        );

        uint112 bobBalanceWithYieldPrincipal = IndexingMath.getPrincipalAmountRoundedDown(
            bobBalanceWithYield,
            currentIndex
        ) + IndexingMath.getPrincipalAmountRoundedDown(amount, currentIndex);

        // When adding, added principal for account is always rounded down in favor of the protocol.
        // So in our test we need to round down too to accurately calculate bobBalanceWithYield.
        bobBalanceWithYield = uint240(
            IndexingMath.getPresentAmountRoundedDown(bobBalanceWithYieldPrincipal, currentIndex)
        );

        uint240 aliceYield = aliceBalanceWithYield <= aliceBalance ? 0 : aliceBalanceWithYield - aliceBalance;
        uint240 bobYield = bobBalanceWithYield <= bobBalance ? 0 : bobBalanceWithYield - bobBalance;
        uint256 yieldFee = _getYieldFee(aliceYield + bobYield, feeRate);

        assertEq(mYieldFee.balanceWithYieldOf(alice), aliceBalance + aliceYield);
        assertEq(mYieldFee.balanceWithYieldOf(alice), aliceBalance + mYieldFee.accruedYieldOf(alice));

        // Bob may gain more due to rounding.
        assertApproxEqAbs(mYieldFee.balanceWithYieldOf(bob), bobBalance + bobYield, 10);
        assertEq(mYieldFee.balanceWithYieldOf(bob), bobBalance + mYieldFee.accruedYieldOf(bob));

        // Principal added or removed from totalPrincipal is rounded up when adding and rounded down when subtracting.
        assertApproxEqAbs(mYieldFee.totalPrincipal(), aliceBalanceWithYieldPrincipal + bobBalanceWithYieldPrincipal, 2);
        assertApproxEqAbs(mYieldFee.totalPrincipal(), mYieldFee.principalOf(alice) + mYieldFee.principalOf(bob), 2);

        uint256 mBalance = aliceBalance + aliceYield + bobBalance + bobYield + yieldFee;

        // Simulate M token balance.
        mToken.setBalanceOf(address(mYieldFee), mBalance);

        // projectedTotalSupply rounds up in favor of the protocol
        assertApproxEqAbs(
            mYieldFee.projectedTotalSupply(),
            mYieldFee.balanceWithYieldOf(alice) + mYieldFee.balanceWithYieldOf(bob),
            MAX_ROUNDING_DELTA
        );

        assertApproxEqAbs(mYieldFee.totalAccruedFee(), yieldFee, MAX_ROUNDING_DELTA);
    }

    /* ============ currentIndex Utils ============ */

    function _getCurrentIndex(
        uint128 latestIndex,
        uint32 latestRate,
        uint40 latestUpdateTimestamp
    ) internal view returns (uint128) {
        return
            UIntMath.bound128(
                ContinuousIndexingMath.multiplyIndicesDown(
                    latestIndex,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(latestRate),
                        uint32(mYieldFee.latestEarnerRateAccrualTimestamp() - latestUpdateTimestamp)
                    )
                )
            );
    }

    /* ============ Fuzz Utils ============ */

    function _setupAccount(
        address account,
        uint240 balanceWithYield,
        uint240 balance
    ) internal returns (uint112 principal_) {
        principal_ = IndexingMath.getPrincipalAmountRoundedDown(balanceWithYield, mYieldFee.currentIndex());

        mYieldFee.setAccountOf(account, balance, principal_);
        mYieldFee.setTotalPrincipal(mYieldFee.totalPrincipal() + principal_);
        mYieldFee.setTotalSupply(mYieldFee.totalSupply() + balance);
    }

    function _setupSupply(uint240 totalSupplyWithYield, uint240 totalSupply) internal returns (uint112 principal_) {
        principal_ = IndexingMath.getPrincipalAmountRoundedDown(totalSupplyWithYield, mYieldFee.currentIndex());

        mYieldFee.setTotalPrincipal(mYieldFee.totalPrincipal() + principal_);
        mYieldFee.setTotalSupply(mYieldFee.totalSupply() + totalSupply);
    }

    function _setupYieldFeeRate(uint16 rate) internal returns (uint16) {
        rate = uint16(bound(rate, 0, ONE_HUNDRED_PERCENT));

        vm.prank(feeManager);
        mYieldFee.setFeeRate(rate);

        return rate;
    }

    function _setupLatestRate(uint32 rate) internal returns (uint32) {
        rate = uint32(bound(rate, 10, 10_000));
        mYieldFee.setLatestRate(rate);
        return rate;
    }

    function _setupLatestIndex(uint128 latestIndex) internal returns (uint128) {
        latestIndex = uint128(bound(latestIndex, EXP_SCALED_ONE, 10_000000000000));
        mYieldFee.setLatestIndex(latestIndex);
        return latestIndex;
    }

    function _setupIndex(bool earningEnabled, uint128 latestIndex) internal returns (uint128) {
        mYieldFee.setLatestIndex(bound(latestIndex, EXP_SCALED_ONE, 10_000000000000));

        if (earningEnabled) {
            mYieldFee.setIsEarningEnabled(true);
        } else {
            mYieldFee.setIsEarningEnabled(false);
        }

        return mYieldFee.currentIndex();
    }
}
