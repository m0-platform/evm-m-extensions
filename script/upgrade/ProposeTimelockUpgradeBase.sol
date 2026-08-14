// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { console } from "../../lib/forge-std/src/console.sol";

import { IProxyAdmin } from "../../lib/openzeppelin-foundry-upgrades/src/internal/interfaces/IProxyAdmin.sol";
import { Options } from "../../lib/openzeppelin-foundry-upgrades/src/Options.sol";
import { Upgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { TimelockController } from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

import { Safe } from "../../lib/common/lib/safe-utils/src/Safe.sol";
import { TimelockBatchBase } from "../../lib/common/script/TimelockBatchBase.sol";

import { SwapFacility } from "../../src/swap/SwapFacility.sol";

import { Config } from "../Config.sol";

/**
 * @title  ProposeTimelockUpgradeBase
 * @notice Base contract for proposing and executing timelock-routed upgrade scripts.
 * @dev    NOTE: This contract duplicates `Deployments` struct and `_readDeployment` from ScriptBase
 *         instead of inheriting it. This is intentional to avoid diamond inheritance issues
 *         in the IDE (both TimelockBatchBase and ScriptBase extend Script).
 */
contract ProposeTimelockUpgradeBase is TimelockBatchBase, Config {
    using Safe for *;

    Safe.Client internal _safeClient;

    /// @dev Duplicated from ScriptBase to avoid diamond inheritance with TimelockBatchBase
    struct Deployments {
        address[] extensionAddresses;
        string[] extensionNames;
        address swapAdapter;
        address swapFacility;
    }

    function _proposeTimelockSwapFacilityUpgrade(
        address proposer,
        address safeMultisig,
        address timelock,
        address swapFacility,
        address pauser
    ) internal {
        string memory contractPath = "SwapFacility.sol:SwapFacility";
        DeployConfig memory config = _getDeployConfig(block.chainid);

        address proxyAdmin = Upgrades.getAdminAddress(swapFacility);

        console.log("================================================================================");
        console.log("ProposeTimelockSwapFacilityUpgrade");
        console.log("================================================================================");
        console.log("Chain ID:            ", block.chainid);
        console.log("Proposer:            ", proposer);
        console.log("Proposer Multisig:   ", safeMultisig);
        console.log("Timelock:            ", timelock);
        console.log("SwapFacility Proxy:  ", swapFacility);
        console.log("ProxyAdmin:          ", proxyAdmin);
        console.log("M Token:             ", config.mToken);
        console.log("Registrar:           ", config.registrar);
        console.log("Pauser:              ", pauser);
        console.log("================================================================================");

        {
            // Step 1: Validate upgrade safety and deploy new implementation using Upgrades.prepareUpgrade
            // Note: unsafeSkipStorageCheck=true skips storage layout comparison (no previous version available)
            // but still validates upgrade safety rules (no constructor logic, proper initializers, etc.)
            Options memory opts;
            opts.constructorData = abi.encode(config.mToken, config.registrar);
            opts.unsafeSkipStorageCheck = true;

            console.log("Validating and deploying new implementation...");
            vm.startBroadcast(proposer);
            address newImplementation = Upgrades.prepareUpgrade(contractPath, opts);
            vm.stopBroadcast();

            console.log("New Implementation:  ", newImplementation);

            // Step 2: Prepare the upgradeAndCall data
            bytes memory initializeV2Data = abi.encodeWithSelector(SwapFacility.initializeV2.selector, pauser);

            bytes memory upgradeAndCallData = abi.encodeCall(
                IProxyAdmin.upgradeAndCall,
                (swapFacility, newImplementation, initializeV2Data)
            );

            // Step 3: Add upgradeAndCall to timelock batch
            _addToTimelockBatch(proxyAdmin, upgradeAndCallData);
        }

        // Step 4: Simulate the batch as the timelock
        console.log("--------------------------------------------------------------------------------");
        console.log("Simulating batch as timelock...");
        _simulateBatch(timelock);
        console.log("Simulation successful!");

        // Step 5: Encode scheduleBatch call data
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();
        console.log("Timelock min delay:  ", minDelay);

        bytes memory scheduleBatchData = _getScheduleBatchCallData(bytes32(0), bytes32(0), minDelay);

        // Step 6: Propose the scheduleBatch call to the proposer Safe multisig
        console.log("--------------------------------------------------------------------------------");
        console.log("Proposing scheduleBatch to Safe...");
        _safeClient.initialize(safeMultisig);

        vm.startBroadcast(proposer);
        _safeClient.proposeTransaction(timelock, scheduleBatchData, proposer);
        vm.stopBroadcast();

        console.log("================================================================================");
        console.log("SwapFacility timelock upgrade proposed successfully!");
        console.log("================================================================================");
    }

    /// @dev Duplicated from ScriptBase to avoid diamond inheritance with TimelockBatchBase
    function _deployOutputPath(uint256 chainId_) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", vm.toString(chainId_), ".json");
    }

    /// @dev Duplicated from ScriptBase to avoid diamond inheritance with TimelockBatchBase
    function _readDeployment(uint256 chainId_) internal returns (Deployments memory) {
        if (!vm.isFile(_deployOutputPath(chainId_))) {
            return Deployments(new address[](0), new string[](0), address(0), address(0));
        }

        bytes memory data = vm.parseJson(vm.readFile(_deployOutputPath(chainId_)));

        return abi.decode(data, (Deployments));
    }
}
