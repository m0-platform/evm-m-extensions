// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IAccessControl } from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Upgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMTokenLike } from "../../src/interfaces/IMTokenLike.sol";

import { MYieldToOneHarness } from "../harness/MYieldToOneHarness.sol";

import { BaseIntegrationTest } from "../utils/BaseIntegrationTest.sol";

contract MYieldToOneIntegrationTests is BaseIntegrationTest {
    uint256 public mainnetFork;

    function setUp() public override {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_482_175);

        super.setUp();

        _fundAccounts();

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

        vm.prank(admin);
        mYieldToOne.setContractKey(
            sbytes32(bytes32(uint256(0xC0FFEE))),
            hex"02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        );
    }

    function test_integration_constants() external view {
        // Check the contract's name, symbol, and decimals
        assertEq(mYieldToOne.name(), NAME);
        assertEq(mYieldToOne.symbol(), SYMBOL);
        assertEq(mYieldToOne.decimals(), 6);

        // Check the initial state of the contract
        assertEq(mYieldToOne.mToken(), address(mToken));
        assertEq(mYieldToOne.swapFacility(), address(swapFacility));
        assertEq(mYieldToOne.yieldRecipient(), yieldRecipient);

        assertTrue(mYieldToOne.hasRole(PAUSER_ROLE, pauser));
        assertTrue(mYieldToOne.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldToOne.hasRole(FREEZE_MANAGER_ROLE, freezeManager));
        assertTrue(mYieldToOne.hasRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager));
        assertTrue(mYieldToOne.hasRole(FREEZE_MANAGER_ROLE, freezeManager));
    }

    function test_yieldAccumulationAndClaim() external {
        uint256 amount = 10e6;

        // Enable earning for the contract
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        // Check the initial earning state
        assertEq(mToken.isEarning(address(mYieldToOne)), true);

        vm.warp(vm.getBlockTimestamp() + 1 days);

        // wrap from non-earner account
        _swapInM(address(mYieldToOne), alice, alice, amount);

        // Check balances of MYieldToOne and Alice after wrapping
        assertEq(mYieldToOne.getBalanceOf(alice), amount); // user receives exact amount
        assertApproxEqAbs(mToken.balanceOf(address(mYieldToOne)), amount, 2); // rounds down

        // Fast forward 10 days in the future to generate yield
        vm.warp(vm.getBlockTimestamp() + 10 days);

        // yield accrual
        assertEq(mYieldToOne.yield(), 11375);

        // transfers do not affect yield
        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount / 2));

        assertEq(mYieldToOne.getBalanceOf(bob), amount / 2);
        assertEq(mYieldToOne.getBalanceOf(alice), amount / 2);

        // yield stays the same
        assertEq(mYieldToOne.yield(), 11375);

        // unwraps
        _swapMOut(address(mYieldToOne), alice, alice, amount / 2);

        // alice receives exact amount but mYieldToOne loses 1 wei
        // due to rounding up in M when transferring from an earner to a non-earner
        assertEq(mYieldToOne.yield(), 11374);

        _swapMOut(address(mYieldToOne), bob, bob, amount / 2);

        assertEq(mYieldToOne.yield(), 11373);

        assertEq(mYieldToOne.getBalanceOf(bob), 0);
        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mToken.balanceOf(bob), amount + amount / 2);
        assertEq(mToken.balanceOf(alice), amount / 2);

        assertEq(mYieldToOne.getBalanceOf(yieldRecipient), 0);

        // claim yield
        mYieldToOne.claimYield();

        assertEq(mYieldToOne.getBalanceOf(yieldRecipient), 11373);
        assertEq(mYieldToOne.yield(), 0);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 11373);
        assertEq(mYieldToOne.totalSupply(), 11373);

        // wrap from earner account
        _addToList(EARNERS_LIST, bob);

        vm.prank(bob);
        mToken.startEarning();

        _swapInM(address(mYieldToOne), bob, bob, amount);

        // Check balances of MYieldToOne and Bob after wrapping
        assertEq(mYieldToOne.getBalanceOf(bob), amount);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 11373 + amount);

        // Disable earning for the contract
        _removeFromList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.disableEarning();

        assertFalse(mYieldToOne.isEarningEnabled());

        // Fast forward 10 days in the future
        vm.warp(vm.getBlockTimestamp() + 10 days);

        // No yield should accrue
        assertEq(mYieldToOne.yield(), 0);

        // Re-enable earning for the contract
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        // Yield should accrue again
        vm.warp(vm.getBlockTimestamp() + 10 days);

        assertEq(mYieldToOne.yield(), 11388);
    }

    /* ============ enableEarning ============ */

    function test_enableEarning_notApprovedEarner() external {
        vm.expectRevert(abi.encodeWithSelector(IMTokenLike.NotApprovedEarner.selector));
        mYieldToOne.enableEarning();
    }

    /* ============ disableEarning ============ */

    function test_disableEarning_approvedEarner() external {
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        vm.expectRevert(abi.encodeWithSelector(IMTokenLike.IsApprovedEarner.selector));
        mYieldToOne.disableEarning();
    }

    /* ============ wrap ============ */

    function test_wrap() external {
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        assertEq(mToken.balanceOf(alice), 10e6);

        _swapInM(address(mYieldToOne), alice, alice, 5e6);

        assertEq(mYieldToOne.getBalanceOf(alice), 5e6);
        assertEq(mYieldToOne.totalSupply(), 5e6);

        assertEq(mToken.balanceOf(alice), 5e6);
        assertApproxEqAbs(mToken.balanceOf(address(mYieldToOne)), 5e6, 1);

        assertEq(mYieldToOne.yield(), 0);

        _swapInM(address(mYieldToOne), alice, alice, 5e6);

        assertEq(mYieldToOne.getBalanceOf(alice), 10e6);
        assertEq(mYieldToOne.totalSupply(), 10e6);

        assertEq(mToken.balanceOf(alice), 0);
        assertApproxEqAbs(mToken.balanceOf(address(mYieldToOne)), 10e6, 2);

        assertEq(mYieldToOne.yield(), 0);

        // Move time forward to generate yield
        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(mYieldToOne.yield(), 42_3730);

        assertEq(mYieldToOne.getBalanceOf(alice), 10e6);
        assertEq(mYieldToOne.totalSupply(), 10e6);
    }

    function test_wrapWithPermits() external {
        _addToList(EARNERS_LIST, address(mYieldToOne));

        assertEq(mToken.balanceOf(alice), 10e6);

        _swapInMWithPermitVRS(address(mYieldToOne), alice, aliceKey, alice, 5e6, 0, block.timestamp);

        assertEq(mYieldToOne.getBalanceOf(alice), 5e6);
        assertEq(mToken.balanceOf(alice), 5e6);

        _swapInMWithPermitSignature(address(mYieldToOne), alice, aliceKey, alice, 5e6, 1, block.timestamp);

        assertEq(mYieldToOne.getBalanceOf(alice), 10e6);
        assertEq(mToken.balanceOf(alice), 0);
    }

    /* ============ unwrap ============ */

    function test_unwrap() external {
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        mYieldToOne.setBalanceOf(alice, 10e6);
        mYieldToOne.setTotalSupply(10e6);
        _giveM(address(mYieldToOne), 10e6);

        // 2 wei are lost due to rounding
        assertApproxEqAbs(mToken.balanceOf(address(mYieldToOne)), 10e6, 2);
        assertEq(mToken.balanceOf(alice), 10e6);
        assertEq(mYieldToOne.getBalanceOf(alice), 10e6);
        assertEq(mYieldToOne.totalSupply(), 10e6);

        // Move time forward to generate yield
        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(mYieldToOne.yield(), 42_3730);

        _swapMOut(address(mYieldToOne), alice, alice, 5e6);

        assertApproxEqAbs(mToken.balanceOf(address(mYieldToOne)), 42_3730 + 5e6, 1);
        assertEq(mToken.balanceOf(alice), 15e6);
        assertEq(mYieldToOne.getBalanceOf(alice), 5e6);
        assertEq(mYieldToOne.totalSupply(), 5e6);

        _swapMOut(address(mYieldToOne), alice, alice, 5e6);

        assertEq(mToken.balanceOf(alice), 20e6);

        // Alice's full withdrawal would have reverted without yield.
        // The 2 wei lost due to rounding were covered by the yield.
        assertEq(mYieldToOne.yield(), 42_3730 - 2);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 42_3730 - 2);

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.totalSupply(), 0);
    }

    function test_unwrapWithPermits() external {
        // `permit` reverts on MYieldToOne, so this swaps out via the native infra `approve` path.
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        mYieldToOne.setBalanceOf(alice, 11e6);
        mYieldToOne.setTotalSupply(11e6);
        _giveM(address(mYieldToOne), 11e6);

        assertEq(mToken.balanceOf(alice), 10e6);
        assertEq(mYieldToOne.getBalanceOf(alice), 11e6);

        _swapMOut(address(mYieldToOne), alice, alice, 5e6);

        assertEq(mYieldToOne.getBalanceOf(alice), 6e6);
        assertEq(mToken.balanceOf(alice), 15e6);

        _swapMOut(address(mYieldToOne), alice, alice, 5e6);

        assertEq(mYieldToOne.getBalanceOf(alice), 1e6);
        assertEq(mToken.balanceOf(alice), 20e6);
    }

    function test_unwrapWithPermits_unsupported() external {
        // `permit` reverts inside SwapFacility's try/catch, so the swap fails on the zero allowance.
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        mYieldToOne.setBalanceOf(alice, 11e6);
        mYieldToOne.setTotalSupply(11e6);
        _giveM(address(mYieldToOne), 11e6);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Extended.InsufficientAllowance.selector, address(swapFacility), 0, 5e6)
        );
        _swapOutMWithPermitVRS(address(mYieldToOne), alice, aliceKey, alice, 5e6, 0, block.timestamp);
    }

    /* ============ claimYield ============ */

    function test_claimYield() external {
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        mYieldToOne.setBalanceOf(alice, 10e6);
        mYieldToOne.setTotalSupply(10e6);
        _giveM(address(mYieldToOne), 10e6);

        // 2 wei are lost due to rounding
        assertApproxEqAbs(mToken.balanceOf(address(mYieldToOne)), 10e6, 2);
        assertEq(mYieldToOne.getBalanceOf(yieldRecipient), 0);

        // Move time forward to generate yield
        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(mYieldToOne.yield(), 42_3730);
        assertEq(mYieldToOne.totalSupply(), 10e6);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 10e6 + 42_3730); // Rounding error has been covered by yield

        assertEq(mYieldToOne.claimYield(), 42_3730);

        assertEq(mYieldToOne.yield(), 0);
        assertEq(mYieldToOne.totalSupply(), 10e6 + 42_3730);
        assertEq(mYieldToOne.getBalanceOf(yieldRecipient), 42_3730);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 10e6 + 42_3730);
    }
}
