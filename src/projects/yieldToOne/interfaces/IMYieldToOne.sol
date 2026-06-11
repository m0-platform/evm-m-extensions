// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

/**
 * @title M Extension where all yield is claimable by a single recipient.
 * @author M0 Labs
 */
interface IMYieldToOne {
    /* ============ Events ============ */

    /**
     * @notice Emitted when this contract's excess M is claimed.
     * @param  yield The amount of M yield claimed.
     */
    event YieldClaimed(uint256 yield);

    /**
     * @notice Emitted when the yield recipient is set.
     * @param  yieldRecipient The address of the new yield recipient.
     */
    event YieldRecipientSet(address indexed yieldRecipient);

    /**
     * @notice Emitted when an address is added to or removed from the infra allowlist.
     * @param  account The address whose allowlist status changed.
     * @param  status  The new allowlist status (`true` = allowlisted).
     */
    event AllowlistSet(address indexed account, bool status);

    /**
     * @notice Emitted by user-path shielded transfers (the `suint256` overloads); the amount is
     *         encrypted to the recipient's registered key.
     * @dev    Distinct `topic0` from the inherited `Transfer(address,address,uint256)` — indexers MUST track both.
     * @param  from            The address transferring the tokens.
     * @param  to              The address receiving the tokens.
     * @param  encryptedAmount AES-GCM ciphertext of the amount; empty bytes if `to` has no registered key.
     */
    event Transfer(address indexed from, address indexed to, bytes encryptedAmount);

    /**
     * @notice Emitted by user-path shielded approvals (the `suint256` overload); the allowance is
     *         encrypted to the spender's registered key.
     * @dev    Distinct `topic0` from the inherited `Approval(address,address,uint256)` — indexers MUST track both.
     * @param  account         The account granting the allowance.
     * @param  spender         The account allowed to spend on behalf of `account`.
     * @param  encryptedAmount AES-GCM ciphertext of the allowance; empty bytes if `spender` has no registered key.
     */
    event Approval(address indexed account, address indexed spender, bytes encryptedAmount);

    /**
     * @notice Emitted when the contract's encrypted-event keypair is installed; only the public key is logged.
     * @param  publicKey The contract's compressed (33-byte) secp256k1 public key.
     */
    event ContractKeySet(bytes publicKey);

    /**
     * @notice Emitted when an account registers (or overwrites) its public key for encrypted-event decryption.
     * @param  account The account whose public key was registered.
     */
    event PublicKeyRegistered(address indexed account);

    /* ============ Custom Errors ============ */

    /// @notice Emitted in initializer if Yield Recipient is 0x0.
    error ZeroYieldRecipient();

    /// @notice Emitted in initializer if Yield Recipient Manager is 0x0.
    error ZeroYieldRecipientManager();

    /// @notice Emitted in initializer if Admin is 0x0.
    error ZeroAdmin();

    /// @notice Emitted when a gated read (`balanceOf` / `allowance`) is called by an unauthorized account.
    error Unauthorized();

    /// @notice Emitted when the native `approve` is called with a non-infra spender, or `permit` is
    ///         called; use the shielded `approve(address,suint256)` overload instead.
    error UseShieldedApprove();

    /// @notice Emitted when the native `transfer` is called, or the native `transferFrom` is called
    ///         by a non-infra caller; use the shielded `suint256` overloads instead.
    error UseShieldedTransfer();

    /// @notice Emitted in `setAllowlisted` if the account is 0x0.
    error ZeroAllowlistAccount();

    /// @notice Emitted in `setContractKey` and `registerPublicKey` if the public key is not 33 bytes.
    error InvalidPublicKeyLength();

    /// @notice Emitted in `setContractKey` and `registerPublicKey` if the public key prefix is not `0x02`/`0x03`.
    error InvalidPublicKeyPrefix();

    /// @notice Emitted in `setContractKey` if the private key is zero.
    error ZeroPrivateKey();

    /// @notice Emitted in `setContractKey` if the contract keypair is already installed.
    error ContractKeyAlreadySet();

    /// @notice Emitted by the encrypted-event path if the contract keypair has not been installed.
    error ContractKeyNotSet();

    /**
     * @notice Emitted when a Seismic precompile staticcall fails.
     * @param  precompile The failing precompile address (0x65 ECDH, 0x66 AES-GCM, 0x68 HKDF).
     */
    error PrecompileFailed(address precompile);

    /* ============ Interactive Functions ============ */

    /// @notice Claims accrued yield to yield recipient.
    function claimYield() external returns (uint256);

    /**
     * @notice Sets the yield recipient.
     * @dev    MUST only be callable by the YIELD_RECIPIENT_MANAGER_ROLE.
     * @dev    SHOULD revert if `yieldRecipient` is 0x0.
     * @dev    SHOULD return early if the `yieldRecipient` is already the actual yield recipient.
     * @param  yieldRecipient The address of the new yield recipient.
     */
    function setYieldRecipient(address yieldRecipient) external;

