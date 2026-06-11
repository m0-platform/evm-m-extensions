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
     * @notice Emitted by user-to-user shielded transfers (the `suint256` overloads). The third field
     *         is an AES-GCM ciphertext of the amount, encrypted to the recipient's registered key via
     *         ECDH; empty bytes if the recipient has not registered one (the transfer still succeeds,
     *         and the amount is recoverable only via the recipient's gated `balanceOf`).
     * @dev    Distinct `topic0` from the inherited `Transfer(address,address,uint256)` — indexers MUST
     *         subscribe to both. Infra paths (mint, burn, native `transferFrom`, forced transfer) emit
     *         the inherited `uint256` overload exclusively.
     * @param  from            The address transferring the tokens.
     * @param  to              The address receiving the tokens.
     * @param  encryptedAmount AES-GCM ciphertext of the amount, or `bytes("")` if `to` is unregistered.
     */
    event Transfer(address indexed from, address indexed to, bytes encryptedAmount);

    /**
     * @notice Emitted by `setContractKey` once the contract keypair is installed. Only the
     *         public key is logged; the private key is held in shielded storage and is
     *         never observable from logs or events.
     * @param  publicKey The contract's compressed (33-byte) secp256k1 public key.
     */
    event ContractKeySet(bytes publicKey);

    /**
     * @notice Emitted by `registerPublicKey` when an account installs or overwrites its
     *         recipient public key for encrypted-event decryption.
     * @param  account The account whose recipient public key was (re-)registered.
     */
    event PublicKeyRegistered(address indexed account);

    /* ============ Custom Errors ============ */

    /// @notice Emitted in initializer if Yield Recipient is 0x0.
    error ZeroYieldRecipient();

    /// @notice Emitted in initializer if Yield Recipient Manager is 0x0.
    error ZeroYieldRecipientManager();

    /// @notice Emitted in initializer if Admin is 0x0.
    error ZeroAdmin();

    /// @notice Emitted when a public read accesses a shielded value without holder authorization
    ///         (caller must use a Seismic signed read with `msg.sender == account`).
    error Unauthorized();

    /// @notice Reverted when native `IERC20.approve` is called with a non-allowlisted spender, or
    ///         when the `permit` path is invoked. Holders must use the shielded
    ///         `approve(address,suint256)` overload, or approve an allowlisted infra address.
    error UseShieldedApprove();

    /// @notice Reverted when the native `IERC20.transfer` path is invoked, or when native
    ///         `IERC20.transferFrom` is called by a non-allowlisted caller. Callers must use the
    ///         shielded overloads; only allowlisted infra may use the native `transferFrom` path.
    error UseShieldedTransfer();

    /// @notice Reverted in `setAllowlisted` if the account is the zero address.
    error ZeroAllowlistAccount();

    /// @notice Reverted by `setContractKey` / `registerPublicKey` if the supplied public
    ///         key is not exactly 33 bytes (compressed secp256k1 encoding).
    error InvalidPublicKeyLength();

    /// @notice Reverted by `setContractKey` / `registerPublicKey` if the supplied public
    ///         key does not start with a compressed-point prefix (`0x02` / `0x03`).
    error InvalidPublicKeyPrefix();

    /// @notice Reverted by `setContractKey` if the supplied private key is zero.
    error ZeroPrivateKey();

    /// @notice Reverted by `setContractKey` if the contract keypair has already been
    ///         installed. Rotation is deliberately not supported — a new key would orphan
    ///         every historical ciphertext.
    error ContractKeyAlreadySet();

    /// @notice Reverted by the encrypted-emit path if a shielded transfer is attempted
    ///         before the admin has called `setContractKey`.
    error ContractKeyNotSet();

    /// @notice Reverted by an encrypted-emit precompile wrapper when the underlying
    ///         `staticcall` to the Seismic precompile fails. `precompile` is the address
    ///         of the precompile that returned a failing result (0x65 ECDH, 0x66 AES-GCM,
    ///         0x68 HKDF).
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
     * @dev    Allowlisted addresses MUST be audited M0 infrastructure contracts (e.g. Portal,
     *         LimitOrderProtocol) — never EOAs or contracts that re-expose `balanceOf`. (SwapFacility
     *         is permanently exempt via the immutable and does not need allowlisting.) An
     *         allowlisted address may use the native `uint256` `approve`
     *         (as spender) and `transferFrom` (as caller) paths and may read any holder's cleartext
     *         `balanceOf`.
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
     * @notice Shielded ERC20 transfer. `amount` is stored and compared in shielded space. Emits the
     *         encrypted-bytes `Transfer(address,address,bytes)` overload to `recipient`'s registered
     *         key (empty ciphertext if `recipient` has not registered one — transfer still succeeds).
     * @param  recipient The address receiving the tokens.
     * @param  amount    The shielded amount to transfer.
     * @return success   Always `true` on non-revert (mirrors `IERC20.transfer`).
     */
    function transfer(address recipient, suint256 amount) external returns (bool);

    /**
     * @notice Shielded ERC20 approve. Stores the allowance as `suint256`.
     * @param  spender The address allowed to spend on behalf of `msg.sender`.
     * @param  amount  The shielded allowance amount. Use `suint256(type(uint256).max)` for an
     *                 infinite, non-decrementing allowance (matches `ERC20ExtendedUpgradeable`).
     * @return success Always `true` on non-revert.
     */
    function approve(address spender, suint256 amount) external returns (bool);

    /**
     * @notice Shielded ERC20 transferFrom. Reads and decrements the shielded allowance in shielded
     *         space; reverts `InsufficientAllowance(spender, 0, amount)` (zeroed payload). Emits the
     *         encrypted-bytes `Transfer` overload (empty ciphertext if `recipient` is unregistered).
     * @param  sender    The address whose tokens are being moved.
     * @param  recipient The address receiving the tokens.
     * @param  amount    The shielded amount to transfer.
     * @return success   Always `true` on non-revert.
     */
    function transferFrom(address sender, address recipient, suint256 amount) external returns (bool);

    /**
     * @notice Installs the contract's encryption keypair used to derive per-recipient
     *         AES-GCM keys for shielded `Transfer` event payloads. One-shot: reverts
     *         `ContractKeyAlreadySet` on any subsequent call.
     * @dev    MUST only be callable by the `DEFAULT_ADMIN_ROLE`.
     * @dev    MUST be sent as a Seismic `TxSeismic` transaction (type `0x4A`) so the
     *         private key is encrypted in calldata. This is an operational requirement
     *         that cannot be enforced from Solidity.
     * @dev    Reverts `InvalidPublicKeyLength` unless `publicKey.length == 33` and
     *         `InvalidPublicKeyPrefix` unless `publicKey[0]` is `0x02` / `0x03`.
     * @dev    Reverts `ZeroPrivateKey` if `privateKey` is zero (a zero key would bypass
     *         the one-shot guard and leave the contract key-less).
     * @dev    Rotation is intentionally out of scope: rotating the contract key would
     *         orphan every historical ciphertext stored in past events.
     * @param  privateKey The contract's secp256k1 private key, shielded at the ABI
     *                   boundary so it remains in flagged storage.
     * @param  publicKey  The contract's compressed (33-byte) secp256k1 public key.
     */
    function setContractKey(sbytes32 privateKey, bytes calldata publicKey) external;

    /**
     * @notice Registers the caller's recipient public key. Idempotent — a subsequent call
     *         overwrites the previously registered key (future ciphertexts use the new
     *         key; historical ciphertexts remain decryptable only with the old key).
     * @dev    Reverts `InvalidPublicKeyLength` unless `publicKey.length == 33` and
     *         `InvalidPublicKeyPrefix` unless `publicKey[0]` is `0x02` / `0x03`.
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
     * @notice Returns the recipient public key previously registered by `account` via
     *         `registerPublicKey`, or empty bytes if none has been registered. Plain
     *         (non-shielded) read — readable by any caller.
     * @param  account The address whose registered public key is being queried.
     * @return The registered compressed (33-byte) secp256k1 public key, or empty bytes.
     */
    function publicKeyOf(address account) external view returns (bytes memory);

    /**
     * @notice Returns the contract's currently installed public key, or empty bytes if
     *         `setContractKey` has not yet been called. Plain (non-shielded) read —
     *         off-chain decryption clients fetch this to verify the ECDH peer.
     * @return The contract's compressed (33-byte) secp256k1 public key, or empty bytes.
     */
    function contractPublicKey() external view returns (bytes memory);
}
