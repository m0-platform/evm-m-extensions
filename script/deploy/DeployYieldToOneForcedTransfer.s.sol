// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { DeployBase } from "./DeployBase.s.sol";
import { console } from "forge-std/console.sol";

contract DeployYieldToOneForcedTransfer is DeployBase {
    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        YieldToOneForcedTransferConfig memory extensionConfig;

        extensionConfig.contractName = vm.envString("CONTRACT_NAME");
        extensionConfig.extensionName = vm.envString("EXTENSION_NAME");
        extensionConfig.symbol = vm.envString("EXTENSION_SYMBOL");
        extensionConfig.yieldRecipient = vm.envAddress("YIELD_RECIPIENT");
        extensionConfig.admin = vm.envAddress("ADMIN");
        extensionConfig.freezeManager = vm.envAddress("FREEZE_MANAGER");
        extensionConfig.yieldRecipientManager = vm.envAddress("YIELD_RECIPIENT_MANAGER");
        extensionConfig.pauser = vm.envAddress("PAUSER");
        extensionConfig.forcedTransferManager = vm.envAddress("FORCED_TRANSFER_MANAGER");
        extensionConfig.allowlistAdmin = vm.envAddress("ALLOWLIST_ADMIN");

        // Verify predicted address (if PREDICTED_ADDRESS env var is set)
        if (_shouldVerifyPredictedAddress()) {
            _verifyPredictedAddress(deployer, extensionConfig.contractName);
        }

        vm.startBroadcast(deployer);

        (
            address yieldToOneForcedTransferImplementation,
            address yieldToOneForcedTransferProxy,
            address yieldToOneForcedTransferProxyAdmin
        ) = _deployYieldToOneForcedTransfer(deployer, extensionConfig);

        vm.stopBroadcast();

        console.log("YieldToOneForcedTransferImplementation:", yieldToOneForcedTransferImplementation);
        console.log("YieldToOneForcedTransferProxy:", yieldToOneForcedTransferProxy);
        console.log("YieldToOneForcedTransferProxyAdmin:", yieldToOneForcedTransferProxyAdmin);

        _writeDeployment(block.chainid, _getExtensionName(), yieldToOneForcedTransferProxy);
    }
}
