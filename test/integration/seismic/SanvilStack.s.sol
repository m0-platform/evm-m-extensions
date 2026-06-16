// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Script } from "../../../lib/forge-std/src/Script.sol";
import { console } from "../../../lib/forge-std/src/console.sol";

import { TransparentUpgradeableProxy } from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { MYieldToOneForcedTransfer } from "../../../src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";
import { SwapFacility } from "../../../src/swap/SwapFacility.sol";

import { MockM, MockRegistrar } from "../../utils/Mocks.sol";

/// @dev Deploys a self-contained MYieldToOneForcedTransfer stack on a local sanvil node.
///      Driven by run-sanvil-e2e.sh — NOT for any public network (MockM, deployer holds every role).
contract SanvilStack is Script {
    function run() external {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        vm.startBroadcast(deployer);

        MockM mToken = new MockM();
        MockRegistrar registrar = new MockRegistrar();

        SwapFacility swapFacility = SwapFacility(
            address(
                new TransparentUpgradeableProxy(
                    address(new SwapFacility(address(mToken), address(registrar))),
                    deployer,
                    abi.encodeWithSelector(SwapFacility.initialize.selector, deployer, deployer)
                )
            )
        );

        MYieldToOneForcedTransfer extension = MYieldToOneForcedTransfer(
            address(
                new TransparentUpgradeableProxy(
                    address(new MYieldToOneForcedTransfer(address(mToken), address(swapFacility))),
                    deployer,
                    abi.encodeWithSelector(
                        MYieldToOneForcedTransfer.initialize.selector,
                        "Seismic Dollar (sanvil)",
                        "USDS",
                        deployer, // yieldRecipient
                        deployer, // admin
                        deployer, // freezeManager
                        deployer, // yieldRecipientManager
                        deployer, // pauser
                        deployer // forcedTransferManager
                    )
                )
            )
        );

        registrar.setEarner(address(extension), true);
        swapFacility.grantRole(swapFacility.M_SWAPPER_ROLE(), deployer);

        vm.stopBroadcast();

        console.log("M_TOKEN=%s", address(mToken));
        console.log("SWAP_FACILITY=%s", address(swapFacility));
        console.log("EXTENSION=%s", address(extension));
    }
}
