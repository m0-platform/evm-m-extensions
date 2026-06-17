// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { PausableUpgradeable } from "../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";
import { IERC20 } from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { SafeERC20 } from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Upgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { Proxy } from "../../lib/common/src/Proxy.sol";

import { UpgradeBase } from "../../script/upgrade/UpgradeBase.sol";

import { IFreezable } from "../../src/components/freezable/IFreezable.sol";
import { MYieldFee } from "../../src/projects/yieldToAllWithFee/MYieldFee.sol";
import { MYieldToOne } from "../../src/projects/yieldToOne/MYieldToOne.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

import { MYieldToOneHarness } from "../harness/MYieldToOneHarness.sol";
import { MYieldFeeHarness } from "../harness/MYieldFeeHarness.sol";
import { JMIExtensionHarness } from "../harness/JMIExtensionHarness.sol";

import { BaseIntegrationTest } from "../utils/BaseIntegrationTest.sol";

contract SwapFacilityIntegrationTest is BaseIntegrationTest, UpgradeBase {
    using SafeERC20 for IERC20;

    // Holds USDC, USDT and wM
    address constant USER = 0x77BAB32F75996de8075eBA62aEa7b1205cf7E004;
    address constant DAI_USER = 0x73781209F3B0f195D0D3fA9D6b95bB61c54c1ca6;
    address constant USDC_USER = 0x2d4d2A025b10C09BDbd794B4FCe4F7ea8C7d7bB4;
    address constant USDT_USER = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_751_329);

        super.setUp();

        mYieldToOne = MYieldToOneHarness(
            Upgrades.deployTransparentProxy(
                "MYieldToOneHarness.sol:MYieldToOneHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldToOneHarness.initialize.selector,
                    NAME,
                    SYMBOL,
                    yieldRecipient,
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    pauser,
                    allowlistAdmin
                ),
                mExtensionDeployOptions
            )
        );

        mYieldFee = MYieldFeeHarness(
            Upgrades.deployTransparentProxy(
                "MYieldFeeHarness.sol:MYieldFeeHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    NAME,
                    SYMBOL,
                    1_000, // 10% fee
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

        jmiExtension = JMIExtensionHarness(
            Upgrades.deployTransparentProxy(
                "JMIExtensionHarness.sol:JMIExtensionHarness",
                admin,
                abi.encodeWithSelector(
                    JMIExtensionHarness.initialize.selector,
                    NAME,
                    SYMBOL,
                    yieldRecipient,
                    admin,
                    assetCapManager,
                    freezeManager,
                    pauser,
                    yieldRecipientManager,
                    allowlistAdmin
                ),
                mExtensionDeployOptions
            )
        );

        _addToList(EARNERS_LIST, address(mYieldToOne));
        _addToList(EARNERS_LIST, address(mYieldFee));
        _addToList(EARNERS_LIST, address(jmiExtension));

        vm.startPrank(assetCapManager);

        jmiExtension.setAssetCap(USDC, 1_000_000_000e6); // 1B USDC cap
        jmiExtension.setAssetCap(DAI, 1_000_000_000e18); // 1B DAI cap
        jmiExtension.setAssetCap(USDT, 28_000_000_000e6); // 28B USDT cap

        vm.stopPrank();

        vm.prank(admin);
        swapFacility.grantRole(M_SWAPPER_ROLE, USER);
    }

    /* ============ swap ============ */

    function test_swap_mYieldToOne_to_wrappedM() public {
        uint256 amount = 1_000_000;
        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);

        mYieldToOne.approve(address(swapFacility), amount);
        swapFacility.swap(address(mYieldToOne), WRAPPED_M, amount, USER);

        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        assertApproxEqAbs(wrappedMBalanceAfter, wrappedMBalanceBefore + amount, 2); // WrappedM V1 rounding error
        assertEq(mYieldToOne.balanceOf(USER), 0);
    }

    function test_swap_mYieldToOne_to_mYieldFee() public {
        uint256 amount = 1_000_000;
        uint256 mYieldFeeBalanceBefore = IERC20(address(mYieldFee)).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);

        mYieldToOne.approve(address(swapFacility), amount);
        swapFacility.swap(address(mYieldToOne), address(mYieldFee), amount, USER);

        uint256 mYieldFeeBalanceAfter = IERC20(address(mYieldFee)).balanceOf(USER);

        assertEq(mYieldFeeBalanceAfter, mYieldFeeBalanceBefore + amount); // precise swaps
        assertEq(mYieldToOne.balanceOf(USER), 0);
    }

    function test_swap_wrappedM_to_mYieldToOne_entireBalance() public {
        uint256 amount = IERC20(WRAPPED_M).balanceOf(USER);

        assertEq(mYieldToOne.balanceOf(USER), 0);

        vm.startPrank(USER);
        IERC20(WRAPPED_M).approve(address(swapFacility), amount);
        swapFacility.swap(WRAPPED_M, address(mYieldToOne), amount, USER);

        assertApproxEqAbs(IERC20(address(mYieldToOne)).balanceOf(USER), amount, 2); // WrappedM V1 rounding error
        assertEq(IERC20(WRAPPED_M).balanceOf(USER), 0);
    }

    function test_swap_mYieldToOne_to_wrappedM_entireBalance() public {
        uint256 amount = IERC20(address(mToken)).balanceOf(USER);
        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);

        mYieldToOne.approve(address(swapFacility), amount);
        swapFacility.swap(address(mYieldToOne), WRAPPED_M, amount, USER);

        assertEq(IERC20(address(mYieldToOne)).balanceOf(USER), 0);
        assertApproxEqAbs(IERC20(WRAPPED_M).balanceOf(USER), wrappedMBalanceBefore + amount, 2); // WrappedM V1 rounding error
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_swap_mYieldToOne_to_wrappedM(uint256 amount) public {
        // Ensure the amount is not zero, above 1 to account for possible rounding, and does not exceed the user's balance
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(address(mToken)).balanceOf(mSource));

        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        _giveM(USER, amount);
        vm.startPrank(USER);

        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);

        mYieldToOne.approve(address(swapFacility), amount);
        swapFacility.swap(address(mYieldToOne), WRAPPED_M, amount, USER);

        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        assertApproxEqAbs(wrappedMBalanceAfter, wrappedMBalanceBefore + amount, 2); // WrappedM V1 rounding error
        assertEq(mYieldToOne.balanceOf(USER), 0);
    }

    function test_swap_wrappedM_to_mYieldToOne_frozenAccount() public {
        uint256 amount = 1_000_000;

        vm.prank(freezeManager);
        mYieldToOne.freeze(USER);

        vm.startPrank(USER);
        IERC20(WRAPPED_M).approve(address(swapFacility), amount);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, USER));
        swapFacility.swap(WRAPPED_M, address(mYieldToOne), amount, USER);
    }

    function test_swapWithPermit_vrs() public {
        uint256 amount = 1_000_000;

        // Transfer $M to Alice
        vm.prank(USER);
        IERC20(address(mToken)).transfer(alice, amount);

        // Swap $M to mYieldToOne
        vm.startPrank(alice);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, alice);

        assertEq(mYieldToOne.balanceOf(alice), amount);
        assertEq(IERC20(WRAPPED_M).balanceOf(alice), 0);

        (uint8 v, bytes32 r, bytes32 s) = _getExtensionPermit(
            address(mYieldToOne),
            address(swapFacility),
            alice,
            aliceKey,
            amount,
            0,
            block.timestamp
        );

        // Swap mYieldToOne to Wrapped M
        swapFacility.swapWithPermit(address(mYieldToOne), WRAPPED_M, amount, alice, block.timestamp, v, r, s);

        assertApproxEqAbs(IERC20(WRAPPED_M).balanceOf(alice), amount, 2);
        assertEq(mYieldToOne.balanceOf(alice), 0);
    }

    /* ============ swapInM ============ */

    function test_swapInM() public {
        uint256 amount = 1_000_000;

        assertEq(mYieldToOne.balanceOf(USER), 0);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);
    }

    function test_swapInM_wrappedM() public {
        uint256 amount = 1_000_000;

        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), WRAPPED_M, amount, USER);

        assertApproxEqAbs(wrappedM.balanceOf(USER) - wrappedMBalanceBefore, amount, 2); // WrappedM V1 rounding error
    }

    function test_swapInM_jmiExtension_paused() public {
        uint256 amount = 1_000_000;

        vm.prank(pauser);
        jmiExtension.pause();

        vm.startPrank(USER);

        IERC20(address(mToken)).approve(address(swapFacility), amount);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        swapFacility.swap(address(mToken), address(jmiExtension), amount, USER);

        vm.stopPrank();
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_swapInM(uint256 amount) public {
        // Ensure the amount is not zero and does not exceed the source balance
        vm.assume(amount > 0);
        vm.assume(amount <= IERC20(address(mToken)).balanceOf(mSource));

        _giveM(USER, amount);

        assertEq(mYieldToOne.balanceOf(USER), 0);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);
    }

    function test_swapInMWithPermit_vrs() public {
        uint256 amount = 1_000_000;

        vm.prank(USER);
        IERC20(address(mToken)).transfer(alice, amount);

        assertEq(mYieldToOne.balanceOf(alice), 0);
        assertEq(IERC20(address(mToken)).balanceOf(alice), amount);

        (uint8 v, bytes32 r, bytes32 s) = _getMPermit(
            address(swapFacility),
            alice,
            aliceKey,
            amount,
            0,
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.swapWithPermit(address(mToken), address(mYieldToOne), amount, alice, block.timestamp, v, r, s);

        assertEq(mYieldToOne.balanceOf(alice), amount);
    }

    function test_swapInMWithPermit_signature() public {
        uint256 amount = 1_000_000;

        vm.prank(USER);
        IERC20(address(mToken)).transfer(alice, amount);

        assertEq(mYieldToOne.balanceOf(alice), 0);
        assertEq(IERC20(address(mToken)).balanceOf(alice), amount);

        (uint8 v, bytes32 r, bytes32 s) = _getMPermit(
            address(swapFacility),
            alice,
            aliceKey,
            amount,
            0,
            block.timestamp
        );

        vm.prank(alice);
        swapFacility.swapWithPermit(
            address(mToken),
            address(mYieldToOne),
            amount,
            alice,
            block.timestamp,
            abi.encodePacked(r, s, v)
        );

        assertEq(mYieldToOne.balanceOf(alice), amount);
    }

    /* ============ swapOutM ============ */

    function test_swapOutM() public {
        uint256 amount = 1_000_000;

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);

        uint256 mBalanceBefore = IERC20(address(mToken)).balanceOf(USER);

        mYieldToOne.approve(address(swapFacility), amount);
        swapFacility.swap(address(mYieldToOne), address(mToken), amount, USER);

        uint256 mBalanceAfter = IERC20(address(mToken)).balanceOf(USER);

        assertEq(mYieldToOne.balanceOf(USER), 0);
        assertEq(mBalanceAfter - mBalanceBefore, amount);
    }

    function test_swapOutM_wrappedM() public {
        uint256 amount = 1_000_000;

        assertTrue(wrappedM.balanceOf(USER) >= amount, "Insufficient Wrapped M balance");

        uint256 mBalanceBefore = IERC20(address(mToken)).balanceOf(USER);

        vm.startPrank(USER);

        wrappedM.approve(address(swapFacility), amount);
        swapFacility.swap(address(wrappedM), address(mToken), amount, USER);

        uint256 mBalanceAfter = IERC20(address(mToken)).balanceOf(USER);

        assertApproxEqAbs(mBalanceAfter - mBalanceBefore, amount, 2); // WrappedM V1 rounding error
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_swapOutM(uint256 amount) public {
        // Ensure the amount is not zero and does not exceed the source balance
        vm.assume(amount > 0);
        vm.assume(amount <= IERC20(address(mToken)).balanceOf(mSource));

        _giveM(USER, amount);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);

        uint256 mBalanceBefore = IERC20(address(mToken)).balanceOf(USER);

        mYieldToOne.approve(address(swapFacility), amount);
        swapFacility.swap(address(mYieldToOne), address(mToken), amount, USER);

        uint256 mBalanceAfter = IERC20(address(mToken)).balanceOf(USER);

        assertEq(mYieldToOne.balanceOf(USER), 0);
        assertEq(mBalanceAfter - mBalanceBefore, amount);
    }

    function test_swapOutMWithPermit_vrs() public {
        uint256 amount = 1_000_000;

        // Transfer $M to Alice
        vm.prank(USER);
        IERC20(address(mToken)).transfer(alice, amount);

        // Swap $M to mYieldToOne
        vm.startPrank(alice);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, alice);

        assertEq(mYieldToOne.balanceOf(alice), amount);
        assertEq(IERC20(address(mToken)).balanceOf(alice), 0);

        (uint8 v, bytes32 r, bytes32 s) = _getExtensionPermit(
            address(mYieldToOne),
            address(swapFacility),
            alice,
            aliceKey,
            amount,
            0,
            block.timestamp
        );

        // Swap mYieldToOne to M
        swapFacility.swapWithPermit(address(mYieldToOne), address(mToken), amount, alice, block.timestamp, v, r, s);

        assertEq(IERC20(address(mToken)).balanceOf(alice), amount);
        assertEq(mYieldToOne.balanceOf(alice), 0);
    }

    /* ============ JMI Extension Swap Tests ============ */

    function test_swap_usdc_to_jmiExtension() public {
        uint256 amount = 1_000_000e6; // 1M USDC (6 decimals)

        assertEq(jmiExtension.balanceOf(USDC_USER), 0);

        vm.startPrank(USDC_USER);

        IERC20(USDC).approve(address(swapFacility), amount);
        swapFacility.swap(USDC, address(jmiExtension), amount, USDC_USER);

        vm.stopPrank();

        assertEq(jmiExtension.balanceOf(USDC_USER), amount);
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_swap_usdc_to_jmiExtension(uint256 amount) public {
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(USDC).balanceOf(USDC_USER));

        assertEq(jmiExtension.balanceOf(USDC_USER), 0);

        vm.startPrank(USDC_USER);

        IERC20(USDC).approve(address(swapFacility), amount);
        swapFacility.swap(USDC, address(jmiExtension), amount, USDC_USER);

        vm.stopPrank();

        assertEq(jmiExtension.balanceOf(USDC_USER), amount);
    }

    function test_swap_dai_to_jmiExtension() public {
        uint256 amount = 1_000_000e18; // 1M DAI

        assertEq(jmiExtension.balanceOf(DAI_USER), 0);

        vm.startPrank(DAI_USER);

        IERC20(DAI).approve(address(swapFacility), amount);
        swapFacility.swap(DAI, address(jmiExtension), amount, DAI_USER);

        vm.stopPrank();

        // DAI has 18 decimals, JMI has 6, so amount gets scaled down
        assertEq(jmiExtension.balanceOf(DAI_USER), amount / 1e12);
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_swap_dai_to_jmiExtension(uint256 amount) public {
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(DAI).balanceOf(DAI_USER));

        assertEq(jmiExtension.balanceOf(DAI_USER), 0);

        uint256 expectedJmiAmount = amount / 1e12;

        vm.startPrank(DAI_USER);

        IERC20(DAI).approve(address(swapFacility), amount);

        if (expectedJmiAmount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        }

        swapFacility.swap(DAI, address(jmiExtension), amount, DAI_USER);

        vm.stopPrank();

        // DAI has 18 decimals, JMI has 6, so amount gets scaled down
        assertEq(jmiExtension.balanceOf(DAI_USER), expectedJmiAmount);
    }

    function test_swap_mYieldToOne_to_jmiExtension() public {
        uint256 amount = 1_000_000;

        vm.startPrank(USER);

        // First swap M to mYieldToOne
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);
        assertEq(jmiExtension.balanceOf(USER), 0);

        // Swap mYieldToOne to jmiExtension
        mYieldToOne.approve(address(swapFacility), amount);
        swapFacility.swap(address(mYieldToOne), address(jmiExtension), amount, USER);

        vm.stopPrank();

        assertEq(mYieldToOne.balanceOf(USER), 0);
        assertEq(jmiExtension.balanceOf(USER), amount);
    }

    function test_swap_usdt_to_jmiExtension() public {
        uint256 amount = 1_000_000e6; // 1M USDT (6 decimals)

        assertEq(jmiExtension.balanceOf(USDT_USER), 0);

        vm.startPrank(USDT_USER);

        IERC20(USDT).forceApprove(address(swapFacility), amount);
        swapFacility.swap(USDT, address(jmiExtension), amount, USDT_USER);

        vm.stopPrank();

        assertEq(jmiExtension.balanceOf(USDT_USER), amount);
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_swap_usdt_to_jmiExtension(uint256 amount) public {
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(USDT).balanceOf(USDT_USER));

        assertEq(jmiExtension.balanceOf(USDT_USER), 0);

        vm.startPrank(USDT_USER);

        IERC20(USDT).forceApprove(address(swapFacility), amount);
        swapFacility.swap(USDT, address(jmiExtension), amount, USDT_USER);

        vm.stopPrank();

        assertEq(jmiExtension.balanceOf(USDT_USER), amount);
    }

    function test_swap_jmiExtension_to_mYieldToOne() public {
        uint256 amount = 1_000_000;

        vm.startPrank(USER);

        // First swap M to jmiExtension
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(jmiExtension), amount, USER);

        assertEq(jmiExtension.balanceOf(USER), amount);
        assertEq(mYieldToOne.balanceOf(USER), 0);

        // Swap jmiExtension to mYieldToOne
        jmiExtension.approve(address(swapFacility), amount);
        swapFacility.swap(address(jmiExtension), address(mYieldToOne), amount, USER);

        vm.stopPrank();

        assertEq(jmiExtension.balanceOf(USER), 0);
        assertEq(mYieldToOne.balanceOf(USER), amount);
    }

    function test_swap_wrappedM_to_jmiExtension() public {
        uint256 amount = 1_000_000;

        uint256 wrappedMBalance = IERC20(WRAPPED_M).balanceOf(USER);
        assertTrue(wrappedMBalance >= amount, "Insufficient WrappedM balance");

        assertEq(jmiExtension.balanceOf(USER), 0);

        vm.startPrank(USER);

        IERC20(WRAPPED_M).approve(address(swapFacility), amount);
        swapFacility.swap(WRAPPED_M, address(jmiExtension), amount, USER);

        vm.stopPrank();

        assertApproxEqAbs(jmiExtension.balanceOf(USER), amount, 1); // WrappedM V1 rounding error
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_swap_wrappedM_to_jmiExtension(uint256 amount) public {
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(WRAPPED_M).balanceOf(USER));

        assertEq(jmiExtension.balanceOf(USER), 0);

        vm.startPrank(USER);

        IERC20(WRAPPED_M).approve(address(swapFacility), amount);
        swapFacility.swap(WRAPPED_M, address(jmiExtension), amount, USER);

        vm.stopPrank();

        assertApproxEqAbs(jmiExtension.balanceOf(USER), amount, 2); // WrappedM V1 rounding error
    }

    function test_swap_jmiExtension_to_wrappedM() public {
        uint256 amount = 1_000_000;

        vm.startPrank(USER);

        // First swap M to jmiExtension
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(jmiExtension), amount, USER);

        assertEq(jmiExtension.balanceOf(USER), amount);

        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        // Swap jmiExtension to WrappedM
        jmiExtension.approve(address(swapFacility), amount);
        swapFacility.swap(address(jmiExtension), WRAPPED_M, amount, USER);

        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        vm.stopPrank();

        assertEq(jmiExtension.balanceOf(USER), 0);
        assertApproxEqAbs(wrappedMBalanceAfter - wrappedMBalanceBefore, amount, 1); // WrappedM V1 rounding error
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_swap_jmiExtension_to_wrappedM(uint256 amount) public {
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(address(mToken)).balanceOf(mSource));

        _giveM(USER, amount);

        vm.startPrank(USER);

        // First swap M to jmiExtension
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(jmiExtension), amount, USER);

        assertEq(jmiExtension.balanceOf(USER), amount);

        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        // Swap jmiExtension to WrappedM
        jmiExtension.approve(address(swapFacility), amount);
        swapFacility.swap(address(jmiExtension), WRAPPED_M, amount, USER);

        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        vm.stopPrank();

        assertEq(jmiExtension.balanceOf(USER), 0);
        assertApproxEqAbs(wrappedMBalanceAfter - wrappedMBalanceBefore, amount, 1); // WrappedM V1 rounding error
    }

    /* ============ JMIExtension replaceAssetWithM tests ============ */

    function test_replaceAssetWithM() public {
        uint256 amount = 1_000_000;

        vm.prank(USER);
        IERC20(address(mToken)).transfer(alice, amount * 2);

        vm.prank(USER);
        IERC20(USDC).transfer(alice, amount);

        vm.startPrank(alice);

        // Alice swaps M for mYieldToOne
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, alice);

        assertEq(mYieldToOne.balanceOf(alice), amount);
        assertEq(IERC20(USDC).balanceOf(alice), amount);

        // Alice swaps USDC for JMI Extension
        IERC20(USDC).approve(address(swapFacility), amount);
        swapFacility.swap(USDC, address(jmiExtension), amount, alice);

        assertEq(jmiExtension.balanceOf(alice), amount);
        assertEq(IERC20(USDC).balanceOf(alice), 0);

        // Approve mYieldToOne tokens to swapFacility
        mYieldToOne.approve(address(swapFacility), amount);

        // Replace USDC with M in JMI Extension
        swapFacility.replaceAssetWithM(USDC, address(mYieldToOne), address(jmiExtension), amount, alice);

        vm.stopPrank();

        assertEq(mYieldToOne.balanceOf(alice), 0);
        assertEq(IERC20(USDC).balanceOf(alice), amount);
        assertEq(jmiExtension.balanceOf(alice), amount);

        assertEq(IERC20(USDC).balanceOf(address(jmiExtension)), 0);
        assertEq(IERC20(address(mToken)).balanceOf(address(jmiExtension)), amount);
    }

    function test_replaceAssetWithMWithPermit_vrs() public {
        uint256 amount = 1_000_000;

        vm.prank(USER);
        IERC20(address(mToken)).transfer(alice, amount * 2);

        vm.prank(USER);
        IERC20(USDC).transfer(alice, amount);

        vm.startPrank(alice);

        // Alice swaps M for mYieldToOne
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, alice);

        assertEq(mYieldToOne.balanceOf(alice), amount);
        assertEq(IERC20(USDC).balanceOf(alice), amount);

        // Alice swaps USDC for jmiExtension
        IERC20(USDC).approve(address(swapFacility), amount);
        swapFacility.swap(USDC, address(jmiExtension), amount, alice);

        assertEq(jmiExtension.balanceOf(alice), amount);
        assertEq(IERC20(USDC).balanceOf(alice), 0);

        // Get permit signature for mYieldToOne
        (uint8 v, bytes32 r, bytes32 s) = _getExtensionPermit(
            address(mYieldToOne),
            address(swapFacility),
            alice,
            aliceKey,
            amount,
            0,
            block.timestamp
        );

        // Replace USDC with M in JMI Extension using permit
        swapFacility.replaceAssetWithMWithPermit(
            USDC,
            address(mYieldToOne),
            address(jmiExtension),
            amount,
            alice,
            block.timestamp,
            v,
            r,
            s
        );

        vm.stopPrank();

        assertEq(mYieldToOne.balanceOf(alice), 0);
        assertEq(IERC20(USDC).balanceOf(alice), amount);
        assertEq(jmiExtension.balanceOf(alice), amount);

        assertEq(IERC20(USDC).balanceOf(address(jmiExtension)), 0);
        assertEq(IERC20(address(mToken)).balanceOf(address(jmiExtension)), amount);
    }

    function test_replaceAssetWithMWithPermit_signature() public {
        uint256 amount = 1_000_000;

        vm.prank(USER);
        IERC20(address(mToken)).transfer(alice, amount * 2);

        vm.prank(USER);
        IERC20(USDC).transfer(alice, amount);

        // Alice swaps M for mYieldToOne
        vm.startPrank(alice);

        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, alice);

        assertEq(mYieldToOne.balanceOf(alice), amount);
        assertEq(IERC20(USDC).balanceOf(alice), amount);

        // Alice swaps USDC for JMI Extension
        IERC20(USDC).approve(address(swapFacility), amount);
        swapFacility.swap(USDC, address(jmiExtension), amount, alice);

        assertEq(jmiExtension.balanceOf(alice), amount);
        assertEq(IERC20(USDC).balanceOf(alice), 0);

        // Get permit signature for mYieldToOne
        (uint8 v, bytes32 r, bytes32 s) = _getExtensionPermit(
            address(mYieldToOne),
            address(swapFacility),
            alice,
            aliceKey,
            amount,
            0,
            block.timestamp
        );

        // Replace USDC with M in JMI Extension using permit with signature bytes
        swapFacility.replaceAssetWithMWithPermit(
            USDC,
            address(mYieldToOne),
            address(jmiExtension),
            amount,
            alice,
            block.timestamp,
            abi.encodePacked(r, s, v)
        );

        vm.stopPrank();

        assertEq(mYieldToOne.balanceOf(alice), 0);
        assertEq(IERC20(USDC).balanceOf(alice), amount);
        assertEq(jmiExtension.balanceOf(alice), amount);

        assertEq(IERC20(USDC).balanceOf(address(jmiExtension)), 0);
        assertEq(IERC20(address(mToken)).balanceOf(address(jmiExtension)), amount);
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_replaceAssetWithM(uint256 amount) public {
        // Ensure the amount is not zero, above 1 to account for possible rounding, and does not exceed available balances
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(address(mToken)).balanceOf(mSource) / 2); // Divide by 2 since we need 2x amount
        vm.assume(amount <= IERC20(USDC).balanceOf(USDC_USER));

        // Give alice 2x amount of M tokens and amount of USDC
        _giveM(alice, amount * 2);

        vm.prank(USDC_USER);
        IERC20(USDC).transfer(alice, amount);

        vm.startPrank(alice);

        // Alice swaps M for mYieldToOne
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, alice);

        assertEq(mYieldToOne.balanceOf(alice), amount);
        assertEq(IERC20(USDC).balanceOf(alice), amount);

        // Alice swaps USDC for JMI Extension
        IERC20(USDC).approve(address(swapFacility), amount);
        swapFacility.swap(USDC, address(jmiExtension), amount, alice);

        assertEq(jmiExtension.balanceOf(alice), amount);
        assertEq(IERC20(USDC).balanceOf(alice), 0);

        // Approve mYieldToOne tokens to swapFacility
        mYieldToOne.approve(address(swapFacility), amount);

        // Replace USDC with M in JMI Extension
        swapFacility.replaceAssetWithM(USDC, address(mYieldToOne), address(jmiExtension), amount, alice);

        vm.stopPrank();

        assertEq(mYieldToOne.balanceOf(alice), 0);
        assertEq(IERC20(USDC).balanceOf(alice), amount);
        assertEq(jmiExtension.balanceOf(alice), amount);

        assertEq(IERC20(USDC).balanceOf(address(jmiExtension)), 0);
        assertEq(IERC20(address(mToken)).balanceOf(address(jmiExtension)), amount);
    }

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_replaceAssetWithM_moreDecimals(uint256 amount) public {
        // amount is in JMI Extension decimals (6 decimals), same as M
        // For DAI, we need to scale up by 1e12 to get 18 decimals
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(address(mToken)).balanceOf(mSource) / 2); // Divide by 2 since we need 2x amount
        vm.assume(amount <= IERC20(DAI).balanceOf(DAI_USER) / 1e12);

        uint256 daiAmount = amount * 1e12; // Scale up to DAI's 18 decimals

        // Give alice 2x amount of M tokens and daiAmount of DAI
        _giveM(alice, amount * 2);

        vm.prank(DAI_USER);
        IERC20(DAI).transfer(alice, daiAmount);

        vm.startPrank(alice);

        // Alice swaps M for mYieldToOne
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swap(address(mToken), address(mYieldToOne), amount, alice);

        assertEq(mYieldToOne.balanceOf(alice), amount);
        assertEq(IERC20(DAI).balanceOf(alice), daiAmount);

        // Alice swaps DAI for JMI Extension
        IERC20(DAI).approve(address(swapFacility), daiAmount);
        swapFacility.swap(DAI, address(jmiExtension), daiAmount, alice);

        assertEq(jmiExtension.balanceOf(alice), amount);
        assertEq(IERC20(DAI).balanceOf(alice), 0);

        // Approve mYieldToOne tokens to swapFacility
        mYieldToOne.approve(address(swapFacility), amount);

        // Replace DAI with M in JMI Extension
        swapFacility.replaceAssetWithM(DAI, address(mYieldToOne), address(jmiExtension), amount, alice);

        vm.stopPrank();

        assertEq(mYieldToOne.balanceOf(alice), 0);
        assertEq(IERC20(DAI).balanceOf(alice), daiAmount);
        assertEq(jmiExtension.balanceOf(alice), amount);

        assertEq(IERC20(DAI).balanceOf(address(jmiExtension)), 0);
        assertEq(IERC20(address(mToken)).balanceOf(address(jmiExtension)), amount);
    }

    /* ============  SwapFacility Upgrade ============ */

    function test_upgradeSwapFacilityV2() public {
        vm.rollFork(23_828_680); // Block number after SwapFacility deployment

        Deployments memory deployments = _readDeployment(block.chainid);
        SwapFacility swapFacilityProxy = SwapFacility(deployments.swapFacility);

        vm.expectRevert();

        vm.prank(pauser);
        swapFacilityProxy.pause();

        vm.startPrank(proxyAdmin);

        _upgradeSwapFacility(address(swapFacilityProxy), pauser);

        vm.stopPrank();

        assertTrue(swapFacilityProxy.hasRole(PAUSER_ROLE, pauser));

        vm.prank(pauser);
        swapFacilityProxy.pause();

        assertTrue(swapFacilityProxy.paused());
    }
}
