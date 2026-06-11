// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import { ERC20ExtendedUpgradeable } from "../../../lib/common/src/ERC20ExtendedUpgradeable.sol";
import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../../lib/common/src/interfaces/IERC20Extended.sol";

import { IMYieldToOne } from "./interfaces/IMYieldToOne.sol";

import { Freezable } from "../../components/freezable/Freezable.sol";
import { Pausable } from "../../components/pausable/Pausable.sol";
import { MExtension } from "../../MExtension.sol";

abstract contract MYieldToOneStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.MYieldToOne
    struct MYieldToOneStorageStruct {
        uint256 totalSupply;
        address yieldRecipient;
        mapping(address account => suint256 balance) balanceOf;
        // Sole allowance store, written by BOTH the shielded and native (ABI-cast) approve/transferFrom.
        // The inherited ERC20Extended `allowance` slot is never written (native writes here; permit reverts).
        mapping(address account => mapping(address spender => suint256 allowance)) shieldedAllowance;
        // Admin-curated trusted M0 infra; gates the native approve/transferFrom paths and balanceOf reads.
        mapping(address account => bool isAllowlisted) allowlist;
        // Encrypted Transfer/Approval events: per-account public-key registry. An unset key triggers
        // the empty-ciphertext fallback emit; the account still recovers the amount via its gated reads.
        mapping(address account => bytes publicKey) publicKeys;
        // Contract public key (plain bytes); off-chain decryption clients ECDH against this.
        bytes _contractPublicKey;
        // Contract private key (shielded ECDH input); set once via `setContractKey` (MUST be sent as TxSeismic 0x4A).
        sbytes32 contractPrivateKey;
        // Monotonic counter feeding the per-emit AES-GCM nonce, shared by encrypted Transfer and
        // Approval emits; pre-incremented so nonces never repeat under one key.
        uint256 encryptedEventNonce;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.MYieldToOne")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _M_YIELD_TO_ONE_STORAGE_LOCATION =
        0xee2f6fc7e2e5879b17985791e0d12536cba689bda43c77b8911497248f4af100;

    function _getMYieldToOneStorageLocation() internal pure returns (MYieldToOneStorageStruct storage $) {
        assembly {
            $.slot := _M_YIELD_TO_ONE_STORAGE_LOCATION
        }
    }
}

/**
 * @title  MYieldToOne
 * @notice Upgradeable ERC20 Token contract for wrapping M into a non-rebasing token
 *         with yield claimable by a single recipient.
 * @author M0 Labs
 */
