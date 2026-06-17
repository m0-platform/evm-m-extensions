// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../../lib/common/src/libs/ContinuousIndexingMath.sol";

import { Options } from "../../lib/openzeppelin-foundry-upgrades/src/Options.sol";
import { Upgrades, UnsafeUpgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { IMExtension } from "../../src/interfaces/IMExtension.sol";
import { IMTokenLike } from "../../src/interfaces/IMTokenLike.sol";
import { IRegistrarLike } from "../../src/swap/interfaces/IRegistrarLike.sol";

import { MYieldFee } from "../../src/projects/yieldToAllWithFee/MYieldFee.sol";
import { MEarnerManager } from "../../src/projects/earnerManager/MEarnerManager.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { UniswapV3SwapAdapter } from "../../src/swap/UniswapV3SwapAdapter.sol";

import { MExtensionHarness } from "../harness/MExtensionHarness.sol";
import { MYieldToOneHarness } from "../harness/MYieldToOneHarness.sol";
import { MYieldFeeHarness } from "../harness/MYieldFeeHarness.sol";
import { JMIExtensionHarness } from "../harness/JMIExtensionHarness.sol";

import { Helpers } from "./Helpers.sol";

interface IMinterGateway {
    function minterRate() external view returns (uint32);
    function totalOwedM() external view returns (uint240);
    function updateIndex() external returns (uint128);
}

contract BaseIntegrationTest is Helpers, Test {
    address public constant deployer = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;
    address public constant proxyAdmin = 0xdcf79C332cB3Fe9d39A830a5f8de7cE6b1BD6fD1;

    address public constant standardGovernor = 0xB024aC5a7c6bC92fbACc8C3387E628a07e1Da016;
    address public constant registrar = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;

    IMinterGateway public constant minterGateway = IMinterGateway(0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E);

    IMTokenLike public constant mToken = IMTokenLike(0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b);
    IERC20 public constant wrappedM = IERC20(0x437cc33344a0B27A429f795ff6B469C72698B291);

    uint16 public constant YIELD_FEE_RATE = 2000; // 20%

    bytes32 public constant EARNERS_LIST = "earners";
    uint32 public constant M_EARNER_RATE = ContinuousIndexingMath.BPS_SCALED_ONE / 10; // 10% APY

    uint56 public constant EXP_SCALED_ONE = 1e12;

    // Large M holder on Ethereum Mainnet
    address public constant mSource = 0x3f0376da3Ae4313E7a5F1dA184BAFC716252d759;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant FREEZE_MANAGER_ROLE = keccak256("FREEZE_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant YIELD_RECIPIENT_MANAGER_ROLE = keccak256("YIELD_RECIPIENT_MANAGER_ROLE");
    bytes32 public constant ALLOWLIST_MANAGER_ROLE = keccak256("ALLOWLIST_MANAGER_ROLE");
    bytes32 public constant ALLOWLIST_ADMIN_ROLE = keccak256("ALLOWLIST_ADMIN_ROLE");
    bytes32 public constant EARNER_MANAGER_ROLE = keccak256("EARNER_MANAGER_ROLE");
    bytes32 public constant M_SWAPPER_ROLE = keccak256("M_SWAPPER_ROLE");
    bytes32 public constant CLAIM_RECIPIENT_MANAGER_ROLE = keccak256("CLAIM_RECIPIENT_MANAGER_ROLE");

    address public constant WRAPPED_M = 0x437cc33344a0B27A429f795ff6B469C72698B291;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public admin = makeAddr("admin");
    address public assetCapManager = makeAddr("assetCapManager");
    address public pauser = makeAddr("pauser");
    address public freezeManager = makeAddr("freezeManager");
    address public yieldRecipient = makeAddr("yieldRecipient");
    address public yieldRecipientManager = makeAddr("yieldRecipientManager");
    address public allowlistAdmin = makeAddr("allowlistAdmin");
    address public feeManager = makeAddr("feeManager");
    address public claimRecipientManager = makeAddr("claimRecipientManager");
    address public earnerManager = makeAddr("earnerManager");
    address public feeRecipient = makeAddr("feeRecipient");

    address public alice;
    uint256 public aliceKey;

    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public charlie = makeAddr("charlie");
    address public david = makeAddr("david");

    address[] public accounts = [alice, bob, carol, charlie, david];

    MExtensionHarness public mExtension;
    MYieldToOneHarness public mYieldToOne;
    MYieldFeeHarness public mYieldFee;
    JMIExtensionHarness public jmiExtension;
    MEarnerManager public mEarnerManager;
    SwapFacility public swapFacility;
    UniswapV3SwapAdapter public swapAdapter;

    string public constant NAME = "M USD Extension";
    string public constant SYMBOL = "MUSDE";

    Options public mExtensionDeployOptions;

    function setUp() public virtual {
        (alice, aliceKey) = makeAddrAndKey("alice");
        accounts = [alice, bob, carol, charlie, david];

        swapFacility = SwapFacility(
            UnsafeUpgrades.deployTransparentProxy(
                address(new SwapFacility(address(mToken), address(registrar))),
                admin,
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin, pauser)
            )
        );

        address[] memory whitelistedTokens = new address[](3);
        whitelistedTokens[0] = WRAPPED_M;
        whitelistedTokens[1] = USDC;
        whitelistedTokens[2] = USDT;

        swapAdapter = new UniswapV3SwapAdapter(
            WRAPPED_M,
            address(swapFacility),
            0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // Uniswap V3 Router
            admin,
            whitelistedTokens
        );

        mExtensionDeployOptions.constructorData = abi.encode(address(mToken), address(swapFacility));

        vm.startPrank(admin);

        swapFacility.grantRole(M_SWAPPER_ROLE, alice);
        swapFacility.grantRole(M_SWAPPER_ROLE, bob);
        swapFacility.grantRole(M_SWAPPER_ROLE, feeRecipient);
        swapFacility.setTrustedRouter(address(swapAdapter), true);

        vm.stopPrank();
    }

    function _addToList(bytes32 list, address account) internal {
        vm.prank(standardGovernor);
        IRegistrarLike(registrar).addToList(list, account);
    }

    function _removeFromList(bytes32 list, address account) internal {
        vm.prank(standardGovernor);
        IRegistrarLike(registrar).removeFromList(list, account);
    }

    function _giveM(address account, uint256 amount) internal {
        vm.prank(mSource);
        mToken.transfer(account, amount);
    }

    function _giveEth(address account, uint256 amount) internal {
        vm.deal(account, amount);
    }

    function _swapInM(address mExtension_, address account, address recipient, uint256 amount) internal {
        vm.prank(account);
        mToken.approve(address(swapFacility), amount);

        vm.prank(account);
        swapFacility.swap(address(mToken), mExtension_, amount, recipient);
    }

    function _swapInMWithPermitVRS(
        address mExtension_,
        address account,
        uint256 signerPrivateKey,
        address recipient,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _getMPermit(
            address(swapFacility),
            account,
            signerPrivateKey,
            amount,
            nonce,
            deadline
        );

        vm.prank(account);
        swapFacility.swapWithPermit(address(mToken), mExtension_, amount, recipient, deadline, v_, r_, s_);
    }

    function _swapInMWithPermitSignature(
        address mExtension_,
        address account,
        uint256 signerPrivateKey,
        address recipient,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _getMPermit(
            address(swapFacility),
            account,
            signerPrivateKey,
            amount,
            nonce,
            deadline
        );

        vm.prank(account);
        swapFacility.swapWithPermit(address(mToken), mExtension_, amount, recipient, deadline, v_, r_, s_);
    }

    function _swapMOut(address mExtension_, address account, address recipient, uint256 amount) internal {
        vm.prank(account);
        IMExtension(mExtension_).approve(address(swapFacility), amount);

        vm.prank(account);
        swapFacility.swap(mExtension_, address(mToken), amount, recipient);
    }

    function _swapOutMWithPermitVRS(
        address mExtension_,
        address account,
        uint256 signerPrivateKey,
        address recipient,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _getExtensionPermit(
            mExtension_,
            address(swapFacility),
            account,
            signerPrivateKey,
            amount,
            nonce,
            deadline
        );

        vm.prank(account);
        swapFacility.swapWithPermit(mExtension_, address(mToken), amount, recipient, deadline, v_, r_, s_);
    }

    function _swapOutMWithPermitSignature(
        address mExtension_,
        address account,
        uint256 signerPrivateKey,
        address recipient,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _getExtensionPermit(
            mExtension_,
            address(swapFacility),
            account,
            signerPrivateKey,
            amount,
            nonce,
            deadline
        );

        vm.prank(account);
        swapFacility.swapWithPermit(mExtension_, address(mToken), amount, recipient, deadline, v_, r_, s_);
    }

    function _set(bytes32 key, bytes32 value) internal {
        vm.prank(standardGovernor);
        IRegistrarLike(registrar).setKey(key, value);
    }

    function _fundAccounts() internal {
        for (uint256 i = 0; i < accounts.length; ++i) {
            _giveM(accounts[i], 10e6);
            _giveEth(accounts[i], 0.1 ether);
        }
    }

    /* ============ utils ============ */

    function _makeKey(string memory name_) internal returns (uint256 key_) {
        (, key_) = makeAddrAndKey(name_);
    }

    function _getMPermit(
        address spender,
        address account,
        uint256 signerPrivateKey,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v_, bytes32 r_, bytes32 s_) {
        return
            vm.sign(
                signerPrivateKey,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        mToken.DOMAIN_SEPARATOR(),
                        keccak256(abi.encode(mToken.PERMIT_TYPEHASH(), account, spender, amount, nonce, deadline))
                    )
                )
            );
    }

    function _getExtensionPermit(
        address extension,
        address spender,
        address account,
        uint256 signerPrivateKey,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v_, bytes32 r_, bytes32 s_) {
        return
            vm.sign(
                signerPrivateKey,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        IMExtension(extension).DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                IMExtension(extension).PERMIT_TYPEHASH(),
                                account,
                                spender,
                                amount,
                                nonce,
                                deadline
                            )
                        )
                    )
                )
            );
    }
}
