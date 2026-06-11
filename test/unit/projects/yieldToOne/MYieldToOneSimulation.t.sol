// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { Upgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MYieldToOneForcedTransfer } from "../../../../src/projects/yieldToOne/MYieldToOneForcedTransfer.sol";

import { ISwapFacility } from "../../../../src/swap/interfaces/ISwapFacility.sol";

import { MYieldToOneForcedTransferHarness } from "../../../harness/MYieldToOneForcedTransferHarness.sol";
import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract MYieldToOneSimulationTests is BaseUnitTest {
    uint256 internal constant _OPS_PER_RUN = 200;
    uint256 internal constant _MAX_WRAP_AMOUNT = 1e15;
    uint256 internal constant _MAX_YIELD_DELTA = 1e12;

    MYieldToOneForcedTransferHarness public mYieldToOne;

    address public infra = makeAddr("infra");

    address[] public holders;

    uint256 internal _lastNonce;

    function setUp() public override {
        super.setUp();

        mYieldToOne = MYieldToOneForcedTransferHarness(
            Upgrades.deployTransparentProxy(
                "MYieldToOneForcedTransferHarness.sol:MYieldToOneForcedTransferHarness",
                admin,
                abi.encodeWithSelector(
                    MYieldToOneForcedTransfer.initialize.selector,
                    "HALO USD",
                    "HALO USD",
                    yieldRecipient,
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    pauser,
                    forcedTransferManager
                ),
                mExtensionDeployOptions
            )
        );

        registrar.setEarner(address(mYieldToOne), true);

        vm.prank(admin);
        mYieldToOne.setAllowlisted(infra, true);

        holders = [alice, bob, charlie, david, yieldRecipient, address(swapFacility)];
    }

    /* ============ Simulation ============ */

    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: seismic.fuzz.runs = 1000
    function testFuzz_simulation(uint256 seed) external {
        _installContractKey();
        _mockPrecompiles();

        for (uint256 i; i < _OPS_PER_RUN; ++i) {
            address actor = accounts[(seed = _getNewSeed(seed)) % accounts.length];
            address peer = accounts[(seed = _getNewSeed(seed)) % accounts.length];

            // 10% chance to drip yield into the mock M token.
            if ((seed = _getNewSeed(seed)) % 100 < 10) {
                mToken.setBalanceOf(
                    address(mYieldToOne),
                    mToken.balanceOf(address(mYieldToOne)) + (_getNewSeed(seed) % _MAX_YIELD_DELTA)
                );
            }

            uint256 op = (seed = _getNewSeed(seed)) % 100;

            if (op < 12) _wrap((seed = _getNewSeed(seed)), actor, peer);
            else if (op < 22) _unwrap((seed = _getNewSeed(seed)), actor);
            else if (op < 37) _transfer((seed = _getNewSeed(seed)), actor, peer);
            else if (op < 47) _transferFromShielded((seed = _getNewSeed(seed)), actor, peer, false);
            else if (op < 55) _transferFromShielded((seed = _getNewSeed(seed)), actor, peer, true);
            else if (op < 63) _transferFromNative((seed = _getNewSeed(seed)), actor, peer);
            else if (op < 71) _claimYield(actor);
            else if (op < 76) _setYieldRecipient((seed = _getNewSeed(seed)));
            else if (op < 83) _forceTransfer((seed = _getNewSeed(seed)), peer);
            else if (op < 91) _toggleFreeze((seed = _getNewSeed(seed)), actor);
            else if (op < 95) _togglePause((seed = _getNewSeed(seed)));
            else _registerPublicKey((seed = _getNewSeed(seed)), actor);

            _checkInvariants();
        }
    }

    /* ============ Ops ============ */

    function _wrap(uint256 seed, address actor, address recipient) internal {
        if (mYieldToOne.paused() || mYieldToOne.isFrozen(actor) || mYieldToOne.isFrozen(recipient)) return;

        uint256 amount = bound(seed, 1, _MAX_WRAP_AMOUNT);

        mToken.setBalanceOf(address(swapFacility), mToken.balanceOf(address(swapFacility)) + amount);

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(actor));

        vm.prank(address(swapFacility));
        mYieldToOne.wrap(recipient, amount);
    }

    function _unwrap(uint256 seed, address actor) internal {
        if (mYieldToOne.paused() || mYieldToOne.isFrozen(actor)) return;

        uint256 balance = mYieldToOne.getBalanceOf(actor);

        if (balance == 0) return;

        uint256 amount = bound(seed, 1, balance);

        // Mirrors the production unwrap route through SwapFacility.
        vm.prank(actor);
        mYieldToOne.transfer(address(swapFacility), suint256(amount));

        vm.mockCall(address(swapFacility), abi.encodeWithSelector(ISwapFacility.msgSender.selector), abi.encode(actor));

        vm.prank(address(swapFacility));
        mYieldToOne.unwrap(actor, amount);

        vm.prank(address(swapFacility));
        mToken.transfer(actor, amount);
    }

    function _transfer(uint256 seed, address actor, address recipient) internal {
        if (mYieldToOne.paused() || mYieldToOne.isFrozen(actor) || mYieldToOne.isFrozen(recipient)) return;

        uint256 amount = bound(seed, 0, mYieldToOne.getBalanceOf(actor));

        vm.prank(actor);
        mYieldToOne.transfer(recipient, suint256(amount));
    }

    function _transferFromShielded(uint256 seed, address owner, address recipient, bool infinite) internal {
        address spender = accounts[_getNewSeed(seed) % accounts.length];

        if (mYieldToOne.paused()) return;
        if (mYieldToOne.isFrozen(owner) || mYieldToOne.isFrozen(spender) || mYieldToOne.isFrozen(recipient)) return;

        uint256 amount = bound(seed, 0, mYieldToOne.getBalanceOf(owner));

        vm.prank(owner);
        mYieldToOne.approve(spender, infinite ? suint256(type(uint256).max) : suint256(amount));

        vm.prank(spender);
        mYieldToOne.transferFrom(owner, recipient, suint256(amount));
    }

    function _transferFromNative(uint256 seed, address owner, address recipient) internal {
        if (mYieldToOne.paused() || mYieldToOne.isFrozen(owner) || mYieldToOne.isFrozen(recipient)) return;

        uint256 amount = bound(seed, 0, mYieldToOne.getBalanceOf(owner));

        vm.prank(owner);
        mYieldToOne.approve(infra, amount);

        vm.prank(infra);
        mYieldToOne.transferFrom(owner, recipient, amount);
    }

    function _claimYield(address actor) internal {
        if (mYieldToOne.paused()) return;

        vm.prank(actor);
        mYieldToOne.claimYield();
    }

    function _setYieldRecipient(uint256 seed) internal {
        address target = seed % 5 == 0 ? yieldRecipient : accounts[seed % accounts.length];

        vm.prank(yieldRecipientManager);
        mYieldToOne.setYieldRecipient(target);
    }

    function _forceTransfer(uint256 seed, address recipient) internal {
        for (uint256 i; i < accounts.length; ++i) {
            if (!mYieldToOne.isFrozen(accounts[i])) continue;

            uint256 amount = bound(seed, 0, mYieldToOne.getBalanceOf(accounts[i]));

            vm.prank(forcedTransferManager);
            mYieldToOne.forceTransfer(accounts[i], recipient, amount);

            return;
        }
    }

    function _toggleFreeze(uint256 seed, address actor) internal {
        if (mYieldToOne.isFrozen(actor)) {
            vm.prank(freezeManager);
            mYieldToOne.unfreeze(actor);
        } else if (seed % 3 == 0) {
            vm.prank(freezeManager);
            mYieldToOne.freeze(actor);
        }
    }

    function _togglePause(uint256 seed) internal {
        if (mYieldToOne.paused()) {
            vm.prank(pauser);
            mYieldToOne.unpause();
        } else if (seed % 4 == 0) {
            vm.prank(pauser);
            mYieldToOne.pause();
        }
    }

    function _registerPublicKey(uint256 seed, address actor) internal {
        vm.prank(actor);
        mYieldToOne.registerPublicKey(_validPubKey(bytes1(uint8(seed))));
    }

    /* ============ Invariants ============ */

    function _checkInvariants() internal {
        uint256 sum;
        for (uint256 i; i < holders.length; ++i) {
            sum += mYieldToOne.getBalanceOf(holders[i]);
        }

        assertEq(sum, mYieldToOne.totalSupply(), "Invariant 1 Failed: sum of balances != totalSupply");

        assertGe(
            mToken.balanceOf(address(mYieldToOne)),
            mYieldToOne.totalSupply(),
            "Invariant 2 Failed: M balance < totalSupply"
        );

        uint256 nonce = mYieldToOne.getEncryptedEventNonce();
        assertGe(nonce, _lastNonce, "Invariant 3 Failed: encrypted event nonce decreased");
        _lastNonce = nonce;
    }

    /* ============ Helpers ============ */

    function _validPubKey(bytes1 marker) internal pure returns (bytes memory) {
        bytes memory key = new bytes(33);
        key[0] = 0x02;
        for (uint256 i = 1; i < 33; ++i) {
            key[i] = marker;
        }
        return key;
    }

    function _installContractKey() internal {
        vm.prank(admin);
        mYieldToOne.setContractKey(sbytes32(bytes32(uint256(0xC0FFEE))), _validPubKey(0xAA));
    }

    function _mockPrecompiles() internal {
        vm.mockCall(address(0x65), bytes(""), abi.encode(bytes32(uint256(1))));
        vm.mockCall(address(0x68), bytes(""), abi.encode(bytes32(uint256(2))));
        vm.mockCall(address(0x66), bytes(""), hex"deadbeefcafebabe");
    }

    function _getNewSeed(uint256 seed) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed)));
    }
}