contract MYieldToOne is IMYieldToOne, MYieldToOneStorageLayout, MExtension, Freezable, Pausable {
    /* ============ Variables ============ */

    /// @inheritdoc IMYieldToOne
    bytes32 public constant YIELD_RECIPIENT_MANAGER_ROLE = keccak256("YIELD_RECIPIENT_MANAGER_ROLE");

    /* ============ Constructor ============ */

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     * @notice Constructs MYieldToOne Implementation contract
     * @dev    Sets immutable storage.
     * @param  mToken       The address of $M token.
     * @param  swapFacility The address of Swap Facility.
     */
    constructor(address mToken, address swapFacility) MExtension(mToken, swapFacility) {}

    /* ============ Initializer ============ */

    /**
     * @dev   Initializes the M extension token with yield claimable by a single recipient.
     * @param name                  The name of the token (e.g. "M Yield to One").
     * @param symbol                The symbol of the token (e.g. "MYO").
     * @param yieldRecipient_       The address of a yield destination.
     * @param admin                 The address of an admin.
     * @param freezeManager         The address of a freeze manager.
     * @param yieldRecipientManager The address of a yield recipient setter.
     * @param pauser                The address of a pauser.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser
    ) public virtual initializer {
        __MYieldToOne_init(name, symbol, yieldRecipient_, admin, freezeManager, yieldRecipientManager, pauser);
    }

    /**
     * @notice Initializes the MYieldToOne token.
     * @param name                  The name of the token (e.g. "M Yield to One").
     * @param symbol                The symbol of the token (e.g. "MYO").
     * @param yieldRecipient_       The address of a yield destination.
     * @param admin                 The address of an admin.
     * @param freezeManager         The address of a freeze manager.
     * @param yieldRecipientManager The address of a yield recipient setter.
     * @param pauser                The address of a pauser.
     */
    function __MYieldToOne_init(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser
    ) internal onlyInitializing {
        if (yieldRecipientManager == address(0)) revert ZeroYieldRecipientManager();
        if (admin == address(0)) revert ZeroAdmin();

        __MExtension_init(name, symbol);
        __Freezable_init(freezeManager);
        __Pausable_init(pauser);

        _setYieldRecipient(yieldRecipient_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IMYieldToOne
    function claimYield() public virtual returns (uint256) {
        _beforeClaimYield();

        uint256 yield_ = yield();

        if (yield_ == 0) return 0;

        emit YieldClaimed(yield_);

        _mint(yieldRecipient(), yield_);

        return yield_;
    }

    /// @inheritdoc IMYieldToOne
    function setYieldRecipient(address account) external virtual onlyRole(YIELD_RECIPIENT_MANAGER_ROLE) {
        // Claim yield for the previous yield recipient.
        claimYield();

        _setYieldRecipient(account);
    }

    /* ============ Allowlist Management ============ */

    /// @inheritdoc IMYieldToOne
    function setAllowlisted(address account, bool status) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAllowlisted(account, status);
    }

    /// @inheritdoc IMYieldToOne
    function setAllowlisted(address[] calldata accounts, bool status) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            _setAllowlisted(accounts[i], status);
        }
    }

    /* ============ Encrypted-Event Keypair Management ============ */

    /// @inheritdoc IMYieldToOne
    /// @dev One-shot guard casts the shielded key to `bytes32` for a zero-check only (no write-back).
    function setContractKey(
        sbytes32 privateKey,
        bytes calldata publicKey
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _revertIfInvalidPublicKey(publicKey);

        if (bytes32(privateKey) == bytes32(0)) revert ZeroPrivateKey();

        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        // One-shot guard (control-flow compare only; see @dev).
        if (bytes32($.contractPrivateKey) != bytes32(0)) revert ContractKeyAlreadySet();

        $.contractPrivateKey = privateKey;
        $._contractPublicKey = publicKey;

        emit ContractKeySet(publicKey);
    }

    /// @inheritdoc IMYieldToOne
    function registerPublicKey(bytes calldata publicKey) external virtual {
        _revertIfInvalidPublicKey(publicKey);

        _getMYieldToOneStorageLocation().publicKeys[msg.sender] = publicKey;

        emit PublicKeyRegistered(msg.sender);
    }

    /* ============ Shielded ERC20 Entry Points ============ */

    /// @inheritdoc IMYieldToOne
    function transfer(address recipient, suint256 amount) external returns (bool) {
        // User-to-user path: encrypted-bytes emit.
        _shieldedTransfer(msg.sender, recipient, amount, true);
        return true;
    }

    /// @inheritdoc IMYieldToOne
    function approve(address spender, suint256 amount) external returns (bool) {
        // User path: encrypted-bytes emit.
        _shieldedApprove(msg.sender, spender, amount, true);
        return true;
    }

    /// @inheritdoc IMYieldToOne
    function transferFrom(address sender, address recipient, suint256 amount) external returns (bool) {
        // User-to-user path via allowance: encrypted-bytes emit.
        _spendAllowanceAndTransfer(sender, recipient, amount, true);
        return true;
    }

    /* ============ Inherited IERC20 / IERC20Extended Entry Points (Allowlist-Gated) ============ */
    // Re-enabled for trusted infra only: native `approve` if the SPENDER is infra, native
    // `transferFrom` if the CALLER is infra (`_isInfra`). Both write the same `shieldedAllowance`
    // slot as the `suint256` overloads (ABI-cast only), so the paths can't diverge. `transfer` and
    // both `permit` overloads always revert. Everyone else uses the `suint256` overloads above.

    /// @inheritdoc IERC20
    function transfer(
        address /* recipient */,
        uint256 /* amount */
    ) external pure override(ERC20ExtendedUpgradeable, IERC20) returns (bool) {
        revert UseShieldedTransfer();
    }

    /// @inheritdoc IERC20
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override(ERC20ExtendedUpgradeable, IERC20) returns (bool) {
        if (!_isInfra(msg.sender)) revert UseShieldedTransfer();

        // Infra path: amount already public via bridge calldata, so emit the plaintext Transfer.
        _spendAllowanceAndTransfer(sender, recipient, suint256(amount), false);
        return true;
    }

    /// @inheritdoc IERC20
    function approve(
        address spender,
        uint256 amount
    ) external override(ERC20ExtendedUpgradeable, IERC20) returns (bool) {
        if (!_isInfra(spender)) revert UseShieldedApprove();

        // Infra path: amount already public via plain calldata, so emit the plaintext Approval.
        _shieldedApprove(msg.sender, spender, suint256(amount), false);
        return true;
    }

    /// @inheritdoc IERC20Extended
    function permit(
        address /* owner */,
        address /* spender */,
        uint256 /* value */,
        uint256 /* deadline */,
        uint8 /* v */,
        bytes32 /* r */,
        bytes32 /* s */
    ) external pure override(ERC20ExtendedUpgradeable, IERC20Extended) {
        revert UseShieldedApprove();
    }

    /// @inheritdoc IERC20Extended
    function permit(
        address /* owner */,
        address /* spender */,
        uint256 /* value */,
        uint256 /* deadline */,
        bytes memory /* signature */
    ) external pure override(ERC20ExtendedUpgradeable, IERC20Extended) {
        revert UseShieldedApprove();
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IERC20
    /// @dev Shielded read, gated to `account` (TxSeismic 0x4A signed read — plain eth_call zeroes
    ///      msg.sender and reverts), trusted infra (`_isInfra`), or FREEZE_MANAGER_ROLE holders
    ///      (compliance must size seizures). Not readable by arbitrary callers.
    function balanceOf(address account) public view virtual override returns (uint256) {
        if (msg.sender != account && !_isInfra(msg.sender) && !hasRole(FREEZE_MANAGER_ROLE, msg.sender)) {
            revert Unauthorized();
        }

        return uint256(_getMYieldToOneStorageLocation().balanceOf[account]);
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256) {
        return _getMYieldToOneStorageLocation().totalSupply;
    }

    /// @inheritdoc IERC20
    /// @dev Shielded read; requires msg.sender == owner or spender (TxSeismic 0x4A signed read).
    ///      Sole allowance source — the inherited unshielded `allowance` slot is never written.
    function allowance(
        address owner,
        address spender
    ) public view override(ERC20ExtendedUpgradeable, IERC20) returns (uint256) {
        if (msg.sender != owner && msg.sender != spender) revert Unauthorized();
        return uint256(_getMYieldToOneStorageLocation().shieldedAllowance[owner][spender]);
    }

    /// @inheritdoc IMYieldToOne
    function yield() public view virtual returns (uint256) {
        unchecked {
            uint256 balance_ = _mBalanceOf(address(this));
            uint256 totalSupply_ = totalSupply();

            return balance_ > totalSupply_ ? balance_ - totalSupply_ : 0;
        }
    }

    /// @inheritdoc IMYieldToOne
    function yieldRecipient() public view returns (address) {
        return _getMYieldToOneStorageLocation().yieldRecipient;
    }

    /// @inheritdoc IMYieldToOne
    function isAllowlisted(address account) external view returns (bool) {
        return _getMYieldToOneStorageLocation().allowlist[account];
    }

    /// @inheritdoc IMYieldToOne
    function publicKeyOf(address account) external view returns (bytes memory) {
        return _getMYieldToOneStorageLocation().publicKeys[account];
    }

    /// @inheritdoc IMYieldToOne
    function contractPublicKey() external view returns (bytes memory) {
        return _getMYieldToOneStorageLocation()._contractPublicKey;
    }

    /* ============ Hooks For Internal Interactive Functions ============ */

    /**
     * @dev    Hooks called before approval of M extension spend.
     * @param  account The account from which M is deposited.
     * @param  spender The account spending M Extension token.
     */
    function _beforeApprove(address account, address spender, uint256 /* amount */) internal view virtual override {
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();

        _revertIfFrozen($, account);
        _revertIfFrozen($, spender);
    }

    /**
     * @dev    Hooks called before wrapping M into M Extension token.
     * @param  account   The account from which M is deposited.
     * @param  recipient The account receiving the minted M Extension token.
     */
    function _beforeWrap(address account, address recipient, uint256 /* amount */) internal view virtual override {
        _requireNotPaused();
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();

        _revertIfFrozen($, account);
        _revertIfFrozen($, recipient);
    }

    /**
     * @dev   Hook called before unwrapping M Extension token.
     * @param account The account from which M Extension token is burned.
     */
    function _beforeUnwrap(address account, uint256 /* amount */) internal view virtual override {
        _requireNotPaused();
        _revertIfFrozen(_getFreezableStorageLocation(), account);
    }

    /**
     * @dev   Hook called before transferring M Extension token.
     * @param sender    The address from which the tokens are being transferred.
     * @param recipient The address to which the tokens are being transferred.
     */
    function _beforeTransfer(address sender, address recipient, uint256 /* amount */) internal view virtual override {
        _requireNotPaused();
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();

        _revertIfFrozen($, msg.sender);

        _revertIfFrozen($, sender);
        _revertIfFrozen($, recipient);
    }

    /**
     * @dev   Hook called before claiming yield from the M Extension token. To be overridden in derived extensions.
     */
    function _beforeClaimYield() internal view virtual {}

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Mints `amount` tokens to `recipient`.
     * @param recipient The address whose account balance will be incremented.
     * @param amount    The present amount of tokens to mint.`
     */
    function _mint(address recipient, uint256 amount) internal override {
        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        // NOTE: Can be `unchecked` because the max amount of $M is never greater than `type(uint240).max`.
        unchecked {
            $.balanceOf[recipient] = $.balanceOf[recipient] + suint256(amount);
            $.totalSupply += amount;
        }

        emit Transfer(address(0), recipient, amount);
    }

    /**
     * @dev   Burns `amount` tokens from `account`.
     * @param account The address whose account balance will be decremented.
     * @param amount  The present amount of tokens to burn.
     */
    function _burn(address account, uint256 amount) internal override {
        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        // NOTE: Can be `unchecked` because `_revertIfInsufficientBalance` is used in MExtension.
        unchecked {
            $.balanceOf[account] = $.balanceOf[account] - suint256(amount);
            $.totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev   Internal balance update used by both the inherited (now-unreachable from outside)
     *        and the shielded transfer paths, and by `MYieldToOneForcedTransfer._forceTransfer`.
     *        Casts the public `uint256` to the shielded storage type at the boundary.
     */
    function _update(address sender, address recipient, uint256 amount) internal override {
        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        // NOTE: Can be `unchecked` because `_revertIfInsufficientBalance` for `sender` runs
        // before this call (in `MExtension._transfer` and in `_shieldedTransfer`).
        unchecked {
            $.balanceOf[sender] = $.balanceOf[sender] - suint256(amount);
            $.balanceOf[recipient] = $.balanceOf[recipient] + suint256(amount);
        }
    }

    /**
     * @dev   Shared allowance-spend + transfer for both `transferFrom` overloads. Decrements the
     *        shielded allowance (the sole store), then delegates to `_shieldedTransfer`. Reverts
     *        `InsufficientAllowance(spender, 0, amount)` — zeroed payload, no shielded-value leak.
     *        `encryptEmit` only selects the Transfer event shape (see `_shieldedTransfer`).
     */
    function _spendAllowanceAndTransfer(address sender, address recipient, suint256 amount, bool encryptEmit) internal {
        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();
        suint256 spenderAllowance = $.shieldedAllowance[sender][msg.sender];

        // Infinite-allowance shortcut (mirrors ERC20ExtendedUpgradeable.transferFrom)
        if (uint256(spenderAllowance) != type(uint256).max) {
            if (spenderAllowance < amount) revert IERC20Extended.InsufficientAllowance(msg.sender, 0, uint256(amount));

            // NOTE: Can be `unchecked` because the `spenderAllowance < amount` check above guarantees
            //       `spenderAllowance >= amount`, so the subtraction never underflows.
            unchecked {
                $.shieldedAllowance[sender][msg.sender] = spenderAllowance - amount;
            }
        }

        _shieldedTransfer(sender, recipient, amount, encryptEmit);
    }

    /**
     * @dev   Shielded transfer pipeline mirroring `MExtension._transfer` via a suint256→uint256 bridge;
     *        reuses `_beforeTransfer` (freeze/pause). Reverts `InsufficientBalance(account, 0, amount)`
     *        — zeroed payload. `encryptEmit`: true => encrypted-bytes Transfer (user paths); false =>
     *        plaintext Transfer(uint256) (infra paths, amount already public).
     */
    function _shieldedTransfer(address sender, address recipient, suint256 amount, bool encryptEmit) internal {
        uint256 amount_ = uint256(amount);

        _revertIfInvalidRecipient(recipient);
        _beforeTransfer(sender, recipient, amount_);

        if (encryptEmit) {
            emit Transfer(sender, recipient, _encryptAmount(sender, recipient, amount));
        } else {
            emit Transfer(sender, recipient, amount_);
        }

        if (amount_ == 0) return;

        if (_getMYieldToOneStorageLocation().balanceOf[sender] < amount) {
            revert InsufficientBalance(sender, 0, amount_);
        }

        _update(sender, recipient, amount_);
    }

    /* ============ Encrypted Event Pipeline ============ */

    /**
     * @dev    Encrypts `amount` to `to`'s registered key for an encrypted-bytes event payload;
     *         AES-GCM under HKDF(ECDH(contractPrivKey, toPubKey)), nonce from the shared monotonic
     *         counter. Reverts `ContractKeyNotSet` if the keypair is not installed — checked before
     *         the unregistered fallback so all user-path emits fail uniformly pre-key (success
     *         would otherwise leak who is registered).
     * @param  from   The counterparty address bound into the nonce derivation (sender / approver).
     * @param  to     The account whose registered key the ciphertext is encrypted to.
     * @param  amount The shielded amount to encrypt.
     * @return The AES-GCM ciphertext, or empty bytes if `to` has not registered a key.
     */
    function _encryptAmount(address from, address to, suint256 amount) internal returns (bytes memory) {
        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        if (bytes32($.contractPrivateKey) == bytes32(0)) revert ContractKeyNotSet();

        bytes memory pubKey = $.publicKeys[to];

        if (pubKey.length == 0) return bytes("");

        // Pre-increment so the first nonce is 1 and no two emits reuse a nonce under one key.
        uint256 n = ++$.encryptedEventNonce;

        sbytes32 sharedSecret = _ecdh($.contractPrivateKey, pubKey);
        sbytes32 aesKey = _hkdf(sharedSecret);
        bytes12 nonce = bytes12(keccak256(abi.encode(from, to, n)));

        return _aesGcmEncrypt(aesKey, nonce, abi.encode(uint256(amount)));
    }

    /**
     * @dev   Seismic ECDH precompile (0x65): shared secret of the shielded `privKey` and `peerPubKey`.
     *        Reverts `PrecompileFailed`.
     */
    function _ecdh(sbytes32 privKey, bytes memory peerPubKey) internal view returns (sbytes32) {
        (bool success, bytes memory result) = address(0x65).staticcall(abi.encodePacked(bytes32(privKey), peerPubKey));
        if (!success) revert PrecompileFailed(address(0x65));
        return sbytes32(abi.decode(result, (bytes32)));
    }

    /**
     * @dev   Seismic HKDF precompile (0x68): expands the shared secret into an AES-GCM key.
     *        Reverts `PrecompileFailed`.
     */
    function _hkdf(sbytes32 sharedSecret) internal view returns (sbytes32) {
        (bool success, bytes memory result) = address(0x68).staticcall(abi.encodePacked(bytes32(sharedSecret)));
        if (!success) revert PrecompileFailed(address(0x68));
        return sbytes32(abi.decode(result, (bytes32)));
    }

    /**
     * @dev   Seismic AES-GCM-encrypt precompile (0x66): encrypts `plaintext` under `key` / `nonce`,
     *        auth tag included. Reverts `PrecompileFailed`.
     */
    function _aesGcmEncrypt(sbytes32 key, bytes12 nonce, bytes memory plaintext) internal view returns (bytes memory) {
        (bool success, bytes memory ciphertext) = address(0x66).staticcall(
            abi.encodePacked(bytes32(key), nonce, plaintext)
        );
        if (!success) revert PrecompileFailed(address(0x66));
        return ciphertext;
    }

    /**
     * @dev   Writes the shielded `shieldedAllowance` slot (never the inherited one); reuses
     *        `_beforeApprove`. `encryptEmit`: true => encrypted-bytes Approval to `spender`'s
     *        registered key (user path); false => plaintext Approval(uint256) (infra path,
     *        amount already public in plain calldata).
     */
    function _shieldedApprove(address account, address spender, suint256 amount, bool encryptEmit) internal {
        uint256 amount_ = uint256(amount);

        _beforeApprove(account, spender, amount_);

        _getMYieldToOneStorageLocation().shieldedAllowance[account][spender] = amount;

        if (encryptEmit) {
            emit Approval(account, spender, _encryptAmount(account, spender, amount));
        } else {
            emit Approval(account, spender, amount_);
        }
    }

    /**
     * @dev   Ungated shielded balance accessor for internal use (bypasses the `balanceOf` gate).
     */
    function _balanceOf(address account) internal view returns (suint256) {
        return _getMYieldToOneStorageLocation().balanceOf[account];
    }

    /**
     * @dev   Trusted M0 infra = the `swapFacility` immutable OR the admin-curated `allowlist`. Gates
     *        the native approve/transferFrom paths and the `balanceOf` read.
     */
    function _isInfra(address account) internal view returns (bool) {
        return account == swapFacility || _getMYieldToOneStorageLocation().allowlist[account];
    }

    /**
     * @dev   Reverts unless `publicKey` is a 33-byte compressed secp256k1 point (`0x02`/`0x03` prefix).
     * @param publicKey The public key being validated.
     */
    function _revertIfInvalidPublicKey(bytes calldata publicKey) internal pure {
        if (publicKey.length != 33) revert InvalidPublicKeyLength();
        if (publicKey[0] != 0x02 && publicKey[0] != 0x03) revert InvalidPublicKeyPrefix();
    }

    /**
     * @dev   Shielded-space override; reverts `InsufficientBalance(account, 0, amount)` — zeroed
     *        payload, no balance leak. The `IMExtension.InsufficientBalance` shape is unchanged.
     */
    function _revertIfInsufficientBalance(address account, uint256 amount) internal view override {
        if (_balanceOf(account) < suint256(amount)) revert InsufficientBalance(account, 0, amount);
    }

    /**
     * @dev Sets the yield recipient.
     * @param yieldRecipient_ The address of the new yield recipient.
     */
    function _setYieldRecipient(address yieldRecipient_) internal {
        if (yieldRecipient_ == address(0)) revert ZeroYieldRecipient();

        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        if (yieldRecipient_ == $.yieldRecipient) return;

        $.yieldRecipient = yieldRecipient_;

        emit YieldRecipientSet(yieldRecipient_);
    }

    /**
     * @dev   Sets the infra allowlist status of `account`.
     * @param account The address whose allowlist status is being set.
     * @param status  The new allowlist status (`true` = allowlisted).
     */
    function _setAllowlisted(address account, bool status) internal {
        if (account == address(0)) revert ZeroAllowlistAccount();

        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        // Return early if the status is unchanged.
        if ($.allowlist[account] == status) return;

        $.allowlist[account] = status;

        emit AllowlistSet(account, status);
    }
}