    /**
     * @notice Adds or removes `account` from the infra allowlist.
     * @dev    MUST only be callable by the DEFAULT_ADMIN_ROLE.
     * @dev    Allowlisted addresses MUST be audited M0 infra contracts, never EOAs or contracts re-exposing `balanceOf`.
     * @dev    Grants native `approve` (as spender) and `transferFrom` (as caller) paths and ungated `balanceOf` reads.
     * @dev    SHOULD revert if `account` is 0x0. SHOULD return early if the status is unchanged.
     * @param  account The address whose allowlist status is being set.
     * @param  status  The new allowlist status (`true` = allowlisted).
     */
    function setAllowlisted(address account, bool status) external;

    /**
     * @notice Adds or removes a batch of accounts from the infra allowlist.
     * @dev    MUST only be callable by the DEFAULT_ADMIN_ROLE.
     * @dev    Reverts atomically (the whole batch) if any `accounts` entry is the zero address.
     * @param  accounts The addresses whose allowlist status is being set.
     * @param  status   The new allowlist status applied to every address in `accounts`.
     */
    function setAllowlisted(address[] calldata accounts, bool status) external;

    /**
     * @notice Shielded ERC20 transfer of `amount` tokens to `recipient`.
     * @dev    Emits the encrypted-bytes `Transfer(address,address,bytes)` overload.
     * @param  recipient The address receiving the tokens.
     * @param  amount    The shielded amount to transfer.
     * @return Whether or not the transfer was successful.
     */
    function transfer(address recipient, suint256 amount) external returns (bool);

    /**
     * @notice Shielded ERC20 approval of `spender` for `amount` of the caller's tokens.
     * @dev    Emits the encrypted-bytes `Approval(address,address,bytes)` overload.
     * @param  spender The address allowed to spend on behalf of `msg.sender`.
     * @param  amount  The shielded allowance; `suint256(type(uint256).max)` is an infinite, non-decrementing allowance.
     * @return Whether or not the approval was successful.
     */
    function approve(address spender, suint256 amount) external returns (bool);

    /**
     * @notice Shielded ERC20 transferFrom; reads and decrements the allowance in shielded space.
     * @dev    Emits the encrypted-bytes `Transfer(address,address,bytes)` overload.
     * @param  sender    The address whose tokens are being moved.
     * @param  recipient The address receiving the tokens.
     * @param  amount    The shielded amount to transfer.
     * @return Whether or not the transfer was successful.
     */
    function transferFrom(address sender, address recipient, suint256 amount) external returns (bool);

    /**
     * @notice Installs the contract's encrypted-event keypair; one-shot, reverts `ContractKeyAlreadySet`
     *         on any subsequent call. Until installed, user-path shielded transfers and approvals
     *         revert `ContractKeyNotSet`.
     * @dev    MUST only be callable by the DEFAULT_ADMIN_ROLE.
     * @dev    MUST be sent as a `TxSeismic` (type 0x4A) transaction — plain calldata would leak the private key.
     * @dev    Rotation is unsupported: a new contract key would orphan every historical ciphertext.
     * @param  privateKey The contract's secp256k1 private key, shielded at the ABI boundary.
     * @param  publicKey  The contract's compressed (33-byte) secp256k1 public key.
     */
    function setContractKey(sbytes32 privateKey, bytes calldata publicKey) external;

    /**
     * @notice Registers the caller's public key for encrypted-event payloads; a subsequent call
     *         overwrites the previously registered key.
     * @param  publicKey The caller's compressed (33-byte) secp256k1 public key.
     */
    function registerPublicKey(bytes calldata publicKey) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can manage the yield recipient.
    function YIELD_RECIPIENT_MANAGER_ROLE() external view returns (bytes32);

    /// @notice The amount of accrued yield.
    function yield() external view returns (uint256);

    /// @notice The address of the yield recipient.
    function yieldRecipient() external view returns (address);

    /**
     * @notice Returns whether `account` is on the infra allowlist.
     * @param  account The address being queried.
     * @return Whether the address is allowlisted.
     */
    function isAllowlisted(address account) external view returns (bool);

    /**
     * @notice Returns the public key registered by `account`, or empty bytes if none; readable by any caller.
     * @param  account The address whose registered public key is being queried.
     * @return The registered compressed (33-byte) secp256k1 public key, or empty bytes.
     */
    function publicKeyOf(address account) external view returns (bytes memory);

    /**
     * @notice Returns the contract's installed public key, or empty bytes if `setContractKey` has not
     *         been called; readable by any caller.
     * @return The contract's compressed (33-byte) secp256k1 public key, or empty bytes.
     */
    function contractPublicKey() external view returns (bytes memory);
}
