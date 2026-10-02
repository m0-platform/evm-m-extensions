// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ContinuousIndexingMath } from "../../../../lib/common/src/libs/ContinuousIndexingMath.sol";
import { IndexingMath } from "../../../../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../../../../lib/common/src/libs/UIntMath.sol";

import { Options } from "../../../../lib/openzeppelin-foundry-upgrades/src/Options.sol";
import { Upgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMTokenLike } from "../../../../src/interfaces/IMTokenLike.sol";

import { IContinuousIndexing } from "../../../../src/projects/yieldToAllWithFee/interfaces/IContinuousIndexing.sol";
import { IRateOracle } from "../../../../src/projects/yieldToAllWithFee/interfaces/IRateOracle.sol";
import { IMSpokeYieldFee } from "../../../../src/projects/yieldToAllWithFee/interfaces/IMSpokeYieldFee.sol";

import { MSpokeYieldFeeHarness } from "../../../harness/MSpokeYieldFeeHarness.sol";
import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract MSpokeYieldFeeUnitTests is BaseUnitTest {
    MSpokeYieldFeeHarness public mYieldFee;

    function setUp() public override {
        super.setUp();

        Options memory deployOptions;
        deployOptions.constructorData = abi.encode(address(mToken), address(swapFacility), address(rateOracle));

        mYieldFee = MSpokeYieldFeeHarness(
            Upgrades.deployTransparentProxy(
                "MSpokeYieldFeeHarness.sol:MSpokeYieldFeeHarness",
                admin,
                abi.encodeWithSelector(
                    MSpokeYieldFeeHarness.initialize.selector,
                    "MSpokeYieldFee",
                    "MSYF",
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    feeManager,
                    claimRecipientManager,
                    freezeManager,
                    pauser
                ),
                deployOptions
            )
        );

        rateOracle.setEarnerRate(M_EARNER_RATE);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mYieldFee.ONE_HUNDRED_PERCENT(), 10_000);
        assertEq(mYieldFee.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.feeRate(), YIELD_FEE_RATE);
        assertEq(mYieldFee.feeRecipient(), feeRecipient);

        assertTrue(mYieldFee.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldFee.hasRole(FEE_MANAGER_ROLE, feeManager));
        assertTrue(mYieldFee.hasRole(CLAIM_RECIPIENT_MANAGER_ROLE, claimRecipientManager));
        assertTrue(mYieldFee.hasRole(FREEZE_MANAGER_ROLE, freezeManager));
        assertTrue(mYieldFee.hasRole(PAUSER_ROLE, pauser));

        assertEq(mYieldFee.rateOracle(), address(rateOracle));
    }

    function test_initialize_zeroRateOracle() external {
        vm.expectRevert(IMSpokeYieldFee.ZeroRateOracle.selector);
        new MSpokeYieldFeeHarness(address(mToken), address(swapFacility), address(0));
    }

    /* ============ currentIndex ============ */

    function test_currentIndex() external {
        mYieldFee.setIsEarningEnabled(true);
        mYieldFee.setLatestRate(mYiedFeeEarnerRate);

        uint256 expectedIndex = EXP_SCALED_ONE;
        assertEq(mYieldFee.currentIndex(), expectedIndex);

        uint40 previousTimestamp = uint40(startTimestamp);
        uint40 nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days);

        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);
        expectedCurrentIndex = _getCurrentIndex(EXP_SCALED_ONE, mYiedFeeEarnerRate, startTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        previousTimestamp = nextTimestamp;
        nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days * 2);

        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);
        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);

        // Half the earner rate
        rateOracle.setEarnerRate(M_EARNER_RATE / 2);
        mYiedFeeEarnerRate = _getEarnerRate(M_EARNER_RATE / 2, YIELD_FEE_RATE);

        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.latestRate(), mYiedFeeEarnerRate);

        previousTimestamp = nextTimestamp;
        nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days * 3);

        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);
        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        // Disable earning
        mYieldFee.disableEarning();

        previousTimestamp = nextTimestamp;

        nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days * 4);
        vm.warp(nextTimestamp);

        // Index should not change
        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);

        // Re-enable earning
        mYieldFee.enableEarning();

        assertEq(mYieldFee.latestRate(), mYiedFeeEarnerRate);

        // Index was just re-enabled, so value should still be the same
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);

        nextTimestamp = uint40(vm.getBlockTimestamp() + 365 days * 5);
        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);
        expectedCurrentIndex = _getCurrentIndex(expectedCurrentIndex, mYiedFeeEarnerRate, previousTimestamp);

        assertEq(mYieldFee.currentIndex(), expectedCurrentIndex);
        assertEq(mYieldFee.updateIndex(), expectedCurrentIndex);
    }

    function testFuzz_currentIndex(
        uint32 earnerRate,
        uint32 nextEarnerRate,
        uint16 feeRate,
        uint16 nextYieldFeeRate,
        bool isEarningEnabled,
        uint128 latestIndex,
        uint40 latestUpdateTimestamp,
        uint40 nextTimestamp,
        uint40 finalTimestamp
    ) external {
        latestUpdateTimestamp = uint40(bound(latestUpdateTimestamp, 0, type(uint40).max - 2));
        nextTimestamp = uint40(bound(nextTimestamp, latestUpdateTimestamp + 1, type(uint40).max - 1));
        finalTimestamp = uint40(bound(finalTimestamp, nextTimestamp + 1, type(uint40).max));

        feeRate = _setupYieldFeeRate(feeRate);

        vm.mockCall(address(mToken), abi.encodeWithSelector(IMTokenLike.earnerRate.selector), abi.encode(earnerRate));
        uint32 latestRate = mYieldFee.latestRate();

        mYieldFee.setIsEarningEnabled(isEarningEnabled);
        latestIndex = _setupLatestIndex(latestIndex);
        latestRate = _setupLatestRate(latestRate);

        vm.warp(latestUpdateTimestamp);

        mToken.setLatestUpdateTimestamp(latestUpdateTimestamp);
        mYieldFee.setLatestUpdateTimestamp(latestUpdateTimestamp);

        // No change in timestamp, so the index should be equal to the latest stored index
        assertEq(mYieldFee.currentIndex(), latestIndex);

        vm.warp(nextTimestamp);

        mToken.setLatestUpdateTimestamp(nextTimestamp);

        uint128 expectedIndex = isEarningEnabled
            ? _getCurrentIndex(latestIndex, latestRate, latestUpdateTimestamp)
            : latestIndex;

        assertEq(mYieldFee.currentIndex(), expectedIndex);

        // Update yield fee rate and M earner rate
        feeRate = _setupYieldFeeRate(nextYieldFeeRate);

        vm.mockCall(
            address(rateOracle),
            abi.encodeWithSelector(IRateOracle.earnerRate.selector),
            abi.encode(nextEarnerRate)
        );

        latestRate = mYieldFee.latestRate();
        latestRate = _setupLatestRate(latestRate);

        vm.warp(finalTimestamp);

        // expectedIndex was saved as the latest index and nextTimestamp is the latest saved timestamp
        expectedIndex = isEarningEnabled ? _getCurrentIndex(expectedIndex, latestRate, nextTimestamp) : latestIndex;
        assertEq(mYieldFee.currentIndex(), expectedIndex);
    }

    /* ============ _latestEarnerRateAccrualTimestamp ============ */

    function test_latestEarnerRateAccrualTimestamp() external {
        uint40 timestamp = uint40(22470340);

        vm.mockCall(
            address(mToken),
            abi.encodeWithSelector(IContinuousIndexing.latestUpdateTimestamp.selector),
            abi.encode(timestamp)
        );

        assertEq(mYieldFee.latestEarnerRateAccrualTimestamp(), timestamp);
    }

    /* ============ _currentEarnerRate ============ */

    function test_currentEarnerRate() external {
        uint32 earnerRate = 415;

        vm.mockCall(
            address(rateOracle),
            abi.encodeWithSelector(IRateOracle.earnerRate.selector),
            abi.encode(earnerRate)
        );

        assertEq(mYieldFee.currentEarnerRate(), earnerRate);
    }

    /* ============ currentIndex Utils ============ */

    function _getCurrentIndex(
        uint128 latestIndex,
        uint32 latestRate,
        uint40 latestUpdateTimestamp
    ) internal view returns (uint128) {
        return
            UIntMath.bound128(
                ContinuousIndexingMath.multiplyIndicesDown(
                    latestIndex,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(latestRate),
                        uint32(mYieldFee.latestEarnerRateAccrualTimestamp() - latestUpdateTimestamp)
                    )
                )
            );
    }

    /* ============ Fuzz Utils ============ */

    function _setupYieldFeeRate(uint16 rate) internal returns (uint16) {
        rate = uint16(bound(rate, 0, ONE_HUNDRED_PERCENT));

        vm.prank(feeManager);
        mYieldFee.setFeeRate(rate);

        return rate;
    }

    function _setupLatestRate(uint32 rate) internal returns (uint32) {
        rate = uint32(bound(rate, 10, 10_000));
        mYieldFee.setLatestRate(rate);
        return rate;
    }

    function _setupLatestIndex(uint128 latestIndex) internal returns (uint128) {
        latestIndex = uint128(bound(latestIndex, EXP_SCALED_ONE, 10_000000000000));
        mYieldFee.setLatestIndex(latestIndex);
        return latestIndex;
    }
}
