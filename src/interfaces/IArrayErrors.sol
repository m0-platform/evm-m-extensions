// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

/**
 * @title  IArrayErrors
 * @notice Shared error declarations for array length validation.
 */
interface IArrayErrors {
    /// @notice Error for array length mismatch.
    error ArrayLengthMismatch();
}
