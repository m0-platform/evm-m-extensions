// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { MYieldToOneForcedTransfer } from "../../src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";

contract MYieldToOneForcedTransferHarness is MYieldToOneForcedTransfer {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address mToken, address swapFacility) MYieldToOneForcedTransfer(mToken, swapFacility) {}

    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient,
        address yieldRecipientManager,
        address admin,
        address freezeManager,
        address pauser,
        address forcedTransferManager
    ) public override initializer {
        super.initialize(
            name,
            symbol,
            yieldRecipient,
            yieldRecipientManager,
            admin,
            freezeManager,
            pauser,
            forcedTransferManager
        );
    }

    function setBalanceOf(address account, uint256 amount) external {
        _getMYieldToOneStorageLocation().balanceOf[account] = suint256(amount);
    }

    /// @dev Bypasses the public `balanceOf` gate.
    function getBalanceOf(address account) external view returns (uint256) {
        return uint256(_getMYieldToOneStorageLocation().balanceOf[account]);
    }

    function setShieldedAllowance(address owner, address spender, uint256 amount) external {
        _getMYieldToOneStorageLocation().shieldedAllowance[owner][spender] = suint256(amount);
    }

    /// @dev Bypasses the gated `allowance` read.
    function getShieldedAllowance(address owner, address spender) external view returns (uint256) {
        return uint256(_getMYieldToOneStorageLocation().shieldedAllowance[owner][spender]);
    }

    /// @dev Reads the encrypted-event nonce counter.
    function getEncryptedEventNonce() external view returns (uint256) {
        return _getMYieldToOneStorageLocation().encryptedEventNonce;
    }
}
