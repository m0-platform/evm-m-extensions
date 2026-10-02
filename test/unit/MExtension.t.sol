// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { Initializable } from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import { Ownable } from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import { IProxyAdmin } from "../../lib/openzeppelin-foundry-upgrades/src/internal/interfaces/IProxyAdmin.sol";

import { Upgrades, UnsafeUpgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

import { IMExtension } from "../../src/interfaces/IMExtension.sol";

import { MExtensionHarness } from "../harness/MExtensionHarness.sol";

import { BaseUnitTest } from "../utils/BaseUnitTest.sol";
import { MExtensionUpgrade } from "../utils/Mocks.sol";

contract MExtensionUnitTests is BaseUnitTest {
    MExtensionHarness public mExtension;
    IProxyAdmin public proxyAdmin;

    string public constant NAME = "M Extension";
    string public constant SYMBOL = "ME";

    function setUp() public override {
        super.setUp();

        mExtension = MExtensionHarness(
            Upgrades.deployTransparentProxy(
                "MExtensionHarness.sol:MExtensionHarness",
                admin,
                abi.encodeWithSelector(MExtensionHarness.initialize.selector, NAME, SYMBOL),
                mExtensionDeployOptions
            )
        );

        proxyAdmin = IProxyAdmin(Upgrades.getAdminAddress(address(mExtension)));
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mExtension.name(), NAME);
        assertEq(mExtension.symbol(), SYMBOL);
        assertEq(mExtension.decimals(), 6);
        assertEq(mExtension.mToken(), address(mToken));
        assertEq(mExtension.swapFacility(), address(swapFacility));
    }

    function test_initialize_zeroMToken() external {
        vm.expectRevert(IMExtension.ZeroMToken.selector);
        new MExtensionHarness(address(0), address(swapFacility));
    }

    function test_initialize_zeroSwapFacility() external {
        vm.expectRevert(IMExtension.ZeroSwapFacility.selector);
        new MExtensionHarness(address(mToken), address(0));
    }

    /* ============ wrap ============ */

    function test_wrap_onlySwapFacility() external {
        vm.expectRevert(IMExtension.NotSwapFacility.selector);
        mExtension.wrap(alice, 1);
    }

    function test_wrap_invalidRecipient() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(address(swapFacility));
        mExtension.wrap(address(0), 1);
    }

    function test_wrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        mExtension.wrap(alice, 0);
    }

    function test_wrap() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(address(swapFacility), amount);

        vm.expectCall(
            address(mToken),
            abi.encodeWithSelector(mToken.transferFrom.selector, address(swapFacility), address(mExtension), amount)
        );

        vm.prank(address(swapFacility));
        mExtension.wrap(alice, amount);
    }

    function testFuzz_wrap(uint256 amount, address recipient) external {
        if (recipient == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));
        } else if (amount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        } else {
            mToken.setBalanceOf(address(swapFacility), amount);

            vm.expectCall(
                address(mToken),
                abi.encodeWithSelector(mToken.transferFrom.selector, address(swapFacility), address(mExtension), amount)
            );
        }

        vm.prank(address(swapFacility));
        mExtension.wrap(recipient, amount);
    }

    /* ============ unwrap ============ */

    function test_unwrap_onlySwapFacility() external {
        vm.expectRevert(IMExtension.NotSwapFacility.selector);
        mExtension.unwrap(alice, 1);
    }

    function test_unwrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(address(swapFacility));
        mExtension.unwrap(alice, 0);
    }

    function test_unwrap_insufficientBalance() external {
        uint256 amount = 1_000e6;

        vm.expectRevert(
            abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, address(swapFacility), 0, amount)
        );

        vm.prank(address(swapFacility));
        mExtension.unwrap(alice, amount);
    }

    function test_unwrap() external {
        uint256 amount = 1_000e6;

        mExtension.setBalanceOf(address(swapFacility), amount);
        mToken.setBalanceOf(address(mExtension), amount);

        vm.expectCall(address(mToken), abi.encodeWithSelector(mToken.transfer.selector, address(swapFacility), amount));

        vm.prank(address(swapFacility));
        mExtension.unwrap(alice, amount);
    }

    function testFuzz_unwrap(uint256 amount, uint256 balance) external {
        mExtension.setBalanceOf(address(swapFacility), balance);
        mToken.setBalanceOf(address(mExtension), amount);

        if (amount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        } else if (balance < amount) {
            vm.expectRevert(
                abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, address(swapFacility), balance, amount)
            );
        } else {
            vm.expectCall(
                address(mToken),
                abi.encodeWithSelector(mToken.transfer.selector, address(swapFacility), amount)
            );
        }

        vm.prank(address(swapFacility));
        mExtension.unwrap(alice, amount);
    }

    /* ============ transfer ============ */

    function test_transfer_invalidRecipient() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));
        mExtension.transfer(address(0), 1);
    }

    function test_transfer_insufficientBalance() external {
        uint256 amount = 1_000e6;

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 0, amount));

        vm.prank(alice);
        mExtension.transfer(bob, amount);
    }

    function test_transfer_zeroAmount() external {
        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, 0);

        vm.prank(alice);
        mExtension.transfer(bob, 0);
    }

    function test_transfer() external {
        uint256 amount = 1_000e6;
        mExtension.setBalanceOf(alice, amount);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount);

        vm.prank(alice);
        mExtension.transfer(bob, amount);
    }

    function testFuzz_transfer(address recipient, uint256 amount, uint256 balance) external {
        mExtension.setBalanceOf(alice, balance);

        if (recipient == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));
        } else if (amount == 0) {
            vm.expectEmit();
            emit IERC20.Transfer(alice, recipient, 0);
        } else if (balance < amount) {
            vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, balance, amount));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(alice, recipient, amount);
        }

        vm.prank(alice);
        mExtension.transfer(recipient, amount);
    }

    /* ============ enableEarning ============ */

    function test_enableEarning_revertsIfEarningIsEnabled() external {
        mToken.setIsEarning(address(mExtension), true);

        vm.expectRevert(IMExtension.EarningIsEnabled.selector);
        mExtension.enableEarning();
    }

    function test_enableEarning() external {
        vm.mockCall(
            address(mToken),
            abi.encodeWithSelector(mToken.currentIndex.selector),
            abi.encode(expectedCurrentIndex)
        );

        vm.expectCall(address(mToken), abi.encodeWithSelector(mToken.startEarning.selector));

        vm.expectEmit();
        emit IMExtension.EarningEnabled(expectedCurrentIndex);

        mExtension.enableEarning();

        assertTrue(mExtension.isEarningEnabled());
    }

    /* ============ disableEarning =========== */

    function test_disableEarning_earningIsDisabled() external {
        mToken.setIsEarning(address(mExtension), false);

        vm.expectRevert(IMExtension.EarningIsDisabled.selector);
        mExtension.disableEarning();
    }

    function test_disableEarning() external {
        mToken.setIsEarning(address(mExtension), true);

        vm.mockCall(
            address(mToken),
            abi.encodeWithSelector(mToken.currentIndex.selector),
            abi.encode(expectedCurrentIndex)
        );

        vm.expectCall(address(mToken), abi.encodeWithSelector(mToken.stopEarning.selector, address(mExtension)));

        vm.expectEmit();
        emit IMExtension.EarningDisabled(expectedCurrentIndex);

        mExtension.disableEarning();

        assertFalse(mExtension.isEarningEnabled());
    }

    /* ============ currentIndex =========== */

    function test_currentIndex() external {
        vm.expectCall(address(mToken), abi.encodeWithSelector(mToken.currentIndex.selector));

        mExtension.currentIndex();
    }

    /* ============ isEarningEnabled =========== */

    function test_isEarningEnabled() external {
        vm.expectCall(address(mToken), abi.encodeWithSelector(mToken.isEarning.selector, address(mExtension)));

        mExtension.isEarningEnabled();
    }

    /* ============ upgrade ============ */

    function test_initializerDisabled() external {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));

        vm.prank(alice);
        MExtensionHarness(Upgrades.getImplementationAddress(address(mExtension))).initialize(NAME, SYMBOL);
    }

    function test_upgrade_onlyAdmin() external {
        address v2implementation = address(new MExtensionUpgrade());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));

        vm.prank(alice);
        proxyAdmin.upgradeAndCall(address(mExtension), v2implementation, "");
    }

    function test_upgrade() public {
        UnsafeUpgrades.upgradeProxy(address(mExtension), address(new MExtensionUpgrade()), "", admin);

        assertEq(MExtensionUpgrade(address(mExtension)).bar(), 1);
    }
}
