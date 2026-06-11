// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";

import { IMYieldToOne } from "./interfaces/IMYieldToOne.sol";

import { MYieldToOne } from "./MYieldToOne.sol";
import { ForcedTransferable } from "../../components/forcedTransferable/ForcedTransferable.sol";

/**
 * @title  MYieldToOneForcedTransfer
 * @notice MYieldToOne extension with Pausable and ForcedTransferable functionality for compliant deployments.
 * @author M0 Labs
 */

contract MYieldToOneForcedTransfer is MYieldToOne, ForcedTransferable {
    /* ============ Constructor ============ */

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     * @notice Constructs MYieldToOne Implementation contract
     * @dev    Sets immutable storage.
     * @param  mToken       The address of $M token.
     * @param  swapFacility The address of Swap Facility.
     */
    constructor(address mToken, address swapFacility) MYieldToOne(mToken, swapFacility) {}

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the MYieldToOneForcedTransfer token with pausable and force transfer compliance features.
     * @dev    MUST only be called once. Reverts if `forcedTransferManager` is the zero address.
     * @param  name                  The name of the token (e.g. "M Yield to One").
     * @param  symbol                The symbol of the token (e.g. "MYTOFT").
     * @param  yieldRecipient_       The address of a yield destination.
     * @param  admin                 The address of an admin.
     * @param  freezeManager         The address of a freeze manager.
     * @param  yieldRecipientManager The address of a yield recipient setter.
     * @param  pauser                The address of a pauser.
     * @param  forcedTransferManager  The address of a force transfer manager.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser,
        address forcedTransferManager
    ) public virtual initializer {
        __MYieldToOneForcedTransfer_init(
            name,
            symbol,
            yieldRecipient_,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );
    }

    /**
     * @notice Initializes the internal state for MYieldToOneForcedTransfer token with pausable and force transfer compliance features.
     * @dev    Sets up the token name, symbol, yield recipient, admin, freeze manager, yield recipient manager, pauser, and force transfer manager.
     * @dev    Reverts if `forcedTransferManager` is the zero address.
     * @param  name                  The name of the token (e.g. "M Yield to One").
     * @param  symbol                The symbol of the token (e.g. "MYTOFT").
     * @param  yieldRecipient_       The address of a yield destination.
     * @param  admin                 The address of an admin.
     * @param  freezeManager         The address of a freeze manager.
     * @param  yieldRecipientManager The address of a yield recipient setter.
     * @param  pauser                The address of a pauser.
     * @param  forcedTransferManager  The address of a force transfer manager.
     */
    function __MYieldToOneForcedTransfer_init(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser,
        address forcedTransferManager
    ) internal onlyInitializing {
        if (forcedTransferManager == address(0)) revert ZeroForcedTransferManager();

        __MYieldToOne_init(name, symbol, yieldRecipient_, admin, freezeManager, yieldRecipientManager, pauser);
        __ForcedTransferable_init(forcedTransferManager);
    }

    /* ============ Interactive Functions ============ */

    /**
     * @inheritdoc IMYieldToOne
     * @dev Reverts if the contract is paused.
     */
    function claimYield() public override returns (uint256) {
        _requireNotPaused();
        return super.claimYield();
    }

    /**
     * @inheritdoc IMYieldToOne
     * @dev Only updates the yield recipient address; does not claim pending yield for the previous recipient.
     */
    function setYieldRecipient(address account) external override onlyRole(YIELD_RECIPIENT_MANAGER_ROLE) {
        _setYieldRecipient(account);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IERC20
    /// @dev Additionally readable by FORCED_TRANSFER_MANAGER_ROLE holders (compliance must size seizures).
    function balanceOf(address account) public view override returns (uint256) {
        if (hasRole(FORCED_TRANSFER_MANAGER_ROLE, msg.sender)) return uint256(_balanceOf(account));

        return super.balanceOf(account);
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Internal ERC20 force transfer function to seize funds from a frozen account.
     * @param frozenAccount The frozen account from which tokens are seized.
     * @param recipient     The recipient's address.
     * @param amount        The amount to be transferred.
     * @dev   Force transfer can only be called on frozen accounts.
     * @dev   No _beforeTransfer checks apply to forced transfers;
     * @dev   Since this function can only be called by the FORCED_TRANSFER_MANAGER_ROLE,
     *        we do not check if the recipient is frozen.
     */
    function _forceTransfer(address frozenAccount, address recipient, uint256 amount) internal override {
        _revertIfNotFrozen(frozenAccount);
        _revertIfInvalidRecipient(recipient);

        emit Transfer(frozenAccount, recipient, amount);
        emit ForcedTransfer(frozenAccount, recipient, msg.sender, amount);

        if (amount == 0) return;

        _revertIfInsufficientBalance(frozenAccount, amount);

        _update(frozenAccount, recipient, amount);
    }
}
