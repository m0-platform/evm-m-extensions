// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { Locker } from "./libs/Locker.sol";

import { AccessControlUpgradeable } from "../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IMsgSender } from "../../lib/uniswap-v4-periphery/src/interfaces/IMsgSender.sol";

import { IReentrancyLock } from "./interfaces/IReentrancyLock.sol";

abstract contract ReentrancyLockStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.ReentrancyLock
    struct ReentrancyLockStorageStruct {
        mapping(address router => bool isTrusted) trustedRouters;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.ReentrancyLock")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _REENTRANCY_LOCK_STORAGE_LOCATION =
        0x157708201859ed3ceee295d1baf4381ae5b622de496b1cee3705ed07c6a50200;

    function _getReentrancyLockStorageLocation() internal pure returns (ReentrancyLockStorageStruct storage $) {
        assembly {
            $.slot := _REENTRANCY_LOCK_STORAGE_LOCATION
        }
    }
}

/// @notice A transient reentrancy lock, that stores the caller's address as the lock
contract ReentrancyLock is IReentrancyLock, ReentrancyLockStorageLayout, AccessControlUpgradeable {
    /* ============ Modifiers ============ */

    modifier isNotLocked() {
        if (Locker.get() != address(0)) revert ContractLocked();

        address caller_ = isTrustedRouter(msg.sender) ? IMsgSender(msg.sender).msgSender() : msg.sender;

        Locker.set(caller_);
        _;
        Locker.set(address(0));
    }

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the contract with the given admin.
     * @param admin The address of an admin.
     */
    function __ReentrancyLock_init(address admin) internal onlyInitializing {
        if (admin == address(0)) revert ZeroAdmin();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IReentrancyLock
    function setTrustedRouter(address router, bool trusted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (router == address(0)) revert ZeroRouter();

        ReentrancyLockStorageStruct storage $ = _getReentrancyLockStorageLocation();
        if ($.trustedRouters[router] == trusted) return;

        $.trustedRouters[router] = trusted;

        emit TrustedRouterSet(router, trusted);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IReentrancyLock
    function isTrustedRouter(address router) public view returns (bool) {
        return _getReentrancyLockStorageLocation().trustedRouters[router];
    }

    /* ============ Private View/Pure Functions ============ */

    function _getLocker() internal view returns (address) {
        return Locker.get();
    }
}
