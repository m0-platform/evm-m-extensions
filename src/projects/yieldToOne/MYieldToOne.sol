// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import { ERC20ExtendedUpgradeable } from "../../../lib/common/src/ERC20ExtendedUpgradeable.sol";
import { ERC3009Upgradeable } from "../../../lib/common/src/ERC3009Upgradeable.sol";
import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../../lib/common/src/interfaces/IERC20Extended.sol";
import { IERC3009 } from "../../../lib/common/src/interfaces/IERC3009.sol";

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
        // Sole allowance store; the inherited ERC20Extended `allowance` slot is never written.
        mapping(address account => mapping(address spender => suint256 allowance)) shieldedAllowance;
        mapping(address account => bool isAllowlisted) allowlist;
        mapping(address account => bytes publicKey) publicKeys;
        bytes contractPublicKey;
        // Set once via `setContractKey` (TxSeismic 0x4A only); no getter exposes it.
        sbytes32 contractPrivateKey;
        // Monotonic counter feeding the per-emit AES-GCM nonce; pre-incremented so nonces never repeat.
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

    /// @inheritdoc IMYieldToOne
    bytes32 public constant ALLOWLIST_MANAGER_ROLE = keccak256("ALLOWLIST_MANAGER_ROLE");

    /// @inheritdoc IMYieldToOne
    bytes32 public constant ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");

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
     * @param allowlistAdmin        The address granted the allowlist admin role (manages the allowlist-manager role).
     */
    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser,
        address allowlistAdmin
    ) public virtual initializer {
        __MYieldToOne_init(
            name,
            symbol,
            yieldRecipient_,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            allowlistAdmin
        );
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
     * @param allowlistAdmin        The address granted the allowlist admin role (manages the allowlist-manager role).
     */
    function __MYieldToOne_init(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser,
        address allowlistAdmin
    ) internal onlyInitializing {
        if (yieldRecipientManager == address(0)) revert ZeroYieldRecipientManager();
        if (admin == address(0)) revert ZeroAdmin();
        if (allowlistAdmin == address(0)) revert ZeroAllowlistAdmin();

        __MExtension_init(name, symbol);
        __Freezable_init(freezeManager);
        __Pausable_init(pauser);

        _setYieldRecipient(yieldRecipient_);

        // The allowlist manager (who calls `setAllowlisted`) is administered by a dedicated allowlist
        // admin rather than the DEFAULT_ADMIN_ROLE, so allowlist control can be delegated independently.
        _setRoleAdmin(ALLOWLIST_MANAGER_ROLE, ALLOWLIST_ADMIN_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager);
        _grantRole(ALLOWLIST_ADMIN_ROLE, allowlistAdmin);
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

    /// @inheritdoc IMYieldToOne
    function setAllowlisted(address account, bool status) external virtual onlyRole(ALLOWLIST_MANAGER_ROLE) {
        _setAllowlisted(account, status);
    }

    /// @inheritdoc IMYieldToOne
    function setAllowlisted(
        address[] calldata accounts,
        bool status
    ) external virtual onlyRole(ALLOWLIST_MANAGER_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            _setAllowlisted(accounts[i], status);
        }
    }

    /// @inheritdoc IMYieldToOne
    /// @dev Deliberately not folded into `initialize()`: initializer calldata is plaintext and would leak the key.
    function setContractKey(
        sbytes32 privateKey,
        bytes calldata publicKey
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _revertIfInvalidPublicKey(publicKey);

        if (bytes32(privateKey) == bytes32(0)) revert ZeroPrivateKey();

        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        if (bytes32($.contractPrivateKey) != bytes32(0)) revert ContractKeyAlreadySet();

        $.contractPrivateKey = privateKey;
        $.contractPublicKey = publicKey;

        emit ContractKeySet(publicKey);
    }

    /// @inheritdoc IMYieldToOne
    function registerPublicKey(bytes calldata publicKey) external virtual {
        _revertIfInvalidPublicKey(publicKey);

        _getMYieldToOneStorageLocation().publicKeys[msg.sender] = publicKey;

        emit PublicKeyRegistered(msg.sender);
    }

    /// @inheritdoc IMYieldToOne
    function transfer(address recipient, suint256 amount) external returns (bool) {
        _shieldedTransfer(msg.sender, recipient, amount, true);
        return true;
    }

    /// @inheritdoc IMYieldToOne
    function approve(address spender, suint256 amount) external returns (bool) {
        _shieldedApprove(msg.sender, spender, amount, true);
        return true;
    }

    /// @inheritdoc IMYieldToOne
    function transferFrom(address sender, address recipient, suint256 amount) external returns (bool) {
        _spendAllowanceAndTransfer(sender, recipient, amount, true);
        return true;
    }

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

        _spendAllowanceAndTransfer(sender, recipient, suint256(amount), false);
        return true;
    }

    /// @inheritdoc IERC20
    function approve(
        address spender,
        uint256 amount
    ) external override(ERC20ExtendedUpgradeable, IERC20) returns (bool) {
        if (!_isInfra(spender)) revert UseShieldedApprove();

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

    // ERC-3009 transfer/receive hard-code a plaintext `uint256 value`, so they cannot be shielded. Disable
    // them (mirroring the `permit` reverts above) to keep amounts off the public, encryption-bypassing path.

    /// @inheritdoc IERC3009
    function transferWithAuthorization(
        address /* from */,
        address /* to */,
        uint256 /* value */,
        uint256 /* validAfter */,
        uint256 /* validBefore */,
        bytes32 /* nonce */,
        bytes memory /* signature */
    ) external pure override(ERC3009Upgradeable, IERC3009) {
        revert UseShieldedTransfer();
    }

    /// @inheritdoc IERC3009
    function transferWithAuthorization(
        address /* from */,
        address /* to */,
        uint256 /* value */,
        uint256 /* validAfter */,
        uint256 /* validBefore */,
        bytes32 /* nonce */,
        bytes32 /* r */,
        bytes32 /* vs */
    ) external pure override(ERC3009Upgradeable, IERC3009) {
        revert UseShieldedTransfer();
    }

    /// @inheritdoc IERC3009
    function transferWithAuthorization(
        address /* from */,
        address /* to */,
        uint256 /* value */,
        uint256 /* validAfter */,
        uint256 /* validBefore */,
        bytes32 /* nonce */,
        uint8 /* v */,
        bytes32 /* r */,
        bytes32 /* s */
    ) external pure override(ERC3009Upgradeable, IERC3009) {
        revert UseShieldedTransfer();
    }

    /// @inheritdoc IERC3009
    function receiveWithAuthorization(
        address /* from */,
        address /* to */,
        uint256 /* value */,
        uint256 /* validAfter */,
        uint256 /* validBefore */,
        bytes32 /* nonce */,
        bytes memory /* signature */
    ) external pure override(ERC3009Upgradeable, IERC3009) {
        revert UseShieldedTransfer();
    }

    /// @inheritdoc IERC3009
    function receiveWithAuthorization(
        address /* from */,
        address /* to */,
        uint256 /* value */,
        uint256 /* validAfter */,
        uint256 /* validBefore */,
        bytes32 /* nonce */,
        bytes32 /* r */,
        bytes32 /* vs */
    ) external pure override(ERC3009Upgradeable, IERC3009) {
        revert UseShieldedTransfer();
    }

    /// @inheritdoc IERC3009
    function receiveWithAuthorization(
        address /* from */,
        address /* to */,
        uint256 /* value */,
        uint256 /* validAfter */,
        uint256 /* validBefore */,
        bytes32 /* nonce */,
        uint8 /* v */,
        bytes32 /* r */,
        bytes32 /* s */
    ) external pure override(ERC3009Upgradeable, IERC3009) {
        revert UseShieldedTransfer();
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IERC20
    /// @dev Gated read: only `account` itself (signed read), trusted infra, or FREEZE_MANAGER_ROLE holders.
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
    /// @dev Gated read: only `owner` or `spender` (signed read) may read the shielded allowance.
    function allowance(
        address owner,
        address spender
    ) public view override(ERC20ExtendedUpgradeable, IERC20) returns (uint256) {
        if (msg.sender != owner && msg.sender != spender) revert Unauthorized();
        return uint256(_getMYieldToOneStorageLocation().shieldedAllowance[owner][spender]);
    }

    /// @inheritdoc IMYieldToOne
    function yield() public view virtual returns (uint256) {
        // NOTE: Can be `unchecked` because the subtraction only runs when `balance_ > totalSupply_`.
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
        return _getMYieldToOneStorageLocation().contractPublicKey;
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
     * @dev   Internal balance update function called on transfer.
     * @param sender    The sender's address.
     * @param recipient The recipient's address.
     * @param amount    The amount to be transferred.
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
     * @dev   Decrements `msg.sender`'s shielded allowance, then transfers via `_shieldedTransfer`.
     * @dev   Reverts `InsufficientAllowance(msg.sender, 0, amount)` — zeroed payload, no shielded-value leak.
     * @param sender      The address whose tokens are being moved.
     * @param recipient   The address receiving the tokens.
     * @param amount      The shielded amount to transfer.
     * @param encryptEmit Whether to emit the encrypted-bytes `Transfer` overload or the plaintext one.
     */
    function _spendAllowanceAndTransfer(address sender, address recipient, suint256 amount, bool encryptEmit) internal {
        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();
        suint256 spenderAllowance = $.shieldedAllowance[sender][msg.sender];

        // Infinite-allowance shortcut (mirrors ERC20ExtendedUpgradeable.transferFrom)
        if (uint256(spenderAllowance) != type(uint256).max) {
            // NOTE: Branching on a shielded value leaks a 1-bit comparison via revert-vs-success;
            //       accepted — inherent to ERC20 insufficient-allowance semantics (ssolc 10311).
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
     * @dev   Shielded transfer mirroring `MExtension._transfer`, including its `_beforeTransfer` hook.
     * @dev   Reverts `InsufficientBalance(sender, 0, amount)` — zeroed payload, no balance leak.
     * @param sender      The address from which the tokens are being transferred.
     * @param recipient   The address to which the tokens are being transferred.
     * @param amount      The shielded amount to transfer.
     * @param encryptEmit Whether to emit the encrypted-bytes `Transfer` overload or the plaintext one.
     */
    function _shieldedTransfer(address sender, address recipient, suint256 amount, bool encryptEmit) internal {
        uint256 amount_ = uint256(amount);

        if (amount_ == 0) return;

        _revertIfInvalidRecipient(recipient);
        _beforeTransfer(sender, recipient, amount_);

        if (encryptEmit) {
            (bytes32 encryptKeyHash, bytes memory ciphertext) = _encryptAmount(sender, recipient, amount);
            emit Transfer(sender, recipient, encryptKeyHash, ciphertext);
        } else {
            emit Transfer(sender, recipient, amount_);
        }

        // NOTE: Branching on a shielded value leaks a 1-bit comparison via revert-vs-success;
        //       accepted — inherent to ERC20 insufficient-balance semantics (ssolc 10311).
        if (_getMYieldToOneStorageLocation().balanceOf[sender] < amount) {
            revert InsufficientBalance(sender, 0, amount_);
        }

        _update(sender, recipient, amount_);
    }

    /**
     * @dev    Encrypts `amount` to `to`'s registered key (AES-GCM under HKDF(ECDH)) for an event payload.
     * @dev    Reverts `ContractKeyNotSet` before the unregistered-key fallback: user emits fail uniformly pre-key.
     * @param  from   The counterparty address bound into the nonce derivation (sender / approver).
     * @param  to     The account whose registered key the ciphertext is encrypted to.
     * @param  amount The shielded amount to encrypt.
     * @return encryptKeyHash `keccak256` of `to`'s registered public key, or `bytes32(0)` if `to` has no key.
     * @return ciphertext     The AES-GCM ciphertext, or empty bytes if `to` has not registered a key.
     */
    function _encryptAmount(
        address from,
        address to,
        suint256 amount
    ) internal returns (bytes32 encryptKeyHash, bytes memory ciphertext) {
        MYieldToOneStorageStruct storage $ = _getMYieldToOneStorageLocation();

        if (bytes32($.contractPrivateKey) == bytes32(0)) revert ContractKeyNotSet();

        bytes memory pubKey = $.publicKeys[to];

        if (pubKey.length == 0) return (bytes32(0), bytes(""));

        encryptKeyHash = keccak256(pubKey);

        uint256 n = ++$.encryptedEventNonce;

        emit EncryptedAmountNonce(from, to, n);

        sbytes32 sharedSecret = _ecdh($.contractPrivateKey, pubKey);
        sbytes32 aesKey = _hkdf(sharedSecret);
        bytes12 nonce = bytes12(keccak256(abi.encode(from, to, n)));

        ciphertext = _aesGcmEncrypt(aesKey, nonce, abi.encode(uint256(amount)));
    }

    /**
     * @dev    Calls the Seismic ECDH precompile (0x65); reverts `PrecompileFailed` on failure.
     * @param  privKey    The shielded private key.
     * @param  peerPubKey The peer's compressed public key.
     * @return The shielded ECDH shared secret.
     */
    function _ecdh(sbytes32 privKey, bytes memory peerPubKey) internal view returns (sbytes32) {
        (bool success, bytes memory result) = address(0x65).staticcall(abi.encodePacked(bytes32(privKey), peerPubKey));
        if (!success) revert PrecompileFailed(address(0x65));
        return sbytes32(abi.decode(result, (bytes32)));
    }

    /**
     * @dev    Calls the Seismic HKDF precompile (0x68); reverts `PrecompileFailed` on failure.
     * @param  sharedSecret The shielded ECDH shared secret.
     * @return The shielded AES-GCM key.
     */
    function _hkdf(sbytes32 sharedSecret) internal view returns (sbytes32) {
        (bool success, bytes memory result) = address(0x68).staticcall(abi.encodePacked(bytes32(sharedSecret)));
        if (!success) revert PrecompileFailed(address(0x68));
        return sbytes32(abi.decode(result, (bytes32)));
    }

    /**
     * @dev    Calls the Seismic AES-GCM encryption precompile (0x66); reverts `PrecompileFailed` on failure.
     * @param  key       The shielded AES-GCM key.
     * @param  nonce     The 12-byte nonce.
     * @param  plaintext The data to encrypt.
     * @return The ciphertext (auth tag included).
     */
    function _aesGcmEncrypt(sbytes32 key, bytes12 nonce, bytes memory plaintext) internal view returns (bytes memory) {
        (bool success, bytes memory ciphertext) = address(0x66).staticcall(
            abi.encodePacked(bytes32(key), nonce, plaintext)
        );
        if (!success) revert PrecompileFailed(address(0x66));
        return ciphertext;
    }

    /**
     * @dev   Sets the shielded allowance of `spender` over `account`'s tokens.
     * @param account     The account granting the allowance.
     * @param spender     The account allowed to spend on behalf of `account`.
     * @param amount      The shielded allowance amount.
     * @param encryptEmit Whether to emit the encrypted-bytes `Approval` overload or the plaintext one.
     */
    function _shieldedApprove(address account, address spender, suint256 amount, bool encryptEmit) internal {
        uint256 amount_ = uint256(amount);

        _beforeApprove(account, spender, amount_);

        _getMYieldToOneStorageLocation().shieldedAllowance[account][spender] = amount;

        if (encryptEmit) {
            (bytes32 encryptKeyHash, bytes memory ciphertext) = _encryptAmount(account, spender, amount);
            emit Approval(account, spender, encryptKeyHash, ciphertext);
        } else {
            emit Approval(account, spender, amount_);
        }
    }

    /**
     * @dev    Ungated shielded balance accessor for internal use.
     * @param  account The account whose balance is read.
     * @return The shielded balance of `account`.
     */
    function _balanceOf(address account) internal view returns (suint256) {
        return _getMYieldToOneStorageLocation().balanceOf[account];
    }

    /**
     * @dev    Returns whether `account` is trusted M0 infra: the `swapFacility` immutable or allowlisted.
     * @param  account The address being checked.
     * @return Whether `account` is trusted infra.
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
     * @dev   Reverts `InsufficientBalance(account, 0, amount)` — zeroed payload, no balance leak.
     * @param account The account whose shielded balance is checked.
     * @param amount  The amount required.
     */
    function _revertIfInsufficientBalance(address account, uint256 amount) internal view override {
        // NOTE: Branching on a shielded value leaks a 1-bit comparison via revert-vs-success;
        //       accepted — inherent to ERC20 insufficient-balance semantics (ssolc 10311).
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

        if ($.allowlist[account] == status) return;

        $.allowlist[account] = status;

        emit AllowlistSet(account, status);
    }
}
