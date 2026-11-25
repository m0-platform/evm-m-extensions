// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @author Uniswap Labs.
 *         Adapted from https://github.com/Uniswap/v4-periphery/blob/main/src/libraries/Locker.sol
 * @dev    Use Uniswap version of the contract when deploying to chains that support transient storage.
 */
library Locker {
    // The slot holding the locker state. bytes32(uint256(keccak256("LockedBy")) - 1)
    bytes32 constant LOCKED_BY_SLOT = 0x0aedd6bde10e3aa2adec092b02a3e3e805795516cda41f27aa145b8f300af87a;

    function set(address locker) internal {
        assembly {
            sstore(LOCKED_BY_SLOT, locker)
        }
    }

    function get() internal view returns (address locker) {
        assembly {
            locker := sload(LOCKED_BY_SLOT)
        }
    }
}
