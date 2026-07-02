// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import { IArrayErrors } from "../../interfaces/IArrayErrors.sol";

interface IForcedTransferable is IArrayErrors {
    /* ============ Events ============ */

    /**
     * @notice Emitted when tokens are forcefully transferred from a frozen account.
     */
    event ForcedTransfer(
        address indexed frozenAccount,
        address indexed recipient,
        address indexed forcedTransferManager,
        uint256 amount
    );

    /* ============ Custom Errors ============ */

    /// @notice Error for zero forced transfer manager address
    error ZeroForcedTransferManager();

    /* ============ Interactive Functions ============ */
    /**
     * @notice Forcefully transfers tokens from a frozen account to a recipient.
     * @dev    MUST only be callable by the FORCE_TRANSFER_MANAGER_ROLE.
     * @dev    SHOULD revert if `frozenAccount` is not frozen.
     * @dev    SHOULD revert if `recipient` is the zero address.
     * @dev    SHOULD revert if `amount` exceeds the balance of `frozenAccount`.
     * @param  frozenAccount The address of the frozen account from which tokens are seized.
     * @param  recipient     The address receiving the seized tokens.
     * @param  amount        The amount of tokens to transfer.
     */
    function forceTransfer(address frozenAccount, address recipient, uint256 amount) external;

    /**
     * @notice Forcefully transfers tokens from multiple frozen accounts to multiple recipients.
     * @dev    MUST only be callable by the FORCE_TRANSFER_MANAGER_ROLE.
     * @dev    SHOULD revert if any `frozenAccount` is not frozen.
     * @dev    SHOULD revert if array lengths do not match.
     * @dev    SHOULD revert if any `recipient` is the zero address.
     * @dev    SHOULD revert if any `amount` exceeds the balance of the corresponding `frozenAccount`.
     * @param  frozenAccounts The array of frozen accounts from which tokens are seized.
     * @param  recipients     The array of recipient addresses.
     * @param  amounts        The array of amounts to transfer for each account.
     */
    function forceTransfers(
        address[] calldata frozenAccounts,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can manage force transfers.
    function FORCED_TRANSFER_MANAGER_ROLE() external view returns (bytes32);
}
