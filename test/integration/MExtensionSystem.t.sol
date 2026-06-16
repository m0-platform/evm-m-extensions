// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Upgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";
import { IndexingMath } from "../../lib/common/src/libs/IndexingMath.sol";
import { ContinuousIndexingMath } from "../../lib/common/src/libs/ContinuousIndexingMath.sol";

import { IContinuousIndexing } from "../../src/projects/yieldToAllWithFee/interfaces/IContinuousIndexing.sol";

import { MEarnerManagerHarness } from "../harness/MEarnerManagerHarness.sol";
import { MYieldToOneHarness } from "../harness/MYieldToOneHarness.sol";
import { MYieldFeeHarness } from "../harness/MYieldFeeHarness.sol";

import { BaseIntegrationTest } from "../utils/BaseIntegrationTest.sol";

import { IFreezable } from "../../src/components/freezable/IFreezable.sol";

import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

import { IRegistrarLike } from "../../src/swap/interfaces/IRegistrarLike.sol";

contract MExtensionSystemIntegrationTests is BaseIntegrationTest {
    uint256 public mainnetFork;

    uint128 public mIndexInitial;
    uint128 public mYieldFeeIndexInitial;

    uint32 public mRate;
    uint40 public mRateStart;

    uint32 public mYieldFeeRate;
    uint32 public mYieldFeeIndexStart;

    uint16 public mEarnerFeeRate;

    function setUp() public override {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_482_175);

        super.setUp();

        _fundAccounts();

        mEarnerManager = MEarnerManagerHarness(
            Upgrades.deployTransparentProxy(
                "MEarnerManagerHarness.sol:MEarnerManagerHarness",
                admin,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    NAME,
                    SYMBOL,
                    admin,
                    earnerManager,
                    feeRecipient,
                    pauser
                ),
                mExtensionDeployOptions
            )
        );

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
                    pauser
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
                    1e3,
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

        _addToList(EARNERS_LIST, address(mYieldFee));
        _addToList(EARNERS_LIST, address(mYieldToOne));
        _addToList(EARNERS_LIST, address(mEarnerManager));

        mEarnerManager.enableEarning();
        mYieldFee.enableEarning();
        mYieldToOne.enableEarning();

        mIndexInitial = mToken.currentIndex();
        mYieldFeeIndexInitial = mYieldFee.currentIndex();

        mRate = mToken.earnerRate();
        mRateStart = IContinuousIndexing(address(mToken)).latestUpdateTimestamp();

        mYieldFeeRate = mYieldFee.earnerRate();
        mYieldFeeIndexStart = uint32(vm.getBlockTimestamp());

        _fundAccounts();

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 5_000); // 50% fee

        mEarnerFeeRate = 5_000;

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(address(swapFacility), true, 0);

        vm.startPrank(admin);
        swapFacility.grantRole(M_SWAPPER_ROLE, alice);
        swapFacility.grantRole(M_SWAPPER_ROLE, bob);
        swapFacility.grantRole(M_SWAPPER_ROLE, carol);
        mYieldToOne.setContractKey(
            sbytes32(bytes32(uint256(0xC0FFEE))),
            hex"02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        );
        vm.stopPrank();
    }

    function test_integration_constants_system() external view {
        assertEq(mEarnerManager.name(), NAME);
        assertEq(mEarnerManager.symbol(), SYMBOL);
        assertEq(mEarnerManager.decimals(), 6);
        assertEq(mEarnerManager.mToken(), address(mToken));
        assertEq(mEarnerManager.feeRecipient(), feeRecipient);
        assertEq(mEarnerManager.ONE_HUNDRED_PERCENT(), 10_000);
        assertTrue(mEarnerManager.hasRole(PAUSER_ROLE, pauser));
        assertTrue(mEarnerManager.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mEarnerManager.hasRole(EARNER_MANAGER_ROLE, earnerManager));

        assertEq(mYieldToOne.name(), NAME);
        assertEq(mYieldToOne.symbol(), SYMBOL);
        assertEq(mYieldToOne.decimals(), 6);
        assertEq(mYieldToOne.mToken(), address(mToken));
        assertEq(mYieldToOne.swapFacility(), address(swapFacility));
        assertEq(mYieldToOne.yieldRecipient(), yieldRecipient);
        assertTrue(mYieldToOne.hasRole(PAUSER_ROLE, pauser));
        assertTrue(mYieldToOne.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldToOne.hasRole(FREEZE_MANAGER_ROLE, freezeManager));
        assertTrue(mYieldToOne.hasRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager));

        assertEq(mYieldFee.name(), NAME);
        assertEq(mYieldFee.symbol(), SYMBOL);
        assertEq(mYieldFee.decimals(), 6);
        assertEq(mYieldFee.mToken(), address(mToken));
        assertEq(mYieldFee.feeRecipient(), feeRecipient);
        assertEq(mYieldFee.feeRate(), 1e3);
        assertTrue(mYieldFee.hasRole(PAUSER_ROLE, pauser));
        assertTrue(mYieldFee.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldFee.hasRole(FEE_MANAGER_ROLE, feeManager));
        assertTrue(mYieldFee.hasRole(CLAIM_RECIPIENT_MANAGER_ROLE, claimRecipientManager));
        assertTrue(mYieldFee.hasRole(FREEZE_MANAGER_ROLE, freezeManager));
    }

    function test_multiHopSwap_mYieldFee_to_mYieldToOne_to_wrappedM() public {
        vm.startPrank(alice);
        mToken.approve(address(swapFacility), 10e6);
        mYieldFee.approve(address(swapFacility), 10e6);
        mYieldToOne.approve(address(swapFacility), 10e6);
        mEarnerManager.approve(address(swapFacility), 10e6);
        wrappedM.approve(address(swapFacility), 10e6);
        vm.stopPrank();

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mYieldFee), 10e6, alice);

        uint256 mYieldFeeBalance = mYieldFee.balanceOf(alice);
        assertEq(mYieldFeeBalance, 10e6);

        vm.prank(alice);
        swapFacility.swap(address(mYieldFee), address(mYieldToOne), mYieldFeeBalance - 2, alice);

        uint256 mYieldToOneBalance = mYieldToOne.getBalanceOf(alice);
        assertEq(mYieldToOneBalance, 10e6 - 2);

        vm.prank(alice);
        swapFacility.swap(address(mYieldToOne), address(mEarnerManager), mYieldToOneBalance - 2, alice);

        uint256 mEarnerManagerBalance = mEarnerManager.balanceOf(alice);
        assertEq(mEarnerManagerBalance, 10e6 - 4);

        vm.prank(alice);
        swapFacility.swap(address(mEarnerManager), address(wrappedM), mEarnerManagerBalance - 2, alice);

        uint256 wrappedMBalance = wrappedM.balanceOf(alice);
        assertEq(wrappedMBalance, 10e6 - 7);
    }

    function test_yieldFlow_betweenExtensions() public {
        // Setup multiple extensions with different yield configurations
        // Swap between them and verify yield is properly tracked
        vm.startPrank(alice);
        mToken.approve(address(swapFacility), 10e6);
        mYieldFee.approve(address(swapFacility), 10e6);
        mYieldToOne.approve(address(swapFacility), 10e6);
        mEarnerManager.approve(address(swapFacility), 10e6);
        wrappedM.approve(address(swapFacility), 10e6);
        vm.stopPrank();

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mYieldFee), 10e6, alice);

        uint256 mYieldFeeBalance = mYieldFee.balanceOf(alice);
        assertEq(mYieldFeeBalance, 10e6);

        // fast forward to accrue yield
        vm.warp(vm.getBlockTimestamp() + 72_426_135);

        // check and claim yield from mYieldFee
        uint256 mYieldFeeYield = mYieldFee.accruedYieldOf(alice);
        assertEq(mYieldFeeYield, 894400, "Should have accrued yield in mYieldFee");

        vm.prank(alice);
        swapFacility.swap(address(mYieldFee), address(mYieldToOne), mYieldFeeBalance, alice);

        uint256 mYieldToOneBalance = mYieldToOne.getBalanceOf(alice);
        assertEq(mYieldToOneBalance, 10e6);

        // fast forward to accrue yield
        vm.warp(vm.getBlockTimestamp() + 10 days);

        // check and claim yield from mYieldToOne
        uint256 mYieldToOneYield = mYieldToOne.yield();
        assertEq(mYieldToOneYield, 11375, "Should have accrued yield in mYieldToOne");

        vm.prank(alice);
        swapFacility.swap(address(mYieldToOne), address(mEarnerManager), mYieldToOneBalance, alice);

        uint256 mEarnerManagerBalance = mEarnerManager.balanceOf(alice);
        assertEq(mEarnerManagerBalance, 10e6);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        (uint256 aliceYieldWithFee, uint256 aliceFee, uint256 aliceYield) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(aliceYieldWithFee, 11375, "alice's yield with fee should be 11375");
        assertEq(aliceFee, 5687, "alice's fee should be 5687");
        assertEq(aliceYield, 5688, "alice's yield should be 5688");

        vm.prank(alice);
        swapFacility.swap(address(mEarnerManager), address(wrappedM), mEarnerManagerBalance - 2, alice);

        uint256 wrappedMBalance = wrappedM.balanceOf(alice);
        assertEq(wrappedMBalance, 10e6 - 2);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        vm.prank(alice);
        swapFacility.swap(address(wrappedM), address(mToken), wrappedMBalance, alice);

        mEarnerManagerBalance = mEarnerManager.balanceOf(alice);

        assertEq(mEarnerManagerBalance, 2);

        mEarnerManager.claimFor(alice);

        mEarnerManagerBalance = mEarnerManager.balanceOf(alice);

        assertEq(mEarnerManagerBalance, 5696, "alice's claiming should have put her yield in her balance");

        assertEq(
            mEarnerManager.balanceOf(feeRecipient),
            5693,
            "Fee recipient should have fee claimed for on alice's claiming"
        );

        mYieldToOne.claimYield();

        mYieldToOneBalance = mYieldToOne.getBalanceOf(yieldRecipient);

        assertEq(mYieldToOneBalance, 11401, "yield recipient should have its yield claimed");

        mYieldFee.claimYieldFor(alice);

        mYieldFeeBalance = mYieldFee.balanceOf(alice);

        assertEq(mYieldFeeBalance, 897145, "alice should have her yield claimed");
    }

    uint256 constant M_YIELD_TO_ONE = 0;
    uint256 constant M_YIELD_FEE = 1;
    uint256 constant M_EARNER_MANAGER = 2;

    /// @dev Using lower fuzz runs and depth to avoid burning through RPC requests in CI
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: default.fuzz.depth = 20
    /// forge-config: ci.fuzz.runs = 10
    /// forge-config: ci.fuzz.depth = 2
    function testFuzz_yieldClaim_afterMultipleSwaps(uint256 seed) public {
        vm.startPrank(alice);
        mToken.approve(address(swapFacility), type(uint256).max);
        mYieldFee.approve(address(swapFacility), type(uint256).max);
        mYieldToOne.approve(address(swapFacility), type(uint256).max);
        mEarnerManager.approve(address(swapFacility), type(uint256).max);
        wrappedM.approve(address(swapFacility), type(uint256).max);
        vm.stopPrank();

        // The fuzz test works by placing function signatures of functions that
        // will swap into an extension from a prior extension, make an assertion
        // against the state that has been swapped into, and accumulate a value
        // throughout the invocations which will be asserted against at the end
        // of the test once the fuzzed permutation is finished.
        function(
            address /* from */,
            uint256[] memory /* yieldsAccumulator */,
            uint256 /* amountIn */
        ) internal returns (uint256, uint256[] memory)[]
            memory yieldAssertions = new function(
                address,
                uint256[] memory,
                uint256
            ) internal returns (uint256, uint256[] memory)[](3);
        yieldAssertions[M_YIELD_TO_ONE] = _testYieldCapture_mYieldToOne;
        yieldAssertions[M_YIELD_FEE] = _testYieldCapture_mYieldFee;
        yieldAssertions[M_EARNER_MANAGER] = _testYieldCapture_mEarnerManager;

        address[] memory extensions = new address[](3);
        extensions[M_YIELD_TO_ONE] = address(mYieldToOne);
        extensions[M_YIELD_FEE] = address(mYieldFee);
        extensions[M_EARNER_MANAGER] = address(mEarnerManager);

        uint256 amount;

        uint256[] memory yields = new uint256[](3);

        (amount, yields) = yieldAssertions[M_YIELD_TO_ONE](address(mToken), yields, 10e6);

        uint256 extensionIndex;

        for (uint256 i = 0; i < 20; i++) {
            // The test uses the iteration of the loop combined with the seed
            // of the fuzz run to create random extension indexes which will
            // be invoked one after the other, allowing for a random order
            // of extensions being swapped into and out of

            uint256 nextExtensionIndex = uint256(keccak256(abi.encode(seed, i))) % 3;

            if (nextExtensionIndex == extensionIndex) nextExtensionIndex = (nextExtensionIndex + 1) % 3;

            (amount, yields) = yieldAssertions[nextExtensionIndex](extensions[extensionIndex], yields, amount);

            extensionIndex = nextExtensionIndex;
        }

        vm.prank(alice);
        swapFacility.swap(extensions[extensionIndex], address(mToken), amount, alice);

        mYieldToOne.claimYield();
        assertApproxEqAbs(mYieldToOne.getBalanceOf(yieldRecipient), yields[M_YIELD_TO_ONE], 20);

        mYieldFee.claimYieldFor(alice);
        assertApproxEqAbs(mYieldFee.balanceOf(alice), yields[M_YIELD_FEE], 50);

        mEarnerManager.claimFor(alice);
        assertApproxEqAbs(mEarnerManager.balanceOf(alice), yields[M_EARNER_MANAGER] / 2, 50);
        assertApproxEqAbs(mEarnerManager.balanceOf(feeRecipient), yields[M_EARNER_MANAGER] / 2, 50);
    }

    function test_mYieldFee_feeRecipientChange_duringActiveYield() public {
        vm.prank(alice);
        mToken.approve(address(swapFacility), type(uint256).max);

        address feeRecipient2 = makeAddr("feeRecipient2");

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mYieldFee), 10e6, alice);

        mRateStart = uint40(vm.getBlockTimestamp());

        uint112 _initialMPrincipalInMYieldFee = _calcMPrincipalAmountRoundedUp(10e6 - 2);

        uint112 _initialMYieldFeePrincipal = _calcMYieldFeePrincipal(10e6 - 2);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        uint256 _postWarpMAmountInMYieldFee = _calcMPresentAmountRoundedDown(_initialMPrincipalInMYieldFee);

        uint256 _postWarpMYieldFeeBalance = _calcMYieldFeePresentAmountRoundedDown(_initialMYieldFeePrincipal);

        uint256 _expectedFee = _postWarpMAmountInMYieldFee - _postWarpMYieldFeeBalance;

        vm.prank(feeManager);
        mYieldFee.setFeeRecipient(feeRecipient2);

        assertApproxEqAbs(mYieldFee.balanceOf(feeRecipient), _expectedFee, 3);

        _initialMYieldFeePrincipal += _calcMYieldFeePrincipal(_expectedFee);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        _postWarpMAmountInMYieldFee = _calcMPresentAmountRoundedDown(_initialMPrincipalInMYieldFee);

        _postWarpMYieldFeeBalance = _calcMYieldFeePresentAmountRoundedDown(_initialMYieldFeePrincipal);

        uint256 _balanceWithYield = IndexingMath.getPresentAmountRoundedDown(
            _initialMYieldFeePrincipal,
            _currentMYieldFeeIndex()
        );

        _expectedFee = _postWarpMAmountInMYieldFee - _postWarpMYieldFeeBalance;

        vm.prank(feeManager);
        mYieldFee.setFeeRecipient(feeRecipient);

        assertApproxEqAbs(mYieldFee.balanceOf(feeRecipient), _expectedFee, 3);
    }

    function test_permissionedExtension_fullLifecycle() public {
        vm.startPrank(alice);
        mToken.approve(address(swapFacility), type(uint256).max);
        mYieldFee.approve(address(swapFacility), type(uint256).max);
        mYieldToOne.approve(address(swapFacility), type(uint256).max);
        mEarnerManager.approve(address(swapFacility), type(uint256).max);
        wrappedM.approve(address(swapFacility), type(uint256).max);
        vm.stopPrank();

        vm.prank(admin);
        swapFacility.setPermissionedExtension(address(mYieldToOne), true);

        vm.prank(admin);
        swapFacility.setPermissionedExtension(address(mYieldFee), true);

        vm.prank(admin);
        swapFacility.setPermissionedExtension(address(mEarnerManager), true);

        vm.prank(admin);
        swapFacility.setPermissionedMSwapper(address(mYieldToOne), alice, true);

        vm.prank(admin);
        swapFacility.setPermissionedMSwapper(address(mYieldFee), alice, true);

        vm.prank(admin);
        swapFacility.setPermissionedMSwapper(address(mEarnerManager), alice, true);

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mYieldToOne), 10e6, alice);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.PermissionedExtension.selector, address(mYieldToOne)));

        vm.prank(alice);
        swapFacility.swap(address(mYieldToOne), address(mYieldFee), 10e6, alice);

        vm.prank(alice);
        swapFacility.swap(address(mYieldToOne), address(mToken), 10e6 - 2, alice);

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mYieldFee), 10e6, alice);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.PermissionedExtension.selector, address(mYieldFee)));

        vm.prank(alice);
        swapFacility.swap(address(mYieldFee), address(mYieldToOne), 10e6 - 2, alice);

        vm.prank(alice);
        swapFacility.swap(address(mYieldFee), address(mToken), 10e6 - 2, alice);

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mEarnerManager), 10e6, alice);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.PermissionedExtension.selector, address(mEarnerManager)));

        vm.prank(alice);
        swapFacility.swap(address(mEarnerManager), address(mYieldFee), 10e6 - 2, alice);

        vm.prank(admin);
        swapFacility.setPermissionedMSwapper(address(mEarnerManager), alice, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapFacility.NotApprovedPermissionedSwapper.selector,
                address(mEarnerManager),
                alice
            )
        );

        vm.prank(alice);
        swapFacility.swap(address(mEarnerManager), address(mToken), 10e6 - 2, alice);

        vm.prank(admin);
        swapFacility.setPermissionedExtension(address(mEarnerManager), false);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.PermissionedExtension.selector, address(mYieldToOne)));

        vm.prank(alice);
        swapFacility.swap(address(mEarnerManager), address(mYieldToOne), 10e6 - 2, alice);

        vm.prank(admin);
        swapFacility.setPermissionedExtension(address(mYieldToOne), false);

        vm.prank(alice);
        swapFacility.swap(address(mEarnerManager), address(mYieldToOne), 10e6 - 2, alice);

        assertEq(mYieldToOne.getBalanceOf(alice), 10e6, "mYieldToOne balance should be 10e6");

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.PermissionedExtension.selector, address(mYieldFee)));

        vm.prank(alice);
        swapFacility.swap(address(mYieldToOne), address(mYieldFee), 10e6, alice);

        vm.prank(admin);
        swapFacility.setPermissionedExtension(address(mYieldFee), false);

        vm.prank(alice);
        swapFacility.swap(address(mYieldToOne), address(mYieldFee), 10e6 - 4, alice);

        assertEq(mYieldFee.balanceOf(alice), 10e6 - 2, "mYieldFee balance should be 10e6 - 4");
    }

    function test_swapAdapter_withMultipleExtensions() public {
        // Test TOKEN -> USDC -> USDT -> WrappedM -> Extension

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(address(swapAdapter), true, 0);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(address(swapAdapter), true);

        vm.startPrank(alice);

        // Approve swap adapter for all tokens
        IERC20(USDC).approve(address(swapAdapter), type(uint256).max);
        USDT.call(abi.encodeWithSelector(IERC20.approve.selector, address(swapAdapter), type(uint256).max));

        // Approve swap facility for all extensions
        mToken.approve(address(swapFacility), type(uint256).max);
        wrappedM.approve(address(swapFacility), type(uint256).max);
        mYieldToOne.approve(address(swapFacility), type(uint256).max);
        mYieldFee.approve(address(swapFacility), type(uint256).max);
        mEarnerManager.approve(address(swapFacility), type(uint256).max);

        // Approve swap adapter for all extensions
        mYieldToOne.approve(address(swapAdapter), type(uint256).max);
        mYieldFee.approve(address(swapAdapter), type(uint256).max);
        mEarnerManager.approve(address(swapAdapter), type(uint256).max);
        wrappedM.approve(address(swapAdapter), type(uint256).max);

        vm.stopPrank();

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mYieldToOne), 10e6, alice);

        assertEq(mYieldToOne.getBalanceOf(alice), 10e6, "mYieldToOne balance should be 10e6");

        vm.prank(alice);
        swapAdapter.swapOut(address(mYieldToOne), 10e6 - 2, USDC, 0, alice, "");

        uint256 usdcBalance = IERC20(USDC).balanceOf(alice);

        assertEq(usdcBalance, 9999631, "USDC balance of alice should be 9999631");

        vm.prank(alice);
        swapAdapter.swapIn(USDC, usdcBalance, address(mYieldToOne), 0, alice, "");

        uint256 yieldToOneBalance = mYieldToOne.getBalanceOf(alice);

        assertEq(yieldToOneBalance, 9997997, "mYieldToOne balance of alice should be 10e6");

        // Encode path for USDT -> USDC -> Wrapped M
        bytes memory path = abi.encodePacked(
            WRAPPED_M,
            uint24(100), // 0.01% fee
            USDC,
            uint24(100), // 0.01% fee
            USDT
        );

        vm.prank(alice);
        swapAdapter.swapOut(address(mYieldToOne), yieldToOneBalance - 4, USDT, 0, alice, path);

        uint256 usdtBalance = IERC20(USDT).balanceOf(alice);

        assertEq(usdtBalance, 9995377, "usdt balance should be 9995377");

        path = abi.encodePacked(
            USDT,
            uint24(100), // 0.01% fee
            USDC,
            uint24(100), // 0.01% fee
            WRAPPED_M
        );

        vm.prank(alice);
        swapAdapter.swapIn(USDT, usdtBalance, address(mYieldFee), 0, alice, path);

        uint256 mYieldFeeBalance = mYieldFee.balanceOf(alice);

        assertEq(mYieldFeeBalance, 9993988, "mYieldFeeBalance should be 9993988");
    }

    function test_yieldToOne_freeze_duringYield() public {
        vm.startPrank(alice);
        mToken.approve(address(swapFacility), type(uint256).max);
        mYieldToOne.approve(address(swapFacility), type(uint256).max);
        vm.stopPrank();

        vm.prank(alice);
        mYieldToOne.approve(bob, suint256(10e6));

        vm.prank(bob);
        mToken.approve(address(swapFacility), 10e6);

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mYieldToOne), 10e6, alice);

        uint256 mYieldToOneBalance = mYieldToOne.getBalanceOf(alice);

        assertEq(mYieldToOneBalance, 10e6, "mYieldToOneBalance should be 10e6");

        uint256 mBalanceBefore = mToken.balanceOf(address(mYieldToOne));

        vm.warp(vm.getBlockTimestamp() + 10 days);

        uint256 mBalanceAfter = mToken.balanceOf(address(mYieldToOne));

        uint256 mYieldToOneYield = mYieldToOne.yield();

        assertEq(mYieldToOneYield, mBalanceAfter - mBalanceBefore - 2, "yield should match increase in m balance");

        vm.expectEmit(true, true, true, true);
        emit IFreezable.Frozen(alice, vm.getBlockTimestamp());

        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        mBalanceAfter = mToken.balanceOf(address(mYieldToOne));

        mYieldToOneYield = mYieldToOne.yield();

        assertEq(mYieldToOneYield, mBalanceAfter - mBalanceBefore - 2, "yield should match increase in m balance");

        mYieldToOne.claimYield();

        assertEq(
            mYieldToOne.getBalanceOf(yieldRecipient),
            mBalanceAfter - mBalanceBefore - 2,
            "yield should be claimed to yield recipient"
        );

        // Test all freeze revertions except for transfer to alice (will test at end)
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swap(address(mYieldToOne), address(mYieldFee), 10e6 - 2, alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldToOne.transfer(bob, suint256(10e6));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldToOne.approve(bob, suint256(10e6));

        vm.stopPrank();

        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldToOne.transferFrom(alice, bob, suint256(10e6));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        swapFacility.swap(address(mToken), address(mYieldToOne), 10e6, alice);

        vm.stopPrank();

        vm.prank(freezeManager);
        mYieldToOne.unfreeze(alice);

        mBalanceBefore = mBalanceAfter;

        vm.warp(vm.getBlockTimestamp() + 10 days);

        mBalanceAfter = mToken.balanceOf(address(mYieldToOne));

        mYieldToOneYield = mYieldToOne.yield();

        assertEq(
            mYieldToOneYield,
            mBalanceAfter - mBalanceBefore,
            "yield should match increase in m balance after unfreeze"
        );

        // Re-freeze again to test transfer from bob to frozen alice
        vm.prank(freezeManager);
        mYieldToOne.freeze(alice);

        vm.startPrank(bob);
        swapFacility.swap(address(mToken), address(mYieldToOne), 10e6, bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        mYieldToOne.transfer(alice, suint256(10e6));
    }

    function test_mEarnerManager_whitelistManagement_withActivePositions() public {
        vm.startPrank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 10_000);
        mEarnerManager.setAccountInfo(bob, true, 5_000);
        mEarnerManager.setAccountInfo(carol, true, 0);
        vm.stopPrank();

        vm.startPrank(alice);
        mToken.approve(address(swapFacility), type(uint256).max);
        mEarnerManager.approve(address(swapFacility), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        mToken.approve(address(swapFacility), type(uint256).max);
        mEarnerManager.approve(address(swapFacility), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(carol);
        mToken.approve(address(swapFacility), type(uint256).max);
        mEarnerManager.approve(address(swapFacility), type(uint256).max);
        vm.stopPrank();

        vm.prank(alice);
        swapFacility.swap(address(mToken), address(mEarnerManager), 10e6, alice);

        vm.prank(bob);
        swapFacility.swap(address(mToken), address(mEarnerManager), 10e6, bob);

        vm.prank(carol);
        swapFacility.swap(address(mToken), address(mEarnerManager), 10e6, carol);

        uint256 aliceBalance = mEarnerManager.balanceOf(alice);
        uint256 bobBalance = mEarnerManager.balanceOf(bob);
        uint256 carolBalance = mEarnerManager.balanceOf(carol);

        uint112 alicePrincipal = _calcMPrincipalAmountRoundedDown(10e6);
        uint112 bobPrincipal = _calcMPrincipalAmountRoundedDown(10e6);
        uint112 carolPrincipal = _calcMPrincipalAmountRoundedDown(10e6);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        (uint256 bobYieldWithFeeActual, , ) = mEarnerManager.accruedYieldAndFeeOf(bob);

        (uint256 carolYieldWithFeeActual, , ) = mEarnerManager.accruedYieldAndFeeOf(carol);

        {
            (uint256 aliceYieldWithFeeActual, uint256 aliceFee, uint256 aliceYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(alice);
            uint256 aliceYieldWithFee = _calcMEarnerManagerYield(aliceBalance, alicePrincipal);

            assertApproxEqAbs(aliceYieldWithFeeActual, aliceYieldWithFee, 2, "alice's yield with fee should be 11375");
            assertApproxEqAbs(aliceFee, aliceYieldWithFee, 2, "alice's fee should be 11375");
            assertApproxEqAbs(aliceYieldNetOfFee, 0, 2, "alice's yield net of fee should be 0");
        }

        {
            (uint256 bobYieldWithFeeActual, uint256 bobFee, uint256 bobYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(bob);

            uint256 bobYieldWithFee = _calcMEarnerManagerYield(bobBalance, bobPrincipal);

            assertApproxEqAbs(bobYieldWithFeeActual, bobYieldWithFee, 2, "bob's yield with fee should be 11375");
            assertApproxEqAbs(bobFee, bobYieldWithFee / 2, 2, "bob's fee should be 11375 / 2");
            assertApproxEqAbs(bobYieldNetOfFee, bobYieldWithFee / 2, 2, "bob's yield net of fee should be 11375 / 2");
        }

        {
            (uint256 carolYieldWithFeeActual, uint256 carolFee, uint256 carolYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(carol);

            uint256 carolYieldWithFee = _calcMEarnerManagerYield(carolBalance, carolPrincipal);

            assertApproxEqAbs(carolYieldWithFeeActual, carolYieldWithFee, 2, "carol's yield with fee should be 11375");
            assertApproxEqAbs(carolFee, 0, 2, "carol's fee should be 0");
            assertApproxEqAbs(carolYieldNetOfFee, carolYieldWithFee, 2, "carol's yield net of fee should be 11375");
        }

        vm.startPrank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 5_000);
        mEarnerManager.setAccountInfo(bob, true, 0);
        mEarnerManager.setAccountInfo(carol, true, 10_000);
        vm.stopPrank();

        aliceBalance = mEarnerManager.balanceOf(alice);
        bobBalance = mEarnerManager.balanceOf(bob);
        carolBalance = mEarnerManager.balanceOf(carol);

        alicePrincipal = _calcMPrincipalAmountRoundedDown(aliceBalance);
        bobPrincipal = _calcMPrincipalAmountRoundedDown(bobBalance);
        carolPrincipal = _calcMPrincipalAmountRoundedDown(carolBalance);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        {
            (uint256 aliceYieldWithFeeActual, uint256 aliceFee, uint256 aliceYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(alice);
            uint256 aliceYieldWithFee = _calcMEarnerManagerYield(aliceBalance, alicePrincipal);

            assertApproxEqAbs(aliceYieldWithFeeActual, aliceYieldWithFee, 2, "alice's yield with fee should be 11375");
            assertApproxEqAbs(aliceFee, aliceYieldWithFee / 2, 2, "alice's fee should be 11375 / 2");
            assertApproxEqAbs(
                aliceYieldNetOfFee,
                aliceYieldWithFee / 2,
                2,
                "alice's yield net of fee should be 11375 / 2"
            );
        }

        {
            (uint256 bobYieldWithFeeActual, uint256 bobFee, uint256 bobYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(bob);

            uint256 bobYieldWithFee = _calcMEarnerManagerYield(bobBalance, bobPrincipal);

            assertApproxEqAbs(bobYieldWithFeeActual, bobYieldWithFee, 2, "bob's yield with fee should be 11375");
            assertApproxEqAbs(bobFee, 0, 2, "bob's fee should be 11375 / 2");
            assertApproxEqAbs(bobYieldNetOfFee, bobYieldWithFee, 2, "bob's yield net of fee should be 11375 / 2");
        }

        {
            (uint256 carolYieldWithFeeActual, uint256 carolFee, uint256 carolYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(carol);

            uint256 carolYieldWithFee = _calcMEarnerManagerYield(carolBalance, carolPrincipal);

            assertApproxEqAbs(carolYieldWithFeeActual, carolYieldWithFee, 2, "carol's yield with fee should be 11375");
            assertApproxEqAbs(carolFee, carolYieldWithFee, 2, "carol's fee should be 11375");
            assertApproxEqAbs(carolYieldNetOfFee, 0, 2, "carol's yield net of fee should be 0");
        }

        vm.startPrank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 0);
        mEarnerManager.setAccountInfo(bob, true, 10_000);
        mEarnerManager.setAccountInfo(carol, true, 5_000);
        vm.stopPrank();

        aliceBalance = mEarnerManager.balanceOf(alice);
        bobBalance = mEarnerManager.balanceOf(bob);
        carolBalance = mEarnerManager.balanceOf(carol);

        alicePrincipal = _calcMPrincipalAmountRoundedDown(aliceBalance);
        bobPrincipal = _calcMPrincipalAmountRoundedDown(bobBalance);
        carolPrincipal = _calcMPrincipalAmountRoundedDown(carolBalance);

        {
            (uint256 aliceYieldWithFeeActual, uint256 aliceFee, uint256 aliceYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(alice);
            uint256 aliceYieldWithFee = _calcMEarnerManagerYield(aliceBalance, alicePrincipal);

            assertApproxEqAbs(aliceYieldWithFeeActual, aliceYieldWithFee, 2, "alice's yield with fee should be 11375");
            assertApproxEqAbs(aliceFee, 0, 2, "alice's fee should be 0");
            assertApproxEqAbs(aliceYieldNetOfFee, aliceYieldWithFee, 2, "alice's yield net of fee should be 11375");
        }

        {
            (uint256 bobYieldWithFeeActual, uint256 bobFee, uint256 bobYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(bob);

            uint256 bobYieldWithFee = _calcMEarnerManagerYield(bobBalance, bobPrincipal);

            assertApproxEqAbs(bobYieldWithFeeActual, bobYieldWithFee, 2, "bob's yield with fee should be 11375");
            assertApproxEqAbs(bobFee, bobYieldWithFee, 2, "bob's fee should be 11375");
            assertApproxEqAbs(bobYieldNetOfFee, 0, 2, "bob's yield net of fee should be 0");
        }

        {
            (uint256 carolYieldWithFeeActual, uint256 carolFee, uint256 carolYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(carol);

            uint256 carolYieldWithFee = _calcMEarnerManagerYield(carolBalance, carolPrincipal);

            assertApproxEqAbs(carolYieldWithFeeActual, carolYieldWithFee, 2, "carol's yield with fee should be 11375");
            assertApproxEqAbs(carolFee, carolYieldWithFee / 2, 2, "carol's fee should be 11375 / 2");
            assertApproxEqAbs(
                carolYieldNetOfFee,
                carolYieldWithFee / 2,
                2,
                "carol's yield net of fee should be 11375 / 2"
            );
        }

        mEarnerManager.claimFor(alice);
        mEarnerManager.claimFor(bob);
        mEarnerManager.claimFor(carol);

        assertApproxEqAbs(
            mEarnerManager.balanceOf(feeRecipient),
            11375 * 3,
            14,
            "earnerManager's balance should be 11375 * 3"
        );

        vm.startPrank(earnerManager);
        mEarnerManager.setAccountInfo(alice, false, 0);
        mEarnerManager.setAccountInfo(bob, false, 0);
        mEarnerManager.setAccountInfo(carol, false, 0);
        vm.stopPrank();

        aliceBalance = mEarnerManager.balanceOf(alice);
        bobBalance = mEarnerManager.balanceOf(bob);
        carolBalance = mEarnerManager.balanceOf(carol);

        alicePrincipal = _calcMPrincipalAmountRoundedDown(aliceBalance);
        bobPrincipal = _calcMPrincipalAmountRoundedDown(bobBalance);
        carolPrincipal = _calcMPrincipalAmountRoundedDown(carolBalance);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        {
            (uint256 aliceYieldWithFeeActual, uint256 aliceFee, uint256 aliceYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(alice);
            uint256 aliceYieldWithFee = _calcMEarnerManagerYield(aliceBalance, alicePrincipal);

            assertApproxEqAbs(aliceYieldWithFeeActual, aliceYieldWithFee, 2, "alice's yield with fee should be 11375");
            assertApproxEqAbs(aliceFee, aliceYieldWithFee, 2, "alice's fee should be 11375");
            assertApproxEqAbs(aliceYieldNetOfFee, 0, 2, "alice's yield net of fee should be 0");
        }

        {
            (uint256 bobYieldWithFeeActual, uint256 bobFee, uint256 bobYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(bob);

            uint256 bobYieldWithFee = _calcMEarnerManagerYield(bobBalance, bobPrincipal);

            assertApproxEqAbs(bobYieldWithFeeActual, bobYieldWithFee, 2, "bob's yield with fee should be 11375");
            assertApproxEqAbs(bobFee, bobYieldWithFee, 2, "bob's fee should be 11375");
            assertApproxEqAbs(bobYieldNetOfFee, 0, 2, "bob's yield net of fee should be 0");
        }

        {
            (uint256 carolYieldWithFeeActual, uint256 carolFee, uint256 carolYieldNetOfFee) = mEarnerManager
                .accruedYieldAndFeeOf(carol);

            uint256 carolYieldWithFee = _calcMEarnerManagerYield(carolBalance, carolPrincipal);

            assertApproxEqAbs(carolYieldWithFeeActual, carolYieldWithFee, 2, "carol's yield with fee should be 11375");
            assertApproxEqAbs(carolFee, carolYieldWithFee, 2, "carol's fee should be 11375");
            assertApproxEqAbs(carolYieldNetOfFee, 0, 2, "carol's yield net of fee should be 0");
        }

        vm.startPrank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 10_000);
        mEarnerManager.setAccountInfo(bob, true, 10_000);
        mEarnerManager.setAccountInfo(carol, true, 10_000);
        vm.stopPrank();

        assertApproxEqAbs(
            mEarnerManager.balanceOf(feeRecipient),
            11375 * 6,
            56,
            "earnerManager's balance should be 11375 * 6"
        );
    }

    function test_zeroYieldScenarios() public {
        vm.startPrank(alice);
        mToken.approve(address(swapFacility), 10e6);
        mYieldFee.approve(address(swapFacility), 10e6);
        mYieldToOne.approve(address(swapFacility), 10e6);
        mEarnerManager.approve(address(swapFacility), 10e6);
        wrappedM.approve(address(swapFacility), 10e6);
        vm.stopPrank();

        // set rate to zero and ensure no yield
        // accumulates during swaps with time in between

        _set("base_minter_rate", bytes32(uint256(0))); // zero rate
        _set("max_earner_rate", bytes32(uint256(0))); // zero rate

        minterGateway.updateIndex();
        mIndexInitial = mToken.updateIndex();
        mYieldFeeIndexInitial = mYieldFee.updateIndex();

        vm.startPrank(alice);

        mToken.approve(address(swapFacility), 5e6);
        swapFacility.swap(address(mToken), address(mYieldFee), 5e6, alice);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        mYieldFee.approve(address(swapFacility), 5e6);
        swapFacility.swap(address(mYieldFee), address(mYieldToOne), 5e6 - 2, alice);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        mYieldToOne.approve(address(swapFacility), 5e6);
        swapFacility.swap(address(mYieldToOne), address(mEarnerManager), 5e6 - 4, alice);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        mEarnerManager.approve(address(swapFacility), 5e6);
        swapFacility.swap(address(mEarnerManager), address(mToken), 5e6 - 6, alice);

        vm.stopPrank();

        uint256 mYieldToOneYield = mYieldToOne.yield();
        uint256 mYieldFeeYield = mYieldFee.totalAccruedYield();
        uint256 mEarnerManagerYield = mEarnerManager.accruedYieldOf(alice);

        assertEq(mYieldToOneYield, 0, "mYieldToOne yield should be 0");
        assertEq(mYieldFeeYield, 0, "mYieldFee yield should be 0");
        assertEq(mEarnerManagerYield, 0, "mEarnerManager yield should be 0");

        // Set rate to non-zero and ensure no yield accumulates
        // during atomic swaps without any time passage

        _set("base_minter_rate", bytes32(uint256(1000))); // 10% rate
        _set("max_earner_rate", bytes32(uint256(1000))); // 10% rate

        minterGateway.updateIndex();
        mIndexInitial = mToken.updateIndex();
        mYieldFeeIndexInitial = mYieldFee.updateIndex();

        vm.startPrank(alice);

        mToken.approve(address(swapFacility), 5e6);
        swapFacility.swap(address(mToken), address(mYieldFee), 5e6, alice);

        mYieldFee.approve(address(swapFacility), 5e6);
        swapFacility.swap(address(mYieldFee), address(mYieldToOne), 5e6 - 2, alice);

        mYieldToOne.approve(address(swapFacility), 5e6);
        swapFacility.swap(address(mYieldToOne), address(mEarnerManager), 5e6 - 4, alice);

        mEarnerManager.approve(address(swapFacility), 5e6);
        swapFacility.swap(address(mEarnerManager), address(mToken), 5e6 - 6, alice);

        vm.stopPrank();

        mYieldToOneYield = mYieldToOne.yield();
        mYieldFeeYield = mYieldFee.totalAccruedYield();
        mEarnerManagerYield = mEarnerManager.accruedYieldOf(alice);

        assertEq(mYieldToOneYield, 0, "mYieldToOne yield should be 0");
        assertEq(mYieldFeeYield, 0, "mYieldFee yield should be 0");
        assertEq(mEarnerManagerYield, 0, "mEarnerManager yield should be 0");
    }

    function test_rateOracle_changes() public {
        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 0);

        vm.startPrank(alice);
        mToken.approve(address(swapFacility), type(uint256).max);
        mYieldFee.approve(address(swapFacility), type(uint256).max);
        mYieldToOne.approve(address(swapFacility), type(uint256).max);
        mEarnerManager.approve(address(swapFacility), type(uint256).max);
        wrappedM.approve(address(swapFacility), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(alice);
        swapFacility.swap(address(mToken), address(mYieldToOne), 5e6, alice);
        swapFacility.swap(address(mToken), address(mYieldFee), 5e6, alice);
        swapFacility.swap(address(mToken), address(mEarnerManager), 5e6, alice);
        vm.stopPrank();

        uint256 mYieldToOneBalance = 5e6;
        uint256 mYieldFeeBalance = 5e6;
        uint256 mEarnerManagerBalance = 5e6;

        uint112 mYieldFeePrincipal = _calcMYieldFeePrincipal(mYieldFeeBalance);
        uint112 mYieldToOnePrincipal = _calcMPrincipalAmountRoundedDown(mEarnerManagerBalance);
        uint112 mEarnerManagerPrincipal = _calcMPrincipalAmountRoundedDown(mYieldToOneBalance);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        uint256 mYieldFeeAccruedPreRateChange = _calcMYieldFeeYield(mYieldFeeBalance, mYieldFeePrincipal);
        uint256 mYieldToOneAccruedPreRateChange = _calcMPresentAmountRoundedDown(mYieldToOnePrincipal) -
            mYieldFeeBalance;
        uint256 mEarnerManagerAccruedPreRateChange = _calcMEarnerManagerYield(5e6, mEarnerManagerPrincipal);

        assertApproxEqAbs(
            mYieldFee.totalAccruedYield(),
            mYieldFeeAccruedPreRateChange,
            1,
            "mYieldFee yield not expected"
        );
        assertApproxEqAbs(mYieldToOne.yield(), mYieldToOneAccruedPreRateChange, 0, "mYieldToOne yield not expected");
        assertApproxEqAbs(
            mEarnerManager.accruedYieldOf(alice),
            mEarnerManagerAccruedPreRateChange,
            1,
            "mEarnerManager yield not expected"
        );

        _set("base_minter_rate", bytes32(uint256(830))); // double rate
        _set("max_earner_rate", bytes32(uint256(830))); // double rate

        minterGateway.updateIndex();
        mIndexInitial = mToken.updateIndex();
        mYieldFeeIndexInitial = mYieldFee.updateIndex();

        mRate = 830;
        mRateStart = uint40(vm.getBlockTimestamp());

        vm.warp(vm.getBlockTimestamp() + 10 days);

        uint256 mYieldFeeAccruedPostRateChange = _calcMYieldFeeYield(
            mYieldFeeBalance + mYieldFeeAccruedPreRateChange,
            mYieldFeePrincipal
        );
        uint256 mYieldToOneAccruedPostRateChange = _calcMPresentAmountRoundedDown(mYieldToOnePrincipal) -
            mYieldFeeBalance;
        uint256 mEarnerManagerAccruedPostRateChange = _calcMEarnerManagerYield(5e6, mEarnerManagerPrincipal);

        assertApproxEqAbs(
            mYieldFee.totalAccruedYield(),
            mYieldFeeAccruedPostRateChange + mYieldFeeAccruedPreRateChange,
            13,
            "mYieldFee !!yield not expected"
        );
        assertApproxEqAbs(
            mYieldToOne.yield(),
            mYieldToOneAccruedPreRateChange * 3,
            22,
            "mYieldToOne yield not expected"
        );
        assertApproxEqAbs(
            mEarnerManager.accruedYieldOf(alice),
            mEarnerManagerAccruedPreRateChange * 3,
            19,
            "mEarnerManager yield not expected"
        );
    }

    function test_roleInteractions_complex() public {
        vm.startPrank(alice);
        mToken.approve(address(swapFacility), type(uint256).max);
        mYieldFee.approve(address(swapFacility), type(uint256).max);
        mYieldToOne.approve(address(swapFacility), type(uint256).max);
        mEarnerManager.approve(address(swapFacility), type(uint256).max);
        wrappedM.approve(address(swapFacility), type(uint256).max);
        vm.stopPrank();

        // Test scenarios where users have multiple roles
        // Test role changes during active operations
        address multiRoleUser = makeAddr("multiRoleUser");

        vm.startPrank(admin);

        mYieldToOne.grantRole(DEFAULT_ADMIN_ROLE, multiRoleUser);
        mYieldToOne.grantRole(YIELD_RECIPIENT_MANAGER_ROLE, multiRoleUser);

        mYieldFee.grantRole(DEFAULT_ADMIN_ROLE, multiRoleUser);
        mYieldFee.grantRole(FEE_MANAGER_ROLE, multiRoleUser);
        mYieldFee.grantRole(CLAIM_RECIPIENT_MANAGER_ROLE, multiRoleUser);

        mEarnerManager.grantRole(DEFAULT_ADMIN_ROLE, multiRoleUser);
        mEarnerManager.grantRole(EARNER_MANAGER_ROLE, multiRoleUser);

        swapFacility.grantRole(DEFAULT_ADMIN_ROLE, multiRoleUser);

        vm.stopPrank();

        vm.startPrank(multiRoleUser);

        // As YIELD_RECIPIENT_MANAGER
        mYieldToOne.setYieldRecipient(alice);
        assertEq(mYieldToOne.yieldRecipient(), alice);

        // As FEE_MANAGER
        mYieldFee.setFeeRate(1500); // 15% fee
        assertEq(mYieldFee.feeRate(), 1500);

        // As CLAIM_RECIPIENT_MANAGER
        mYieldFee.setClaimRecipient(alice, bob);
        assertEq(mYieldFee.claimRecipientFor(alice), bob);

        // As EARNER_MANAGER
        mEarnerManager.setAccountInfo(alice, true, 2000); // 20% fee
        assertTrue(mEarnerManager.isWhitelisted(alice));

        mEarnerManager.setFeeRecipient(alice);
        assertTrue(mEarnerManager.feeRecipient() == alice);

        // As DEFAULT_ADMIN on SwapFacility
        swapFacility.setPermissionedExtension(address(mYieldFee), true);
        assertTrue(swapFacility.isPermissionedExtension(address(mYieldFee)));

        swapFacility.setPermissionedMSwapper(address(mYieldFee), alice, true);

        vm.stopPrank();

        vm.startPrank(alice);
        swapFacility.swap(address(mToken), address(mYieldFee), 5e6, alice);
        swapFacility.swap(address(mToken), address(mYieldToOne), 5e6, alice);
        swapFacility.swap(address(mToken), address(mEarnerManager), 5e6, alice);
        vm.stopPrank();

        // Warp time to accrue yield
        vm.warp(block.timestamp + 10 days);

        vm.prank(admin);
        mYieldToOne.revokeRole(YIELD_RECIPIENT_MANAGER_ROLE, multiRoleUser);

        uint256 yieldAfter = mYieldToOne.yield();
        assertTrue(yieldAfter > 0, "Should have accrued yield despite role change");

        vm.prank(multiRoleUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                multiRoleUser,
                YIELD_RECIPIENT_MANAGER_ROLE
            )
        );
        mYieldToOne.setYieldRecipient(bob);

        vm.prank(admin);
        mYieldToOne.revokeRole(DEFAULT_ADMIN_ROLE, multiRoleUser);

        vm.prank(multiRoleUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                multiRoleUser,
                DEFAULT_ADMIN_ROLE
            )
        );
        mYieldToOne.grantRole(YIELD_RECIPIENT_MANAGER_ROLE, multiRoleUser);

        // Remove FEE_MANAGER role from multiRoleUser while yield is accruing
        vm.prank(admin);
        mYieldFee.revokeRole(FEE_MANAGER_ROLE, multiRoleUser);

        // Verify multiRoleUser can no longer change fee rate
        vm.prank(multiRoleUser);
        vm.expectRevert();
        mYieldFee.setFeeRate(2000);

        // But can still perform other role functions
        vm.prank(multiRoleUser);
        mYieldFee.setClaimRecipient(carol, david);
        assertEq(mYieldFee.claimRecipientFor(carol), david);

        vm.prank(admin);
        mYieldFee.revokeRole(CLAIM_RECIPIENT_MANAGER_ROLE, multiRoleUser);

        vm.prank(multiRoleUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                multiRoleUser,
                CLAIM_RECIPIENT_MANAGER_ROLE
            )
        );
        mYieldFee.setClaimRecipient(carol, bob);

        vm.prank(admin);
        mYieldFee.revokeRole(CLAIM_RECIPIENT_MANAGER_ROLE, multiRoleUser);

        vm.prank(multiRoleUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                multiRoleUser,
                CLAIM_RECIPIENT_MANAGER_ROLE
            )
        );
        mYieldFee.setClaimRecipient(carol, bob);

        vm.prank(admin);
        mYieldFee.revokeRole(DEFAULT_ADMIN_ROLE, multiRoleUser);

        vm.prank(multiRoleUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                multiRoleUser,
                DEFAULT_ADMIN_ROLE
            )
        );
        mYieldFee.grantRole(CLAIM_RECIPIENT_MANAGER_ROLE, multiRoleUser);

        yieldAfter = mYieldFee.accruedYieldOf(alice);
        assertTrue(yieldAfter > 0, "Should have accrued yield");

        vm.prank(admin);
        mEarnerManager.revokeRole(EARNER_MANAGER_ROLE, multiRoleUser);

        vm.prank(multiRoleUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                multiRoleUser,
                EARNER_MANAGER_ROLE
            )
        );
        mEarnerManager.setAccountInfo(bob, true, 1000);

        vm.prank(admin);
        mEarnerManager.revokeRole(DEFAULT_ADMIN_ROLE, multiRoleUser);

        vm.prank(multiRoleUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                multiRoleUser,
                DEFAULT_ADMIN_ROLE
            )
        );
        mEarnerManager.grantRole(EARNER_MANAGER_ROLE, multiRoleUser);

        yieldAfter = mEarnerManager.accruedYieldOf(alice);
        assertTrue(yieldAfter > 0, "Should have accrued yield");
    }

    function _calcMEarnerManagerYield(uint256 balance, uint112 principal) public view returns (uint256) {
        uint128 currentIndex = _currentMIndex();

        uint256 balanceWithYield = IndexingMath.getPresentAmountRoundedUp(principal, currentIndex);

        // Yield is the difference between present value and current balance
        return balanceWithYield > balance ? balanceWithYield - balance : 0;
    }

    function _calcMYieldFeePrincipal(uint256 amount) public view returns (uint112) {
        uint128 _index = _currentMYieldFeeIndex();

        return IndexingMath.getPrincipalAmountRoundedUp(uint240(amount), _index);
    }

    function _calcMYieldFeeYield(uint256 priorAmount, uint112 _principal) public view returns (uint256) {
        uint128 _index = _currentMYieldFeeIndex();

        uint256 _amountPlusYield = IndexingMath.getPresentAmountRoundedUp(_principal, _index);

        return _amountPlusYield - priorAmount;
    }

    function _currentMYieldFeeIndex() public view returns (uint128) {
        unchecked {
            return
                // NOTE: Cap the index to `type(uint128).max` to prevent overflow in present value math.
                UIntMath.bound128(
                    ContinuousIndexingMath.multiplyIndicesDown(
                        mYieldFeeIndexInitial,
                        ContinuousIndexingMath.getContinuousIndex(
                            ContinuousIndexingMath.convertFromBasisPoints(mYieldFeeRate),
                            uint32(vm.getBlockTimestamp() - mYieldFeeIndexStart)
                        )
                    )
                );
        }
    }

    function _calcMPrincipalAmountRoundedUp(uint256 amount) public view returns (uint112) {
        uint128 _index = _currentMIndex();

        return IndexingMath.getPrincipalAmountRoundedUp(uint240(amount), _index);
    }

    function _calcMPrincipalAmountRoundedDown(uint256 amount) public view returns (uint112) {
        uint128 _index = _currentMIndex();

        return IndexingMath.getPrincipalAmountRoundedDown(uint240(amount), _index);
    }

    function _calcMPresentAmountRoundedDown(uint112 amount) public view returns (uint240) {
        uint128 _index = _currentMIndex();

        return IndexingMath.getPresentAmountRoundedDown(amount, _index);
    }

    function _calcMYieldFeePresentAmountRoundedDown(uint112 amount) public view returns (uint240) {
        uint128 _index = _currentMYieldFeeIndex();

        return IndexingMath.getPresentAmountRoundedDown(amount, _index);
    }

    function _currentMIndex() public view returns (uint128) {
        unchecked {
            return
                // NOTE: Cap the index to `type(uint128).max` to prevent overflow in present value math.
                UIntMath.bound128(
                    ContinuousIndexingMath.multiplyIndicesDown(
                        mIndexInitial,
                        ContinuousIndexingMath.getContinuousIndex(
                            ContinuousIndexingMath.convertFromBasisPoints(mRate),
                            uint32(block.timestamp - mRateStart)
                        )
                    )
                );
        }
    }

    function _testYieldCapture_mYieldToOne(
        address from,
        uint256[] memory yields,
        uint256 amount
    ) public returns (uint256, uint256[] memory) {
        vm.prank(alice);
        if (from == address(mToken)) swapFacility.swap(address(mToken), address(mYieldToOne), amount, alice);
        else swapFacility.swap(from, address(mYieldToOne), amount, alice);

        // Prep MEarnerManager
        uint112 mEarnerManagerPrincipal = yields[M_EARNER_MANAGER] == 0
            ? 0
            : _calcMPrincipalAmountRoundedDown(yields[M_EARNER_MANAGER]);

        // Prep MYieldFee
        uint112 mYieldFeePrincipal = yields[M_YIELD_FEE] == 0 ? 0 : _calcMYieldFeePrincipal(yields[M_YIELD_FEE]);

        // Prep MYieldToOne
        uint256 mBalanceBefore = mToken.balanceOf(address(mYieldToOne));

        vm.warp(vm.getBlockTimestamp() + 10 days);

        // Collect MEarnerManager yield
        yields[M_EARNER_MANAGER] += mEarnerManagerPrincipal == 0
            ? 0
            : _calcMEarnerManagerYield(yields[M_EARNER_MANAGER], mEarnerManagerPrincipal);

        // Collect MYieldFee yield
        yields[M_YIELD_FEE] += mYieldFeePrincipal == 0
            ? 0
            : _calcMYieldFeeYield(yields[M_YIELD_FEE], mYieldFeePrincipal);

        // Assert MYieldToOne yield
        uint256 mBalanceAfter = mToken.balanceOf(address(mYieldToOne));

        uint256 mYieldToOneYield = mYieldToOne.yield();

        uint256 priorYield = yields[0];

        uint256 yield = mBalanceAfter - mBalanceBefore;

        assertApproxEqAbs(mYieldToOneYield, yield + priorYield, 50, "Should have accrued yield in mYieldToOne");

        yields[0] += yield;

        return (priorYield == 0 ? amount - 2 : amount, yields);
    }

    function _testYieldCapture_mYieldFee(
        address from,
        uint256[] memory yields,
        uint256 amount
    ) public returns (uint256, uint256[] memory) {
        vm.prank(alice);

        swapFacility.swap(from, address(mYieldFee), amount, alice);

        // Prep MEarnerManager
        uint112 mEarnerManagerPrincipal = yields[M_EARNER_MANAGER] == 0
            ? 0
            : _calcMPrincipalAmountRoundedDown(yields[M_EARNER_MANAGER]);

        // Prep MYieldToOne
        uint256 mBalanceBefore = mToken.balanceOf(address(mYieldToOne));

        // Prep MYieldFee
        uint112 _principal = _calcMYieldFeePrincipal(amount + yields[M_YIELD_FEE]);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        // Collect MEarnerManager yield
        yields[M_EARNER_MANAGER] += mEarnerManagerPrincipal == 0
            ? 0
            : _calcMEarnerManagerYield(yields[M_EARNER_MANAGER], mEarnerManagerPrincipal);

        // Collect MYieldToOne yield
        yields[M_YIELD_TO_ONE] += mBalanceBefore == 0 ? 0 : mToken.balanceOf(address(mYieldToOne)) - mBalanceBefore;

        // Collect MYieldFee yield
        uint256 priorYield = yields[M_YIELD_FEE];

        yields[M_YIELD_FEE] += _calcMYieldFeeYield(amount + yields[M_YIELD_FEE], _principal);

        uint256 mYieldFeeYield = mYieldFee.accruedYieldOf(alice);

        assertApproxEqAbs(mYieldFeeYield, yields[M_YIELD_FEE], 50, "Should have accrued yield in mYieldFee");

        return (priorYield == 0 ? amount - 2 : amount, yields);
    }

    function _testYieldCapture_mEarnerManager(
        address from,
        uint256[] memory yields,
        uint256 amount
    ) public returns (uint256, uint256[] memory) {
        vm.prank(alice);
        swapFacility.swap(from, address(mEarnerManager), amount, alice);

        // Prep MYieldFee
        uint112 mYieldFeePrincipal = yields[M_YIELD_FEE] == 0 ? 0 : _calcMYieldFeePrincipal(yields[M_YIELD_FEE]);

        // Prep MYieldToOne
        uint256 mBalanceBefore = yields[M_YIELD_TO_ONE] == 0 ? 0 : mToken.balanceOf(address(mYieldToOne));

        // Prep MEarnerManager
        uint112 principal = _calcMPrincipalAmountRoundedDown(amount + yields[M_EARNER_MANAGER]);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        // Collect MYieldFee yield
        yields[M_YIELD_FEE] += mYieldFeePrincipal == 0
            ? 0
            : _calcMYieldFeeYield(yields[M_YIELD_FEE], mYieldFeePrincipal);

        // Collect MYieldToOne yield
        yields[M_YIELD_TO_ONE] += mBalanceBefore == 0 ? 0 : mToken.balanceOf(address(mYieldToOne)) - mBalanceBefore;

        // Assert MEarnerManager yield
        uint256 yield = _calcMEarnerManagerYield(amount + yields[M_EARNER_MANAGER], principal);

        (uint256 aliceYieldWithFee, uint256 aliceFee, uint256 aliceYield) = mEarnerManager.accruedYieldAndFeeOf(alice);

        uint256 priorYield = yields[M_EARNER_MANAGER];

        yields[M_EARNER_MANAGER] += yield;

        assertApproxEqAbs(
            aliceYieldWithFee,
            yields[M_EARNER_MANAGER],
            50,
            "unexpected alice's mEarnerManager yield with fee"
        );
        assertApproxEqAbs(aliceFee, yields[M_EARNER_MANAGER] / 2, 50, "unexpected alice's mEarnerManager fee");
        assertApproxEqAbs(aliceYield, yields[M_EARNER_MANAGER] / 2, 50, "unexpected alice's mEarnerManager yield");

        return (priorYield == 0 ? amount - 2 : amount, yields);
    }
}
