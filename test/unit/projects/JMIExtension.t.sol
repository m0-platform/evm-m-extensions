// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Vm } from "../../../lib/forge-std/src/Vm.sol";

import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../../lib/common/src/interfaces/IERC20Extended.sol";

import { IAccessControl } from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { PausableUpgradeable } from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { Upgrades, UnsafeUpgrades } from "../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { UIntMath } from "../../../lib/common/src/libs/UIntMath.sol";

import { MockERC20, MockFeeOnTransferERC20, MockM } from "../../utils/Mocks.sol";

import { JMIExtension } from "../../../src/projects/jmi/JMIExtension.sol";
import { IJMIExtension } from "../../../src/projects/jmi/IJMIExtension.sol";
import { IMYieldToOne } from "../../../src/projects/yieldToOne/interfaces/IMYieldToOne.sol";

import { IMExtension } from "../../../src/interfaces/IMExtension.sol";

import { JMIExtensionHarness } from "../../harness/JMIExtensionHarness.sol";

import { BaseUnitTest } from "../../utils/BaseUnitTest.sol";

contract JMIExtensionUnitTests is BaseUnitTest {
    JMIExtensionHarness public jmi;

    string public constant NAME = "Just Mint It";
    string public constant SYMBOL = "JMI";
    uint8 public constant EXTENSION_DECIMALS = 6;

    MockERC20 public mockUSDC;
    uint256 public mockUSDCCap = 1_000_000_000e6;

    MockERC20 public mockAsset4Decimals;
    uint256 public mockAsset4DecimalsCap = 1_000_000_000e4;

    MockERC20 public mockDAI;
    uint256 public mockDAICap = 1_000_000_000e18;

    MockFeeOnTransferERC20 public mockFeeOnTransferToken;
    uint256 public mockFeeOnTransferTokenCap = 1_000_000_000e18;

    function setUp() public override {
        super.setUp();

        mockUSDC = new MockERC20("Mock USDC", "USDC", EXTENSION_DECIMALS);
        mockAsset4Decimals = new MockERC20("Mock Asset 4 Decimals", "MA4D", 4);
        mockDAI = new MockERC20("Mock DAI", "DAI", 18);
        mockFeeOnTransferToken = new MockFeeOnTransferERC20("MockFeeOnTransferERC20", "MFOTERC20", 6);

        jmi = JMIExtensionHarness(
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

        vm.prank(allowlistAdmin);
        jmi.grantRole(ALLOWLIST_MANAGER_ROLE, admin);

        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockUSDC), mockUSDCCap);

        vm.prank(address(swapFacility));
        mockUSDC.approve(address(jmi), type(uint256).max);

        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockAsset4Decimals), mockAsset4DecimalsCap);

        vm.prank(address(swapFacility));
        mockAsset4Decimals.approve(address(jmi), type(uint256).max);

        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockDAI), mockDAICap);

        vm.prank(address(swapFacility));
        mockDAI.approve(address(jmi), type(uint256).max);

        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockFeeOnTransferToken), mockFeeOnTransferTokenCap);

        vm.prank(address(swapFacility));
        mockFeeOnTransferToken.approve(address(jmi), type(uint256).max);

        registrar.setEarner(address(jmi), true);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(jmi.name(), NAME);
        assertEq(jmi.symbol(), SYMBOL);
        assertEq(jmi.decimals(), EXTENSION_DECIMALS);
        assertEq(jmi.mToken(), address(mToken));
        assertEq(jmi.swapFacility(), address(swapFacility));
        assertEq(jmi.yieldRecipient(), yieldRecipient);
        assertEq(jmi.M_DECIMALS(), EXTENSION_DECIMALS);

        assertTrue(jmi.isAllowedAsset(address(mockUSDC)));
        assertEq(jmi.assetCap(address(mockUSDC)), mockUSDCCap);
        assertEq(jmi.assetDecimals(address(mockUSDC)), 6);

        assertTrue(jmi.isAllowedAsset(address(mockAsset4Decimals)));
        assertEq(jmi.assetCap(address(mockAsset4Decimals)), mockAsset4DecimalsCap);
        assertEq(jmi.assetDecimals(address(mockAsset4Decimals)), 4);

        assertTrue(jmi.isAllowedAsset(address(mockDAI)));
        assertEq(jmi.assetCap(address(mockDAI)), mockDAICap);
        assertEq(jmi.assetDecimals(address(mockDAI)), 18);

        assertTrue(IAccessControl(address(jmi)).hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(IAccessControl(address(jmi)).hasRole(ASSET_CAP_MANAGER_ROLE, assetCapManager));
        assertTrue(IAccessControl(address(jmi)).hasRole(FREEZE_MANAGER_ROLE, freezeManager));
        assertTrue(IAccessControl(address(jmi)).hasRole(PAUSER_ROLE, pauser));
        assertTrue(IAccessControl(address(jmi)).hasRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager));
    }

    function test_initialize_zeroAssetCapManager() external {
        address implementation = address(new JMIExtensionHarness(address(mToken), address(swapFacility)));

        vm.expectRevert(IJMIExtension.ZeroAssetCapManager.selector);
        JMIExtensionHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    JMIExtensionHarness.initialize.selector,
                    NAME,
                    SYMBOL,
                    yieldRecipient,
                    admin,
                    address(0),
                    freezeManager,
                    pauser,
                    yieldRecipientManager,
                    allowlistAdmin
                )
            )
        );
    }

    /* ============ assetBalanceOf ============ */

    function test_assetBalanceOf() external {
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), 0);

        uint256 amount = 1_000e6;

        jmi.setAssetBalanceOf(address(mockUSDC), amount);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), amount);
    }

    /* ============ isAllowedAsset ============ */

    function test_isAllowedAsset() external {
        assertTrue(jmi.isAllowedAsset(address(mToken)));
        assertTrue(jmi.isAllowedAsset(address(mockUSDC)));
        assertTrue(jmi.isAllowedAsset(address(mockAsset4Decimals)));
        assertTrue(jmi.isAllowedAsset(address(mockDAI)));
        assertFalse(jmi.isAllowedAsset(address(0)));

        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockUSDC), 0);

        assertFalse(jmi.isAllowedAsset(address(mockUSDC)));
    }

    /* ============ isAllowedToWrap ============ */

    function test_isAllowedToWrap() external {
        assertTrue(jmi.isAllowedToWrap(address(mToken), type(uint256).max));
        assertTrue(jmi.isAllowedToWrap(address(mockUSDC), mockUSDCCap));

        assertFalse(jmi.isAllowedToWrap(address(mToken), 0));
        assertFalse(jmi.isAllowedToWrap(address(mockUSDC), 0));

        jmi.setAssetBalanceOf(address(mockUSDC), mockUSDCCap - 1);

        assertTrue(jmi.isAllowedToWrap(address(mockUSDC), 1));
        assertFalse(jmi.isAllowedToWrap(address(mockUSDC), 2));
    }

    /* ============ isAllowedToUnwrap ============ */

    function test_isAllowedToUnwrap() external {
        assertFalse(jmi.isAllowedToUnwrap(0));

        jmi.setTotalSupply(100_000_000e6);
        jmi.setTotalAssets(50_000_000e6);

        assertTrue(jmi.isAllowedToUnwrap(25_000_000e6));

        jmi.setTotalSupply(100_000_000e6);
        jmi.setTotalAssets(90_000_000e6);

        assertTrue(jmi.isAllowedToUnwrap(10_000_000e6));
        assertFalse(jmi.isAllowedToUnwrap(25_000_000e6));
    }

    /* ============ isAllowedToReplaceAssetWithM ============ */

    function test_isAllowedToReplaceAssetWithM() external {
        assertFalse(jmi.isAllowedToReplaceAssetWithM(address(mockUSDC), 0));
        assertFalse(jmi.isAllowedToReplaceAssetWithM(address(mockUSDC), 1));

        jmi.setAssetBalanceOf(address(mockUSDC), 100_000_000e6);

        assertTrue(jmi.isAllowedToReplaceAssetWithM(address(mockUSDC), 25_000_000e6));
        assertTrue(jmi.isAllowedToReplaceAssetWithM(address(mockUSDC), 100_000_000e6));
        assertFalse(jmi.isAllowedToReplaceAssetWithM(address(mockUSDC), 125_000_000e6));
    }

    /* ============ setAssetCap ============ */

    function test_setAssetCap_onlyAssetCapManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                ASSET_CAP_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        jmi.setAssetCap(address(mockUSDC), 1000);
    }

    function test_setAssetCap_invalidAsset() external {
        vm.expectRevert(abi.encodeWithSelector(IJMIExtension.InvalidAsset.selector, address(0)));

        vm.prank(assetCapManager);
        jmi.setAssetCap(address(0), 1000);
    }

    function test_setAssetCap_earlyReturn() external {
        assertEq(jmi.assetCap(address(mockUSDC)), mockUSDCCap);

        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockUSDC), mockUSDCCap);

        assertEq(jmi.assetCap(address(mockUSDC)), mockUSDCCap);
    }

    function test_setAssetCap() external {
        assertEq(jmi.assetCap(address(mockUSDC)), mockUSDCCap);

        uint256 newCap = mockUSDCCap * 2;

        vm.expectEmit();
        emit IJMIExtension.AssetCapSet(address(mockUSDC), newCap);

        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockUSDC), newCap);

        assertEq(jmi.assetCap(address(mockUSDC)), newCap);
    }

    /* ============ wrap ============ */

    function test_wrap_onlySwapFacility() external {
        vm.expectRevert(IMExtension.NotSwapFacility.selector);

        vm.prank(alice);
        jmi.wrap(address(mockUSDC), alice, 1);
    }

    function test_wrap_enforcedPause() external {
        vm.prank(pauser);
        jmi.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockUSDC), alice, 1);
    }

    function test_wrap_invalidAsset() external {
        vm.expectRevert(abi.encodeWithSelector(IJMIExtension.InvalidAsset.selector, address(0)));

        vm.prank(address(swapFacility));
        jmi.wrap(address(0), alice, 1);
    }

    function test_wrap_invalidRecipient() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockUSDC), address(0), 1);
    }

    function test_wrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockUSDC), alice, 0);
    }

    function test_wrap_insufficientJMIAmount() external {
        uint256 amount = 1;

        mockDAI.mint(address(swapFacility), amount);
        assertEq(mockDAI.balanceOf(address(swapFacility)), amount);

        // Truncates down when converting from asset to extension amount.
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockDAI), alice, amount);
    }

    function test_wrap_assetNotAllowed() external {
        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockDAI), 0);

        vm.expectRevert(abi.encodeWithSelector(IJMIExtension.AssetCapReached.selector, address(mockDAI)));

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockDAI), alice, 1);
    }

    function test_wrap_safe240_overflow() external {
        uint256 amount = uint256(type(uint240).max) + 1;

        mockUSDC.mint(address(swapFacility), amount);
        assertEq(mockUSDC.balanceOf(address(swapFacility)), amount);

        // Set asset cap to allow the maximum uint240 value
        vm.prank(assetCapManager);
        jmi.setAssetCap(address(mockUSDC), amount);

        vm.expectRevert(abi.encodeWithSelector(UIntMath.InvalidUInt240.selector, address(mockUSDC)));

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockUSDC), alice, amount);
    }

    function test_wrap_withM_enforcedPause() public {
        uint256 amount = 1_000e6;

        mToken.setBalanceOf(address(swapFacility), amount);
        assertEq(mToken.balanceOf(address(swapFacility)), amount);

        vm.prank(pauser);
        jmi.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(address(swapFacility));
        jmi.wrap(alice, amount);
    }

    function test_wrap_withM() public {
        // `wrap(address recipient, uint256 amount)` can be used to wrap with M directly.
        vm.expectRevert(abi.encodeWithSelector(IJMIExtension.InvalidAsset.selector, address(mToken)));

        vm.prank(address(swapFacility));
        jmi.wrap(address(mToken), alice, 1_000e6);
    }

    function test_wrap() public {
        uint256 amount = 1_000e6;

        mockUSDC.mint(address(swapFacility), amount);
        assertEq(mockUSDC.balanceOf(address(swapFacility)), amount);

        vm.expectCall(
            address(mockUSDC),
            abi.encodeWithSelector(mockUSDC.transferFrom.selector, address(swapFacility), address(jmi), amount)
        );

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, amount);

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockUSDC), alice, amount);

        assertEq(jmi.getBalanceOf(alice), amount);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), amount);
        assertEq(jmi.totalAssets(), amount);
        assertEq(jmi.totalSupply(), amount);

        assertEq(mockUSDC.balanceOf(alice), 0);
        assertEq(mockUSDC.balanceOf(address(jmi)), amount);
    }

    function test_wrap_assetDeposit_emitsPlaintextOnly() public {
        uint256 amount = 1_000e6;

        _installContractKey();

        vm.prank(alice);
        jmi.registerPublicKey(_validPubKey(0xBB));

        mockUSDC.mint(address(swapFacility), amount);

        vm.recordLogs();

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockUSDC), alice, amount);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 bytesTopic = keccak256("Transfer(address,address,bytes32,bytes)");
        bytes32 plaintextTopic = keccak256("Transfer(address,address,uint256)");

        bool foundBytes;
        bool foundPlaintext;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(jmi)) continue;
            if (logs[i].topics.length == 0) continue;

            if (logs[i].topics[0] == bytesTopic) {
                foundBytes = true;
            } else if (logs[i].topics[0] == plaintextTopic) {
                foundPlaintext = true;
            }
        }

        assertTrue(foundPlaintext, "missing plaintext Transfer(uint256) on asset deposit");
        assertFalse(foundBytes, "bytes-overload Transfer emitted on asset deposit");

        assertEq(jmi.getEncryptedEventNonce(), 0);
        assertEq(jmi.getBalanceOf(alice), amount);
    }

    function test_wrap_diffDecimals() public {
        uint256 mockDAIAmount = 1e18;
        uint256 mockAsset4DecimalsAmount = 1e4;
        uint256 extensionAmount = 1e6;

        mockDAI.mint(address(swapFacility), mockDAIAmount);
        assertEq(mockDAI.balanceOf(address(swapFacility)), mockDAIAmount);

        mockAsset4Decimals.mint(address(swapFacility), mockAsset4DecimalsAmount);
        assertEq(mockAsset4Decimals.balanceOf(address(swapFacility)), mockAsset4DecimalsAmount);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, extensionAmount);

        vm.expectCall(
            address(mockDAI),
            abi.encodeWithSelector(mockDAI.transferFrom.selector, address(swapFacility), address(jmi), mockDAIAmount)
        );

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockDAI), alice, mockDAIAmount);

        assertEq(jmi.getBalanceOf(alice), extensionAmount);
        assertEq(jmi.assetBalanceOf(address(mockDAI)), mockDAIAmount);
        assertEq(jmi.totalAssets(), extensionAmount);
        assertEq(jmi.totalSupply(), extensionAmount);

        assertEq(mockDAI.balanceOf(alice), 0);
        assertEq(mockDAI.balanceOf(address(jmi)), mockDAIAmount);

        vm.expectCall(
            address(mockAsset4Decimals),
            abi.encodeWithSelector(
                mockAsset4Decimals.transferFrom.selector,
                address(swapFacility),
                address(jmi),
                mockAsset4DecimalsAmount
            )
        );

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, extensionAmount);

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockAsset4Decimals), alice, mockAsset4DecimalsAmount);

        assertEq(jmi.getBalanceOf(alice), extensionAmount * 2);
        assertEq(jmi.assetBalanceOf(address(mockAsset4Decimals)), mockAsset4DecimalsAmount);
        assertEq(jmi.totalAssets(), extensionAmount * 2);
        assertEq(jmi.totalSupply(), extensionAmount * 2);

        assertEq(mockAsset4Decimals.balanceOf(alice), 0);
        assertEq(mockAsset4Decimals.balanceOf(address(jmi)), mockAsset4DecimalsAmount);
    }

    function test_wrap_feeOnTransfer() public {
        uint256 amount = 1_000e6;
        uint256 amountAfterFee = amount - 10e6;

        mockFeeOnTransferToken.mint(address(swapFacility), amount);
        assertEq(mockFeeOnTransferToken.balanceOf(address(swapFacility)), amount);

        vm.expectCall(
            address(mockFeeOnTransferToken),
            abi.encodeWithSelector(
                mockFeeOnTransferToken.transferFrom.selector,
                address(swapFacility),
                address(jmi),
                amount
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IJMIExtension.InsufficientAssetReceived.selector,
                address(mockFeeOnTransferToken),
                amount,
                amountAfterFee
            )
        );

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockFeeOnTransferToken), alice, amount);
    }

    function testFuzz_wrap(uint240 amount) public {
        bool assetCapReached = amount > mockUSDCCap;

        mockUSDC.mint(address(swapFacility), amount);
        assertEq(mockUSDC.balanceOf(address(swapFacility)), amount);

        if (amount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        } else if (assetCapReached) {
            vm.expectRevert(abi.encodeWithSelector(IJMIExtension.AssetCapReached.selector, address(mockUSDC)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), alice, amount);
        }

        if (!assetCapReached && amount != 0) {
            vm.expectCall(
                address(mockUSDC),
                abi.encodeWithSelector(mockUSDC.transferFrom.selector, address(swapFacility), address(jmi), amount)
            );
        }

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockUSDC), alice, amount);

        if (assetCapReached || amount == 0) {
            return;
        }

        assertEq(jmi.getBalanceOf(alice), amount);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), amount);
        assertEq(jmi.totalAssets(), amount);
        assertEq(jmi.totalSupply(), amount);

        assertEq(mockUSDC.balanceOf(alice), 0);
        assertEq(mockUSDC.balanceOf(address(jmi)), amount);
    }

    function testFuzz_wrap_diffDecimals(uint256 seed, uint240 amount) public {
        (MockERC20 asset, uint256 assetCap, ) = _getRandomAsset(seed);

        bool assetCapReached = amount > assetCap;
        uint256 extensionAmount = jmi.fromAssetToExtensionAmount(address(asset), amount);

        asset.mint(address(swapFacility), amount);
        assertEq(asset.balanceOf(address(swapFacility)), amount);

        if (amount == 0 || extensionAmount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        } else if (assetCapReached) {
            vm.expectRevert(abi.encodeWithSelector(IJMIExtension.AssetCapReached.selector, address(asset)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), alice, extensionAmount);
        }

        if (!assetCapReached && amount != 0) {
            vm.expectCall(
                address(asset),
                abi.encodeWithSelector(asset.transferFrom.selector, address(swapFacility), address(jmi), amount)
            );
        }

        vm.prank(address(swapFacility));
        jmi.wrap(address(asset), alice, amount);

        if (assetCapReached || amount == 0 || extensionAmount == 0) {
            return;
        }

        assertEq(jmi.getBalanceOf(alice), extensionAmount);
        assertEq(jmi.assetBalanceOf(address(asset)), amount);
        assertEq(jmi.totalAssets(), extensionAmount);
        assertEq(jmi.totalSupply(), extensionAmount);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(jmi)), amount);
    }

    /* ============ unwrap ============ */

    function test_unwrap_enforcedPause() external {
        jmi.setTotalSupply(1);

        vm.prank(pauser);
        jmi.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(address(swapFacility));
        jmi.unwrap(alice, 1);
    }

    function test_unwrap_insufficientMBacking() public {
        uint256 unwrapAmount = 1e6;

        vm.expectRevert(abi.encodeWithSelector(IJMIExtension.InsufficientMBacking.selector, unwrapAmount, 0));

        vm.prank(address(swapFacility));
        jmi.unwrap(alice, unwrapAmount);
    }

    function test_unwrap() public {
        uint256 amount = 1_000e6;
        uint256 unwrapAmount = 1e6;
        uint256 totalSupply = amount * 2;
        uint256 totalUnwrapAmount = 0;

        jmi.setBalanceOf(address(swapFacility), totalSupply);
        jmi.setTotalSupply(totalSupply);

        mToken.setBalanceOf(address(jmi), amount);
        jmi.setAssetBalanceOf(address(mockUSDC), amount);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), unwrapAmount);

        vm.prank(address(swapFacility));
        jmi.unwrap(alice, unwrapAmount);

        totalSupply -= unwrapAmount;
        totalUnwrapAmount += unwrapAmount;

        assertEq(jmi.totalSupply(), totalSupply);
        assertEq(jmi.getBalanceOf(address(swapFacility)), totalSupply);
        assertEq(mToken.balanceOf(address(swapFacility)), totalUnwrapAmount);

        unwrapAmount = 499e6;

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), unwrapAmount);

        vm.prank(address(swapFacility));
        jmi.unwrap(alice, unwrapAmount);

        totalSupply -= unwrapAmount;
        totalUnwrapAmount += unwrapAmount;

        assertEq(jmi.totalSupply(), totalSupply);
        assertEq(jmi.getBalanceOf(address(swapFacility)), totalSupply);
        assertEq(mToken.balanceOf(address(swapFacility)), totalUnwrapAmount);

        unwrapAmount = 500e6;

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), unwrapAmount);

        vm.prank(address(swapFacility));
        jmi.unwrap(alice, unwrapAmount);

        totalSupply -= unwrapAmount;
        totalUnwrapAmount += unwrapAmount;

        assertEq(jmi.totalSupply(), totalSupply);
        assertEq(jmi.getBalanceOf(address(swapFacility)), totalSupply);

        assertEq(mToken.balanceOf(address(swapFacility)), totalUnwrapAmount);
        assertEq(mToken.balanceOf(address(jmi)), 0);
    }

    function testFuzz_unwrap(uint240 amount, uint240 mSupply, uint256 totalAssets) public {
        // Cap totalAssets to prevent overflow when calculating totalSupply
        totalAssets = bound(totalAssets, 0, type(uint256).max - mSupply);

        // We assume that all yield has been accrued
        uint256 totalSupply = uint256(mSupply) + totalAssets;

        jmi.setTotalAssets(totalAssets);
        jmi.setBalanceOf(address(swapFacility), totalSupply);
        jmi.setTotalSupply(totalSupply);

        mToken.setBalanceOf(address(jmi), mSupply);
        jmi.setAssetBalanceOf(address(mockUSDC), totalAssets);

        // Calculate expected M backing: totalSupply - totalAssets
        uint256 expectedMBacking = totalSupply > totalAssets ? totalSupply - totalAssets : 0;

        if (amount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        } else if (amount > expectedMBacking) {
            vm.expectRevert(
                abi.encodeWithSelector(IJMIExtension.InsufficientMBacking.selector, amount, expectedMBacking)
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(swapFacility), address(0), amount);
        }

        vm.prank(address(swapFacility));
        jmi.unwrap(alice, amount);

        if (amount == 0 || amount > expectedMBacking) {
            return;
        }

        assertEq(jmi.totalSupply(), totalSupply - amount);
        assertEq(jmi.getBalanceOf(address(swapFacility)), totalSupply - amount);

        assertEq(mToken.balanceOf(address(swapFacility)), amount);
        assertEq(mToken.balanceOf(address(jmi)), mSupply - amount);
    }

    /* ============ transfer (shielded) ============ */

    function test_transfer_enforcedPause() external {
        vm.prank(pauser);
        jmi.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        jmi.transfer(bob, suint256(1));
    }

    function test_shieldedTransfer() external {
        uint256 amount = 1_000e6;

        _installContractKey();

        mockUSDC.mint(address(swapFacility), amount);
        assertEq(mockUSDC.balanceOf(address(swapFacility)), amount);

        vm.prank(address(swapFacility));
        jmi.wrap(address(mockUSDC), alice, amount);

        assertEq(jmi.getBalanceOf(alice), amount);
        assertEq(jmi.getBalanceOf(bob), 0);

        assertEq(jmi.assetBalanceOf(address(mockUSDC)), amount);
        assertEq(jmi.totalAssets(), amount);
        assertEq(jmi.totalSupply(), amount);

        vm.expectEmit(true, true, true, true);
        emit IMYieldToOne.Transfer(alice, bob, bytes32(0), bytes(""));

        vm.prank(alice);
        jmi.transfer(bob, suint256(amount));

        assertEq(jmi.getBalanceOf(alice), 0);
        assertEq(jmi.getBalanceOf(bob), amount);

        assertEq(jmi.assetBalanceOf(address(mockUSDC)), amount);
        assertEq(jmi.totalAssets(), amount);
        assertEq(jmi.totalSupply(), amount);
    }

    function test_transfer_inheritedPathReverts() external {
        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);

        vm.prank(alice);
        jmi.transfer(bob, 1_000e6);
    }

    function test_transfer_inheritedPathRevertsWhenPaused() external {
        vm.prank(pauser);
        jmi.pause();

        vm.expectRevert(IMYieldToOne.UseShieldedTransfer.selector);

        vm.prank(alice);
        jmi.transfer(bob, 1);
    }

    /* ============ transferFrom (native) ============ */

    function test_nativeTransferFrom_allowlistedCaller() public {
        uint256 amount = 1_000e6;
        uint256 allowanceAmount = 1_500e6;
        jmi.setBalanceOf(alice, amount);

        _installContractKey();

        vm.prank(admin);
        jmi.setAllowlisted(carol, true);

        vm.prank(alice);
        jmi.approve(carol, suint256(allowanceAmount));

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount);

        vm.prank(carol);
        jmi.transferFrom(alice, bob, amount);

        assertEq(jmi.getBalanceOf(alice), 0);
        assertEq(jmi.getBalanceOf(bob), amount);

        vm.prank(alice);
        assertEq(jmi.allowance(alice, carol), allowanceAmount - amount);
    }

    /* ============ balanceOf ============ */

    function test_balanceOf_holderCanRead() public {
        jmi.setBalanceOf(alice, 1_000e6);

        vm.prank(alice);
        assertEq(jmi.balanceOf(alice), 1_000e6);
    }

    function test_balanceOf_unauthorized() public {
        jmi.setBalanceOf(alice, 1_000e6);

        vm.expectRevert(IMYieldToOne.Unauthorized.selector);
        vm.prank(bob);
        jmi.balanceOf(alice);
    }

    function test_balanceOf_swapFacilityCanRead() public {
        jmi.setBalanceOf(alice, 1_000e6);

        vm.prank(address(swapFacility));
        assertEq(jmi.balanceOf(alice), 1_000e6);
    }

    /* ============ replaceAssetWithM ============ */

    function test_replaceAssetWithM_onlySwapFacility() external {
        vm.expectRevert(IMExtension.NotSwapFacility.selector);

        vm.prank(alice);
        jmi.replaceAssetWithM(address(mockUSDC), alice, 1);
    }

    function test_replaceAssetWithM_enforcedPause() external {
        vm.prank(pauser);
        jmi.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockUSDC), alice, 1);
    }

    function test_replaceAssetWithM_invalidAsset() external {
        vm.expectRevert(abi.encodeWithSelector(IJMIExtension.InvalidAsset.selector, address(0)));

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(0), alice, 1);

        vm.expectRevert(abi.encodeWithSelector(IJMIExtension.InvalidAsset.selector, address(mToken)));

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mToken), alice, 1);
    }

    function test_replaceAssetWithM_invalidRecipient() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockUSDC), address(0), 1);
    }

    function test_replaceAssetWithM_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockUSDC), alice, 0);
    }

    function test_replaceAssetWithM_insufficientAssetAmount() external {
        uint256 amount = 1;

        mockAsset4Decimals.mint(address(jmi), amount);
        assertEq(mockAsset4Decimals.balanceOf(address(jmi)), amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockAsset4Decimals), alice, amount);
    }

    function test_replaceAssetWithM_insufficientAssetBacking() external {
        uint256 amount = 1_000e6;

        vm.expectRevert(
            abi.encodeWithSelector(IJMIExtension.InsufficientAssetBacking.selector, address(mockUSDC), amount, 0)
        );

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockUSDC), alice, amount);
    }

    function test_replaceAssetWithM_inflationAttack() public {
        uint256 amount = 1_000e6;

        jmi.setAssetBalanceOf(address(mockUSDC), amount);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), amount);

        mToken.setBalanceOf(address(swapFacility), amount * 4);
        assertEq(mToken.balanceOf(address(swapFacility)), amount * 4);

        jmi.setTotalAssets(amount);
        assertEq(jmi.totalAssets(), amount);

        jmi.setTotalSupply(amount);
        assertEq(jmi.totalSupply(), amount);

        // Send USDC directly to the contract to bypass `_revertIfInsufficientAssetBacking()` check.
        mockUSDC.mint(address(jmi), amount * 2);
        assertEq(mockUSDC.balanceOf(address(jmi)), amount * 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IJMIExtension.InsufficientAssetBacking.selector,
                address(mockUSDC),
                amount * 3,
                amount
            )
        );

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockUSDC), alice, amount * 3);
    }

    function test_replaceAssetWithM() public {
        uint256 amount = 1_000e6;

        mockUSDC.mint(address(jmi), amount);
        assertEq(mockUSDC.balanceOf(address(jmi)), amount);

        jmi.setAssetBalanceOf(address(mockUSDC), amount);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), amount);

        mToken.setBalanceOf(address(swapFacility), amount);
        assertEq(mToken.balanceOf(address(swapFacility)), amount);

        jmi.setTotalAssets(amount);
        assertEq(jmi.totalAssets(), amount);

        jmi.setTotalSupply(amount);
        assertEq(jmi.totalSupply(), amount);

        vm.expectCall(address(mockUSDC), abi.encodeWithSelector(mockUSDC.transfer.selector, alice, amount));

        vm.expectEmit();
        emit IJMIExtension.AssetReplacedWithM(address(mockUSDC), amount, alice, amount);

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockUSDC), alice, amount);

        assertEq(jmi.getBalanceOf(alice), 0);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), 0);
        assertEq(jmi.totalAssets(), 0);
        assertEq(jmi.totalSupply(), amount);

        assertEq(mToken.balanceOf(address(swapFacility)), 0);
        assertEq(mToken.balanceOf(address(jmi)), amount);

        assertEq(mockUSDC.balanceOf(alice), amount);
        assertEq(mockUSDC.balanceOf(address(jmi)), 0);
    }

    function test_replaceAssetWithM_diffDecimals() public {
        uint256 mockDAIAmount = 1e18;
        uint256 mockAsset4DecimalsAmount = 1e4;
        uint256 extensionAmount = 1e6;
        uint256 totalAmount = extensionAmount * 2;

        mockDAI.mint(address(jmi), mockDAIAmount);
        assertEq(mockDAI.balanceOf(address(jmi)), mockDAIAmount);

        jmi.setAssetBalanceOf(address(mockDAI), mockDAIAmount);
        assertEq(jmi.assetBalanceOf(address(mockDAI)), mockDAIAmount);

        mockAsset4Decimals.mint(address(jmi), mockAsset4DecimalsAmount);
        assertEq(mockAsset4Decimals.balanceOf(address(jmi)), mockAsset4DecimalsAmount);

        jmi.setAssetBalanceOf(address(mockAsset4Decimals), mockAsset4DecimalsAmount);
        assertEq(jmi.assetBalanceOf(address(mockAsset4Decimals)), mockAsset4DecimalsAmount);

        jmi.setTotalAssets(totalAmount);
        assertEq(jmi.totalAssets(), totalAmount);

        jmi.setTotalSupply(totalAmount);
        assertEq(jmi.totalSupply(), totalAmount);

        mToken.setBalanceOf(address(swapFacility), totalAmount);
        assertEq(mToken.balanceOf(address(swapFacility)), totalAmount);

        vm.expectEmit();
        emit IJMIExtension.AssetReplacedWithM(address(mockDAI), mockDAIAmount, alice, extensionAmount);

        vm.expectCall(address(mockDAI), abi.encodeWithSelector(mockDAI.transfer.selector, alice, mockDAIAmount));

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockDAI), alice, extensionAmount);

        assertEq(jmi.getBalanceOf(alice), 0);
        assertEq(jmi.totalAssets(), extensionAmount);
        assertEq(jmi.totalSupply(), totalAmount);

        assertEq(mToken.balanceOf(address(swapFacility)), extensionAmount);
        assertEq(mToken.balanceOf(address(jmi)), extensionAmount);

        assertEq(mockDAI.balanceOf(alice), mockDAIAmount);
        assertEq(mockDAI.balanceOf(address(jmi)), 0);

        vm.expectEmit();
        emit IJMIExtension.AssetReplacedWithM(
            address(mockAsset4Decimals),
            mockAsset4DecimalsAmount,
            alice,
            extensionAmount
        );

        vm.expectCall(
            address(mockAsset4Decimals),
            abi.encodeWithSelector(mockAsset4Decimals.transfer.selector, alice, mockAsset4DecimalsAmount)
        );

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockAsset4Decimals), alice, extensionAmount);

        assertEq(jmi.getBalanceOf(alice), 0);
        assertEq(jmi.assetBalanceOf(address(mockAsset4Decimals)), 0);
        assertEq(jmi.totalAssets(), 0);
        assertEq(jmi.totalSupply(), totalAmount);

        assertEq(mToken.balanceOf(address(swapFacility)), 0);
        assertEq(mToken.balanceOf(address(jmi)), totalAmount);

        assertEq(mockAsset4Decimals.balanceOf(alice), mockAsset4DecimalsAmount);
        assertEq(mockAsset4Decimals.balanceOf(address(jmi)), 0);
    }

    function testFuzz_replaceAssetWithM(uint256 amount, uint256 usdcBacking, uint240 mSupply) public {
        usdcBacking = bound(usdcBacking, 0, type(uint240).max - mSupply);
        uint256 extensionSupply = uint256(mSupply) + usdcBacking;

        mockUSDC.mint(address(jmi), usdcBacking);
        assertEq(mockUSDC.balanceOf(address(jmi)), usdcBacking);

        jmi.setAssetBalanceOf(address(mockUSDC), usdcBacking);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), usdcBacking);

        mToken.setBalanceOf(address(swapFacility), amount);
        assertEq(mToken.balanceOf(address(swapFacility)), amount);

        mToken.setBalanceOf(address(jmi), mSupply);
        assertEq(mToken.balanceOf(address(jmi)), mSupply);

        jmi.setTotalAssets(usdcBacking);
        assertEq(jmi.totalAssets(), usdcBacking);

        jmi.setTotalSupply(extensionSupply);
        assertEq(jmi.totalSupply(), extensionSupply);

        bool usdcBackingInsufficient = amount > usdcBacking;

        if (amount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        } else if (usdcBackingInsufficient) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IJMIExtension.InsufficientAssetBacking.selector,
                    address(mockUSDC),
                    amount,
                    usdcBacking
                )
            );
        } else {
            vm.expectEmit();
            emit IJMIExtension.AssetReplacedWithM(address(mockUSDC), amount, alice, amount);
        }

        if (!usdcBackingInsufficient && amount != 0) {
            vm.expectCall(address(mockUSDC), abi.encodeWithSelector(mockUSDC.transfer.selector, alice, amount));
        }

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(mockUSDC), alice, amount);

        if (usdcBackingInsufficient || amount == 0) {
            return;
        }

        assertEq(jmi.getBalanceOf(alice), 0);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), usdcBacking - amount);
        assertEq(jmi.totalAssets(), usdcBacking - amount);
        assertEq(jmi.totalSupply(), extensionSupply);

        assertEq(mToken.balanceOf(address(swapFacility)), 0);
        assertEq(mToken.balanceOf(address(jmi)), mSupply + amount);

        assertEq(mockUSDC.balanceOf(alice), amount);
        assertEq(mockUSDC.balanceOf(address(jmi)), usdcBacking - amount);
    }

    function testFuzz_replaceAssetWithM_diffDecimals(
        uint256 seed,
        uint256 amount,
        uint256 assetBacking,
        uint240 mSupply
    ) public {
        assetBacking = bound(assetBacking, 0, type(uint240).max - mSupply);

        (MockERC20 asset, , uint8 assetDecimals) = _getRandomAsset(seed);

        bool isAssetDecimalsGreater = assetDecimals > EXTENSION_DECIMALS;
        uint256 scaleFactor = isAssetDecimalsGreater
            ? (10 ** (assetDecimals - EXTENSION_DECIMALS))
            : (10 ** (EXTENSION_DECIMALS - assetDecimals));

        // Overflow can occur for very large amounts when scaling up
        if (!isAssetDecimalsGreater && uint256(amount) > type(uint256).max / scaleFactor) {
            return;
        }

        uint256 extensionAmount = jmi.fromAssetToExtensionAmount(address(asset), amount);

        if (!isAssetDecimalsGreater && uint256(assetBacking) > type(uint256).max / scaleFactor) {
            return;
        }

        uint256 extensionBacking = jmi.fromAssetToExtensionAmount(address(asset), assetBacking);
        amount = jmi.fromExtensionToAssetAmount(address(asset), extensionAmount);

        uint256 extensionSupply = uint256(mSupply) + extensionBacking;

        asset.mint(address(jmi), assetBacking);
        assertEq(asset.balanceOf(address(jmi)), assetBacking);

        jmi.setAssetBalanceOf(address(asset), assetBacking);
        assertEq(jmi.assetBalanceOf(address(asset)), assetBacking);

        mToken.setBalanceOf(address(swapFacility), extensionAmount);
        assertEq(mToken.balanceOf(address(swapFacility)), extensionAmount);

        mToken.setBalanceOf(address(jmi), mSupply);
        assertEq(mToken.balanceOf(address(jmi)), mSupply);

        jmi.setTotalAssets(extensionBacking);
        assertEq(jmi.totalAssets(), extensionBacking);

        jmi.setTotalSupply(extensionSupply);
        assertEq(jmi.totalSupply(), extensionSupply);

        bool assetBackingInsufficient = amount > assetBacking;

        if (extensionAmount == 0 || amount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        } else if (assetBackingInsufficient) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IJMIExtension.InsufficientAssetBacking.selector,
                    address(asset),
                    jmi.fromExtensionToAssetAmount(address(asset), extensionAmount),
                    assetBacking
                )
            );
        } else {
            vm.expectEmit();
            emit IJMIExtension.AssetReplacedWithM(
                address(asset),
                jmi.fromExtensionToAssetAmount(address(asset), extensionAmount),
                alice,
                extensionAmount
            );
        }

        if (!assetBackingInsufficient && extensionAmount != 0) {
            vm.expectCall(address(asset), abi.encodeWithSelector(asset.transfer.selector, alice, amount));
        }

        vm.prank(address(swapFacility));
        jmi.replaceAssetWithM(address(asset), alice, extensionAmount);

        if (assetBackingInsufficient || extensionAmount == 0 || amount == 0) {
            return;
        }

        assertEq(jmi.getBalanceOf(alice), 0);
        assertEq(jmi.assetBalanceOf(address(asset)), assetBacking - amount);
        assertEq(jmi.totalAssets(), extensionBacking - extensionAmount);
        assertEq(jmi.totalSupply(), extensionSupply);

        assertEq(mToken.balanceOf(address(swapFacility)), 0);
        assertEq(mToken.balanceOf(address(jmi)), mSupply + extensionAmount);

        assertEq(asset.balanceOf(alice), amount);
        assertEq(asset.balanceOf(address(jmi)), assetBacking - amount);
    }

    /* ============ yield ============ */

    function testFuzz_yield(uint240 mBalance, uint256 totalAssets) external {
        // Cap totalAssets to prevent overflow when calculating totalSupply
        totalAssets = uint256(bound(totalAssets, 0, type(uint256).max - mBalance));

        uint256 totalSupply = bound(0, totalAssets, mBalance + totalAssets);

        mToken.setBalanceOf(address(jmi), mBalance);
        jmi.setAssetBalanceOf(address(mockUSDC), totalAssets);
        jmi.setTotalAssets(totalAssets);
        jmi.setTotalSupply(totalSupply);

        uint256 mBacking = totalSupply < totalAssets ? 0 : totalSupply - totalAssets;
        uint256 expectedYield = mBalance > mBacking ? mBalance - mBacking : 0;

        assertEq(jmi.yield(), expectedYield);
    }

    /* ============ claimYield ============ */

    function test_claimYield() external {
        // M backing = totalSupply - totalAssets = 2_500e6 - 1_500e6 = 1_000e6
        // Expected yield = mBalance - mBacking = 1_500e6 - 1_000e6 = 500e6
        uint256 yield = 500e6;

        mToken.setBalanceOf(address(jmi), 1_500e6);
        mockUSDC.mint(address(jmi), 1_500e6);
        jmi.setAssetBalanceOf(address(mockUSDC), 1_500e6);
        jmi.setTotalAssets(1_500e6);
        jmi.setTotalSupply(2_500e6);

        assertEq(jmi.yield(), yield);

        vm.expectEmit();
        emit IMYieldToOne.YieldClaimed(yield);

        assertEq(jmi.claimYield(), yield);
        assertEq(jmi.yield(), 0);

        assertEq(mToken.balanceOf(address(jmi)), 1_500e6);
        assertEq(mockUSDC.balanceOf(address(jmi)), 1_500e6);
        assertEq(jmi.assetBalanceOf(address(mockUSDC)), 1_500e6);
        assertEq(jmi.totalAssets(), 1_500e6);
        assertEq(jmi.totalSupply(), 3_000e6);

        assertEq(mToken.balanceOf(yieldRecipient), 0);
        assertEq(jmi.getBalanceOf(yieldRecipient), yield);
    }

    /* ============ _fromAssetToExtensionAmount ============ */

    function testFuzz_fromAssetToExtensionAmount_lessDecimals(uint256 amount) external {
        uint256 scaleFactor = 10 ** 2;

        // Overflow can occur for very large amounts when scaling up
        if (amount > type(uint256).max / scaleFactor) {
            vm.expectRevert();
            jmi.fromAssetToExtensionAmount(address(mockAsset4Decimals), amount);
        } else {
            assertEq(jmi.fromAssetToExtensionAmount(address(mockAsset4Decimals), amount), amount * scaleFactor);
        }
    }

    function testFuzz_fromAssetToExtensionAmount_sameDecimals(uint256 amount) external {
        assertEq(jmi.fromAssetToExtensionAmount(address(mockUSDC), amount), amount);
    }

    function testFuzz_fromAssetToExtensionAmount_moreDecimals(uint256 amount) external {
        assertEq(jmi.fromAssetToExtensionAmount(address(mockDAI), amount), uint256(amount) / 10 ** 12);

        // MUST always truncate down when converting to fewer decimals
        assertLe(jmi.fromAssetToExtensionAmount(address(mockDAI), amount), uint256(amount));
    }

    /* ============ _fromExtensionToAssetAmount ============ */

    function testFuzz_fromExtensionToAssetAmount_lessDecimals(uint256 amount) external {
        assertEq(jmi.fromExtensionToAssetAmount(address(mockAsset4Decimals), amount), amount / 10 ** 2);

        // MUST always truncate down when converting to fewer decimals
        assertLe(jmi.fromExtensionToAssetAmount(address(mockAsset4Decimals), amount), amount);
    }

    function testFuzz_fromExtensionToAssetAmount_sameDecimals(uint256 amount) external {
        assertEq(jmi.fromExtensionToAssetAmount(address(mockUSDC), amount), amount);
    }

    function testFuzz_fromExtensionToAssetAmount_moreDecimals(uint256 amount) external {
        uint256 scaleFactor = 10 ** 12;

        // Overflow can occur for very large amounts when scaling up
        if (amount > type(uint256).max / scaleFactor) {
            vm.expectRevert();
            jmi.fromExtensionToAssetAmount(address(mockDAI), amount);
        } else {
            assertEq(jmi.fromExtensionToAssetAmount(address(mockDAI), amount), amount * scaleFactor);
        }
    }

    /* ============ Helper Functions ============ */

    /// @dev Returns a 33-byte compressed-secp256k1-shaped public key; contents are arbitrary.
    function _validPubKey(bytes1 marker) internal pure returns (bytes memory) {
        bytes memory key = new bytes(33);
        key[0] = 0x02; // compressed-secp256k1 even-Y prefix
        for (uint256 i = 1; i < 33; ++i) {
            key[i] = marker;
        }
        return key;
    }

    /// @dev Installs the contract keypair through the admin path.
    function _installContractKey() internal {
        vm.prank(admin);
        jmi.setContractKey(sbytes32(bytes32(uint256(0xC0FFEE))), _validPubKey(0xAA));
    }

    /// @dev Helper function to randomly select one of the 3 stablecoins based on a seed
    function _getRandomAsset(uint256 seed) internal view returns (MockERC20 asset, uint256 cap, uint8 decimals) {
        uint256 choice = seed % 3;

        if (choice == 0) {
            return (mockUSDC, mockUSDCCap, 6);
        } else if (choice == 1) {
            return (mockAsset4Decimals, mockAsset4DecimalsCap, 4);
        } else {
            return (mockDAI, mockDAICap, 18);
        }
    }
}
