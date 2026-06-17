// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Vm } from "../../../lib/forge-std/src/Vm.sol";

import { Upgrades } from "../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";

import { MYieldToOneForcedTransfer } from "../../../src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";
import { MYieldFee } from "../../../src/projects/yieldToAllWithFee/MYieldFee.sol";

import { IMYieldToOne } from "../../../src/projects/yieldToOne/interfaces/IMYieldToOne.sol";
import { IMExtension } from "../../../src/interfaces/IMExtension.sol";
import { IFreezable } from "../../../src/components/freezable/IFreezable.sol";
import { ISwapFacility } from "../../../src/swap/interfaces/ISwapFacility.sol";

import { MYieldToOneForcedTransferHarness } from "../../harness/MYieldToOneForcedTransferHarness.sol";
import { MYieldFeeHarness } from "../../harness/MYieldFeeHarness.sol";

import { BaseUnitTest } from "../../utils/BaseUnitTest.sol";

/// @dev In-process, NON-FORKING system integration suite for the shielded SRC-20 token.
///      Deploys the shielded `MYieldToOneForcedTransfer` and a sibling `MYieldFee` behind proxies
///      against the same real `SwapFacility` + `MockM` infra the unit suite uses. Runs against the
///      REAL Seismic precompiles (sforge's mercury EVM) — a real contract key is installed and holder
///      public keys are registered, so the encrypted-event path is exercised with no `vm.mockCall`.
///
///      Mirrors the SRC-20-relevant flows of the excluded mainnet-fork `MExtensionSystem.t.sol`
///      (multi-extension swap, yield lifecycle, freeze-during-yield, permissioned gating) with
///      RELATIONAL assertions — conservation, monotonicity, typed reverts — not the fork suite's
///      hardcoded mainnet yield constants.
contract MExtensionSystemSeismicIntegrationTests is BaseUnitTest {
    bytes32 internal constant TRANSFER_BYTES_TOPIC = keccak256("Transfer(address,address,bytes32,bytes)");

    // Non-round index so the sibling extension's principal math runs on a realistic value.
    uint128 internal constant _M_INDEX = 1_100000068703;

    MYieldToOneForcedTransferHarness public mYieldToOne;
    MYieldFeeHarness public mYieldFee;

    Vm.Wallet public contractWallet;
    Vm.Wallet public aliceWallet;
    Vm.Wallet public bobWallet;

    function setUp() public override {
        super.setUp();

        // Realistic, non-zero $M index: the sibling `MYieldFee` principal conversions divide by it.
        mToken.setCurrentIndex(_M_INDEX);

        // Deploy the shielded extension behind a proxy. Args are passed in PRODUCTION
        // `MYieldToOneForcedTransfer.initialize` order (yieldRecipient, admin, freezeManager,
        // yieldRecipientManager, pauser, forcedTransferManager): the harness's positional forward to
        // `super.initialize` makes the param NAMES on its own `initialize` misleading, so role wiring
        // is correct only when the call site mirrors the production order — same as MYieldToOneSimulation.t.sol.
        mYieldToOne = MYieldToOneForcedTransferHarness(
            Upgrades.deployTransparentProxy(
                "MYieldToOneForcedTransferHarness.sol:MYieldToOneForcedTransferHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldToOneForcedTransfer.initialize.selector,
                    "Seismic Dollar",
                    "USDS",
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

        // Sibling extension. `MYieldFee` is index-based; with earning disabled its index stays at
        // EXP_SCALED_ONE so swaps move value 1:1, which keeps the cross-extension assertions clean.
        mYieldFee = MYieldFeeHarness(
            Upgrades.deployTransparentProxy(
                "MYieldFeeHarness.sol:MYieldFeeHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldFeeHarness.initialize.selector,
                    "Seismic Yield",
                    "SY",
                    uint16(0),
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

        registrar.setEarner(address(mYieldToOne), true);
        registrar.setEarner(address(mYieldFee), true);

        // Real Seismic keys: contract keypair + per-holder registered pubkeys drive the real
        // encrypted-event precompiles (0x65/0x66/0x68), no mocks.
        contractWallet = vm.createWallet("seismic contract key");
        aliceWallet = vm.createWallet("seismic alice key");
        bobWallet = vm.createWallet("seismic bob key");

        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(contractWallet.privateKey)), _compressed(contractWallet));

        vm.prank(alice);
        mYieldToOne.registerPublicKey(_compressed(aliceWallet));

        vm.prank(bob);
        mYieldToOne.registerPublicKey(_compressed(bobWallet));

        vm.startPrank(admin);
        swapFacility.grantRole(M_SWAPPER_ROLE, alice);
        swapFacility.grantRole(M_SWAPPER_ROLE, bob);
        vm.stopPrank();
    }

    /* ============ wrap -> shielded balance ============ */

    function test_wrap_shieldedBalanceAndBacking() external {
        uint256 amount_ = 1_000e6;

        _wrapInto(mYieldToOne, alice, amount_);

        // Wrap is 1:1: the holder's shielded balance equals the wrapped amount.
        assertEq(mYieldToOne.getBalanceOf(alice), amount_);
        assertEq(mYieldToOne.totalSupply(), amount_);

        // M backing fully covers the minted supply.
        assertEq(mToken.balanceOf(address(mYieldToOne)), mYieldToOne.totalSupply());
    }

    function testFuzz_wrap_shieldedBalanceAndBacking(uint256 amount_) external {
        amount_ = bound(amount_, 1, 1e15);

        _wrapInto(mYieldToOne, alice, amount_);

        assertEq(mYieldToOne.getBalanceOf(alice), amount_);
        assertEq(mYieldToOne.totalSupply(), amount_);
        assertGe(mToken.balanceOf(address(mYieldToOne)), mYieldToOne.totalSupply());
    }

    /* ============ cross-extension swap (native infra paths) ============ */

    function test_crossExtensionSwap_mYieldToOne_to_mYieldFee() external {
        uint256 amount_ = 500e6;

        _wrapInto(mYieldToOne, alice, amount_);

        uint256 totalBackingBefore_ = mToken.balanceOf(address(mYieldToOne)) + mToken.balanceOf(address(mYieldFee));

        // The swap-out leg routes through MYieldToOne's NATIVE infra paths: the holder's
        // `approve(swapFacility, amount)` and SwapFacility's `transferFrom(holder, facility, amount)`
        // both take the `_isInfra` branch (swapFacility is the immutable infra address), NOT the
        // user-revert `UseShieldedApprove` / `UseShieldedTransfer` paths.
        vm.prank(alice);
        mYieldToOne.approve(address(swapFacility), amount_);

        vm.prank(alice);
        swapFacility.swap(address(mYieldToOne), address(mYieldFee), amount_, alice);

        // Value conserved across the hop (1:1, both extensions at a flat index).
        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldFee.balanceOf(alice), amount_);

        // M backing is conserved system-wide, only relocated between the two extensions.
        assertEq(mToken.balanceOf(address(mYieldToOne)) + mToken.balanceOf(address(mYieldFee)), totalBackingBefore_);
        assertEq(mToken.balanceOf(address(mYieldFee)), amount_);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 0);
    }

    function test_crossExtensionSwap_nativeApproveReachesInfraPath() external {
        uint256 amount_ = 10e6;

        _wrapInto(mYieldToOne, alice, amount_);

        // A non-infra spender on the native overload must hit the user-revert path...
        vm.prank(alice);
        vm.expectRevert(IMYieldToOne.UseShieldedApprove.selector);
        mYieldToOne.approve(bob, amount_);

        // ...while the infra spender (swapFacility) is accepted and records the allowance.
        vm.prank(alice);
        mYieldToOne.approve(address(swapFacility), amount_);

        vm.prank(alice);
        assertEq(mYieldToOne.allowance(alice, address(swapFacility)), amount_);
    }

    /* ============ shielded transfer / transferFrom between holders ============ */

    function test_shieldedTransfer_emitsRealCiphertext_andMovesBalance() external {
        uint256 amount_ = 800e6;

        _wrapInto(mYieldToOne, alice, amount_);

        uint256 nonceBefore_ = mYieldToOne.getEncryptedEventNonce();

        vm.recordLogs();

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount_));

        // A real encrypted `Transfer(address,address,bytes32,bytes)` is emitted to the registered recipient,
        // with non-empty ciphertext, and the per-emit nonce advances.
        bytes memory ciphertext_ = _extractPayload(TRANSFER_BYTES_TOPIC, alice, bob);
        assertGt(ciphertext_.length, 0);
        assertEq(mYieldToOne.getEncryptedEventNonce(), nonceBefore_ + 1);

        // Balances move correctly under the shielded path.
        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount_);
        assertEq(mYieldToOne.totalSupply(), amount_);
    }

    function test_shieldedTransferFrom_betweenHolders() external {
        uint256 amount_ = 300e6;

        _wrapInto(mYieldToOne, alice, amount_);

        // alice approves carol (shielded) to move funds to the registered recipient bob.
        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount_));

        uint256 nonceBefore_ = mYieldToOne.getEncryptedEventNonce();

        vm.recordLogs();

        vm.prank(carol);
        mYieldToOne.transferFrom(alice, bob, suint256(amount_));

        bytes memory ciphertext_ = _extractPayload(TRANSFER_BYTES_TOPIC, alice, bob);
        assertGt(ciphertext_.length, 0);
        assertEq(mYieldToOne.getEncryptedEventNonce(), nonceBefore_ + 1);

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount_);
        assertEq(mYieldToOne.getShieldedAllowance(alice, carol), 0);
    }

    function test_shieldedTransfer_insufficientBalance() external {
        uint256 amount_ = 100e6;

        _wrapInto(mYieldToOne, alice, amount_);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 0, amount_ + 1));
        mYieldToOne.transfer(bob, suint256(amount_ + 1));
    }

    /* ============ yield lifecycle ============ */

    function test_yieldLifecycle_accrueAndClaim() external {
        uint256 amount_ = 1_000e6;

        _wrapInto(mYieldToOne, alice, amount_);

        assertEq(mYieldToOne.yield(), 0);
        assertGe(mToken.balanceOf(address(mYieldToOne)), mYieldToOne.totalSupply());

        // Simulate M yield by bumping the extension's mock M balance (the MockM has no index accrual).
        uint256 yieldDelta_ = 7_500;
        mToken.setBalanceOf(address(mYieldToOne), mToken.balanceOf(address(mYieldToOne)) + yieldDelta_);

        assertGt(mYieldToOne.yield(), 0);
        assertEq(mYieldToOne.yield(), yieldDelta_);

        uint256 recipientBefore_ = mYieldToOne.getBalanceOf(yieldRecipient);
        uint256 supplyBefore_ = mYieldToOne.totalSupply();

        uint256 claimed_ = mYieldToOne.claimYield();

        // claimYield mints the accrued yield to the yield recipient and clears the surplus.
        assertEq(claimed_, yieldDelta_);
        assertEq(mYieldToOne.getBalanceOf(yieldRecipient), recipientBefore_ + yieldDelta_);
        assertEq(mYieldToOne.totalSupply(), supplyBefore_ + yieldDelta_);
        assertEq(mYieldToOne.yield(), 0);

        // Backing invariant holds throughout.
        assertGe(mToken.balanceOf(address(mYieldToOne)), mYieldToOne.totalSupply());
    }

    function testFuzz_yieldLifecycle_backingHolds(uint256 amount_, uint256 yieldDelta_) external {
        amount_ = bound(amount_, 1, 1e15);
        yieldDelta_ = bound(yieldDelta_, 1, 1e15);

        _wrapInto(mYieldToOne, alice, amount_);

        mToken.setBalanceOf(address(mYieldToOne), mToken.balanceOf(address(mYieldToOne)) + yieldDelta_);

        assertEq(mYieldToOne.yield(), yieldDelta_);

        mYieldToOne.claimYield();

        assertEq(mYieldToOne.yield(), 0);
        assertEq(mYieldToOne.getBalanceOf(yieldRecipient), yieldDelta_);
        assertGe(mToken.balanceOf(address(mYieldToOne)), mYieldToOne.totalSupply());
    }

    /* ============ freeze during yield ============ */

    function test_freeze_duringYield_blocksFlowAndSeizes() external {
        uint256 amount_ = 1_000e6;

        _wrapInto(mYieldToOne, alice, amount_);

        // Grant the swap-out and spender allowances BEFORE freezing, so the blocked operations
        // surface `AccountFrozen` from the `_beforeTransfer` hook rather than tripping the
        // allowance check first.
        vm.prank(alice);
        mYieldToOne.approve(address(swapFacility), amount_);

        vm.prank(alice);
        mYieldToOne.approve(carol, suint256(amount_));

        // Accrue some yield before freezing.
        mToken.setBalanceOf(address(mYieldToOne), mToken.balanceOf(address(mYieldToOne)) + 5_000);
        uint256 yieldBeforeFreeze_ = mYieldToOne.yield();
        assertGt(yieldBeforeFreeze_, 0);

        vm.expectEmit(true, true, true, true);
        emit IFreezable.Frozen(alice, vm.getBlockTimestamp());

        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        // Yield keeps accruing while alice is frozen.
        mToken.setBalanceOf(address(mYieldToOne), mToken.balanceOf(address(mYieldToOne)) + 5_000);
        assertGt(mYieldToOne.yield(), yieldBeforeFreeze_);

        // A frozen holder's swap/transfer/approve/transferFrom all revert AccountFrozen.
        vm.prank(alice);
        mToken.approve(address(swapFacility), amount_); // mock M approval is unaffected by freeze

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swap(address(mYieldToOne), address(mYieldFee), amount_, alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldToOne.transfer(bob, suint256(amount_));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldToOne.approve(address(swapFacility), amount_);

        vm.stopPrank();

        // transferFrom on a frozen owner also reverts (here carol would be the spender).
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldToOne.transferFrom(alice, bob, suint256(amount_));

        // The forced-transfer manager seizes from the frozen account (no freeze checks on this path).
        uint256 seizeAmount_ = 400e6;
        vm.prank(forcedTransferManager);
        mYieldToOne.forceTransfer(alice, bob, seizeAmount_);

        assertEq(mYieldToOne.getBalanceOf(alice), amount_ - seizeAmount_);
        assertEq(mYieldToOne.getBalanceOf(bob), seizeAmount_);

        // Unfreeze restores normal flow: alice can transfer the remainder.
        vm.prank(freezeManager);
        mYieldToOne.unfreeze(alice);

        vm.prank(alice);
        mYieldToOne.transfer(bob, suint256(amount_ - seizeAmount_));

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mYieldToOne.getBalanceOf(bob), amount_);

        // Supply unchanged by the freeze/seize/transfer churn; yield still claimable.
        assertEq(mYieldToOne.totalSupply(), amount_);
        assertGt(mYieldToOne.yield(), 0);
    }

    /* ============ permissioned-extension gating ============ */

    function test_permissionedExtension_gating() external {
        uint256 amount_ = 100e6;

        // Seed alice's $M and a standing $M approval to the facility (the swap-out leg returns it).
        mToken.setBalanceOf(alice, amount_);

        vm.prank(alice);
        mToken.approve(address(swapFacility), amount_);

        // Mark MYieldToOne permissioned: only an explicitly-allowed M swapper may swap M in/out of it.
        vm.prank(admin);
        swapFacility.setPermissionedExtension(address(mYieldToOne), true);

        // alice holds M_SWAPPER_ROLE but is NOT yet a permissioned M swapper for this extension.

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.NotApprovedPermissionedSwapper.selector, address(mYieldToOne), alice)
        );
        swapFacility.swapInM(address(mYieldToOne), amount_, alice);

        // Grant the permissioned-swapper right; the swap-in now succeeds.
        vm.prank(admin);
        swapFacility.setPermissionedMSwapper(address(mYieldToOne), alice, true);

        vm.prank(alice);
        swapFacility.swapInM(address(mYieldToOne), amount_, alice);
        assertEq(mYieldToOne.getBalanceOf(alice), amount_);

        // A permissioned extension cannot be the input of an extension->extension swap.
        vm.prank(alice);
        mYieldToOne.approve(address(swapFacility), amount_);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.PermissionedExtension.selector, address(mYieldToOne)));
        swapFacility.swap(address(mYieldToOne), address(mYieldFee), amount_, alice);

        // Revoking the swapper right re-closes the swap-out M path.
        vm.prank(admin);
        swapFacility.setPermissionedMSwapper(address(mYieldToOne), alice, false);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapFacility.NotApprovedPermissionedSwapper.selector, address(mYieldToOne), alice)
        );
        swapFacility.swapOutM(address(mYieldToOne), amount_, alice);

        // Lifting the permissioned flag returns the extension to the open M_SWAPPER_ROLE regime.
        vm.prank(admin);
        swapFacility.setPermissionedExtension(address(mYieldToOne), false);

        vm.prank(alice);
        swapFacility.swapOutM(address(mYieldToOne), amount_, alice);

        assertEq(mYieldToOne.getBalanceOf(alice), 0);
        assertEq(mToken.balanceOf(alice), amount_);
    }

    /* ============ helpers ============ */

    /// @dev Wraps `amount` $M into `extension` for `holder` through the real SwapFacility swap-in path.
    function _wrapInto(IERC20 extension, address holder, uint256 amount) internal {
        mToken.setBalanceOf(holder, mToken.balanceOf(holder) + amount);

        vm.prank(holder);
        mToken.approve(address(swapFacility), amount);

        vm.prank(holder);
        swapFacility.swapInM(address(extension), amount, holder);
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
}
