// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { JMIExtension } from "../../src/projects/jmi/JMIExtension.sol";

contract JMIExtensionHarness is JMIExtension {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address mToken, address swapFacility) JMIExtension(mToken, swapFacility) {}

    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient,
        address admin,
        address assetCapManager,
        address freezeManager,
        address pauser,
        address yieldRecipientManager
    ) public override initializer {
        super.initialize(
            name,
            symbol,
            yieldRecipient,
            admin,
            assetCapManager,
            freezeManager,
            pauser,
            yieldRecipientManager
        );
    }

    function setAssetBalanceOf(address account, uint256 amount) external {
        _getJMIExtensionStorageLocation().assets[account].balance = uint240(amount);
    }

    function setBalanceOf(address account, uint256 amount) external {
        _getMYieldToOneStorageLocation().balanceOf[account] = suint256(amount);
    }

    /// @dev Bypasses the public `balanceOf` gate.
    function getBalanceOf(address account) external view returns (uint256) {
        return uint256(_getMYieldToOneStorageLocation().balanceOf[account]);
    }

    /// @dev Reads the encrypted-event nonce counter.
    function getEncryptedEventNonce() external view returns (uint256) {
        return _getMYieldToOneStorageLocation().encryptedEventNonce;
    }

    function setTotalAssets(uint256 amount) external {
        _getJMIExtensionStorageLocation().totalAssets = amount;
    }

    function setTotalSupply(uint256 amount) external {
        _getMYieldToOneStorageLocation().totalSupply = amount;
    }

    function fromAssetToExtensionAmount(address asset, uint256 amount) external view returns (uint256) {
        return _fromAssetToExtensionAmount(asset, amount);
    }

    function fromExtensionToAssetAmount(address asset, uint256 amount) external view returns (uint256) {
        return _fromExtensionToAssetAmount(asset, amount);
    }
}
