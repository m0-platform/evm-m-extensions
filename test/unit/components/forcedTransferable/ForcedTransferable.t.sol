// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IAccessControl } from "../../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Upgrades, UnsafeUpgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IForcedTransferable } from "../../../../src/components/forcedTransferable/IForcedTransferable.sol";
import { IArrayErrors } from "../../../../src/interfaces/IArrayErrors.sol";

import { ForcedTransferableHarness } from "../../../harness/ForcedTransferableHarness.sol";

import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract ForcedTransferableUnitTests is BaseUnitTest {
    ForcedTransferableHarness public forcedTransfer;

    function setUp() public override {
        super.setUp();

        forcedTransfer = ForcedTransferableHarness(
            Upgrades.deployTransparentProxy(
                "ForcedTransferableHarness.sol:ForcedTransferableHarness",
                admin,
                abi.encodeWithSelector(ForcedTransferableHarness.initialize.selector, forcedTransferManager)
            )
        );
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertTrue(
            IAccessControl(address(forcedTransfer)).hasRole(FORCED_TRANSFER_MANAGER_ROLE, forcedTransferManager)
        );
    }

    function test_initialize_zeroForcedTransferManager() external {
        address implementation = address(new ForcedTransferableHarness());

        vm.expectRevert(IForcedTransferable.ZeroForcedTransferManager.selector);
        UnsafeUpgrades.deployTransparentProxy(
            implementation,
            admin,
            abi.encodeWithSelector(ForcedTransferableHarness.initialize.selector, address(0))
        );
    }

    /* ============ forceTransfer ============ */

    function test_forceTransfer_onlyForcedTransferManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                FORCED_TRANSFER_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        forcedTransfer.forceTransfer(bob, carol, 100);
    }

    /* ============ forceTransfers ============ */

    function test_forceTransfers_onlyForcedTransferManager() public {
        address[] memory froms = new address[](2);
        address[] memory tos = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        froms[0] = alice;
        froms[1] = bob;
        tos[0] = carol;
        tos[1] = david;
        amounts[0] = 10;
        amounts[1] = 20;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                FORCED_TRANSFER_MANAGER_ROLE
            )
        );
        vm.prank(alice);
        forcedTransfer.forceTransfers(froms, tos, amounts);
    }

    function test_forceTransfers_arrayLengthMismatch() public {
        address[] memory froms = new address[](2);
        address[] memory tos = new address[](1);
        uint256[] memory amounts = new uint256[](2);

        froms[0] = alice;
        froms[1] = bob;
        tos[0] = carol;
        amounts[0] = 10;
        amounts[1] = 20;

        vm.prank(forcedTransferManager);
        vm.expectRevert(IArrayErrors.ArrayLengthMismatch.selector);
        forcedTransfer.forceTransfers(froms, tos, amounts);
    }
}
