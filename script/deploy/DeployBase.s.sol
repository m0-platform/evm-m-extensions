// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { DeployHelpers } from "../../lib/common/script/deploy/DeployHelpers.sol";

import { Options } from "../../lib/openzeppelin-foundry-upgrades/src/Options.sol";
import { Upgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { ScriptBase } from "../ScriptBase.s.sol";

import { MEarnerManager } from "../../src/projects/earnerManager/MEarnerManager.sol";
import { MYieldToOne } from "../../src/projects/yieldToOne/MYieldToOne.sol";
import { MYieldToOneForcedTransfer } from "../../src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";
import { MYieldFee } from "../../src/projects/yieldToAllWithFee/MYieldFee.sol";
import { JMIExtension } from "../../src/projects/jmi/JMIExtension.sol";

import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { UniswapV3SwapAdapter } from "../../src/swap/UniswapV3SwapAdapter.sol";

import { console } from "forge-std/console.sol";

contract DeployBase is DeployHelpers, ScriptBase {
    Options public deployOptions;

    /**
     * @notice Checks if PREDICTED_ADDRESS env var is set
     * @return True if PREDICTED_ADDRESS is set, false otherwise
     */
    function _shouldVerifyPredictedAddress() internal view returns (bool) {
        return vm.envOr("PREDICTED_ADDRESS", address(0)) != address(0);
    }

    /**
     * @notice Verifies predicted address against computed CREATE3 address
     * @dev Computes expected address and compares with PREDICTED_ADDRESS env var
     * @param deployer The deployer address
     * @param contractName Contract Name used for salt computation
     */
    function _verifyPredictedAddress(address deployer, string memory contractName) internal view {
        address predictedAddress = vm.envAddress("PREDICTED_ADDRESS");
        address computedAddress = _getCreate3Address(deployer, _computeSalt(deployer, contractName));

        console.log("================================================================================");
        console.log(string.concat("PREDICTED_ADDRESS verification for ", contractName));
        console.log("================================================================================");
        console.log("Predicted address: ", predictedAddress);
        console.log("Computed address:  ", computedAddress);

        require(
            computedAddress == predictedAddress,
            string.concat(
                contractName,
                " address mismatch! Predicted: ",
                vm.toString(predictedAddress),
                ", but computed: ",
                vm.toString(computedAddress)
            )
        );

        console.log("--------------------------------------------------------------------------------");
        console.log(string.concat("SUCCESS: Address verification passed for ", contractName, "!"));
        console.log("================================================================================");
    }

    function _deploySwapFacility(
        address deployer,
        address pauser
    ) internal returns (address implementation, address proxy, address proxyAdmin) {
        DeployConfig memory config = _getDeployConfig(block.chainid);

        implementation = address(new SwapFacility(config.mToken, config.registrar));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            config.admin,
            abi.encodeWithSelector(SwapFacility.initialize.selector, config.admin, pauser),
            _computeSalt(deployer, "SwapFacility")
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deploySwapAdapter(address deployer) internal returns (address swapAdapter) {
        DeployConfig memory config = _getDeployConfig(block.chainid);

        swapAdapter = _deployCreate3(
            abi.encodePacked(
                type(UniswapV3SwapAdapter).creationCode,
                abi.encode(
                    config.wrappedMToken,
                    _getSwapFacility(),
                    config.uniswapV3Router,
                    config.admin,
                    _getWhitelistedTokens(block.chainid)
                )
            ),
            _computeSalt(deployer, "SwapAdapter")
        );
    }

    function _deployMEarnerManager(
        address deployer,
        MEarnerManagerConfig memory extensionConfig
    ) internal returns (address implementation, address proxy, address proxyAdmin) {
        DeployConfig memory config = _getDeployConfig(block.chainid);

        implementation = address(new MEarnerManager(config.mToken, _getSwapFacility()));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            extensionConfig.admin,
            abi.encodeWithSelector(
                MEarnerManager.initialize.selector,
                extensionConfig.extensionName,
                extensionConfig.symbol,
                extensionConfig.admin,
                extensionConfig.earnerManager,
                extensionConfig.feeRecipient,
                extensionConfig.pauser
            ),
            _computeSalt(deployer, extensionConfig.contractName)
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);

        return (implementation, proxy, proxyAdmin);
    }

    function _deployYieldToOne(
        address deployer,
        YieldToOneConfig memory extensionConfig
    ) internal returns (address implementation, address proxy, address proxyAdmin) {
        DeployConfig memory config = _getDeployConfig(block.chainid);

        implementation = address(new MYieldToOne(config.mToken, _getSwapFacility()));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            extensionConfig.admin,
            _yieldToOneInitData(extensionConfig),
            _computeSalt(deployer, extensionConfig.contractName)
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployYieldToOneForcedTransfer(
        address deployer,
        YieldToOneForcedTransferConfig memory extensionConfig
    ) internal returns (address implementation, address proxy, address proxyAdmin) {
        DeployConfig memory config = _getDeployConfig(block.chainid);

        implementation = address(new MYieldToOneForcedTransfer(config.mToken, _getSwapFacility()));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            extensionConfig.admin,
            _yieldToOneForcedTransferInitData(extensionConfig),
            _computeSalt(deployer, extensionConfig.contractName)
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _deployJMIExtension(
        address deployer,
        JMIExtensionConfig memory extensionConfig
    ) internal returns (address implementation, address proxy, address proxyAdmin) {
        DeployConfig memory config = _getDeployConfig(block.chainid);

        implementation = address(new JMIExtension(config.mToken, _getSwapFacility()));

        proxy = _deployCreate3TransparentProxy(
            implementation,
            extensionConfig.admin,
            _jmiExtensionInitData(extensionConfig),
            _computeSalt(deployer, extensionConfig.contractName)
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _yieldToOneInitData(YieldToOneConfig memory c) private pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MYieldToOne.initialize.selector,
                c.extensionName,
                c.symbol,
                c.yieldRecipient,
                c.admin,
                c.freezeManager,
                c.yieldRecipientManager,
                c.pauser,
                c.allowlistAdmin
            );
    }

    function _yieldToOneForcedTransferInitData(
        YieldToOneForcedTransferConfig memory c
    ) private pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MYieldToOneForcedTransfer.initialize.selector,
                c.extensionName,
                c.symbol,
                c.yieldRecipient,
                c.admin,
                c.freezeManager,
                c.yieldRecipientManager,
                c.pauser,
                c.forcedTransferManager,
                c.allowlistAdmin
            );
    }

    function _jmiExtensionInitData(JMIExtensionConfig memory c) private pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                JMIExtension.initialize.selector,
                c.extensionName,
                c.symbol,
                c.yieldRecipient,
                c.admin,
                c.assetCapManager,
                c.freezeManager,
                c.pauser,
                c.yieldRecipientManager,
                c.allowlistAdmin
            );
    }

    function _deployYieldToAllWithFee(
        address deployer,
        YieldToAllWithFeeConfig memory extensionConfig
    ) internal returns (address implementation, address proxy, address proxyAdmin) {
        DeployConfig memory config = _getDeployConfig(block.chainid);

        implementation = address(new MYieldFee(config.mToken, _getSwapFacility()));

        // delegate to helper function to avoid stack too deep
        proxy = _deployYieldToAllWithFeeProxy(deployer, implementation, extensionConfig);
        proxyAdmin = Upgrades.getAdminAddress(proxy);

        return (implementation, proxy, proxyAdmin);
    }

    // helper function to avoid stack too deep
    function _deployYieldToAllWithFeeProxy(
        address deployer,
        address implementation,
        YieldToAllWithFeeConfig memory extensionConfig
    ) private returns (address proxy) {
        proxy = _deployCreate3TransparentProxy(
            implementation,
            extensionConfig.admin,
            abi.encodeWithSelector(
                MYieldFee.initialize.selector,
                extensionConfig.extensionName,
                extensionConfig.symbol,
                extensionConfig.feeRate,
                extensionConfig.feeRecipient,
                extensionConfig.admin,
                extensionConfig.feeManager,
                extensionConfig.claimRecipientManager,
                extensionConfig.freezeManager,
                extensionConfig.pauser
            ),
            _computeSalt(deployer, extensionConfig.contractName)
        );
    }
}
