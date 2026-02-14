// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WadRayMath} from "../math/WadRayMath.sol";
import {MathUtils} from "../math/MathUtils.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";

/**
 * @title ReserveLogic library
 * @author ZeroLend
 * @notice Implements the logic to update the reserves state
 */
library ReserveLogic {
    using WadRayMath for uint256;

    /**
     * @dev Initializes a reserve
     * @param reserve The reserve object
     * @param aTokenAddress The address of the overlying aToken contract
     * @param variableDebtTokenAddress The address of the overlying variable debt token contract
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     * @param reserveFactor The reserve factor of the reserve
     */
    function init(
        DataTypes.ReserveData storage reserve,
        address aTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint256 reserveFactor
    ) external {
        require(
            reserve.aTokenAddress == address(0),
            Errors.RESERVE_ALREADY_INITIALIZED
        );

        reserve.aTokenAddress = aTokenAddress;
        reserve.variableDebtTokenAddress = variableDebtTokenAddress;
        reserve.interestRateStrategyAddress = interestRateStrategyAddress;
        reserve.reserveFactor = reserveFactor;
    }

    /**
     * @notice Updates the liquidity cumulative index and variable borrow cumulative index
     * @param reserve The reserve object
     * @param reserveCache The cached reserve data
     */
    function _updateIndexes(
        DataTypes.ReserveData storage reserve,
        DataTypes.ReserveCache memory reserveCache
    ) internal {
        if (reserveCache.currLiquidityRate != 0) {
            uint256 cumulatedLiquidityInterest = MathUtils
                .calculateLinearInterest(
                    reserveCache.currLiquidityRate,
                    reserveCache.reserveLastUpdateTimestamp
                );
            reserveCache.nextLiquidityIndex = cumulatedLiquidityInterest.rayMul(
                reserveCache.currLiquidityIndex
            );
            reserve.liquidityIndex = reserveCache
                .nextLiquidityIndex
                .toUint128();
        }

        if (reserveCache.currVariableBorrowRate != 0) {
            uint256 cumulatedVariableBorrowInterest = MathUtils
                .calculateCompoundedInterest(
                    reserveCache.currVariableBorrowRate,
                    reserveCache.reserveLastUpdateTimestamp
                );
            reserveCache.nextVariableBorrowIndex = cumulatedVariableBorrowInterest
                .rayMul(reserveCache.currVariableBorrowIndex);
            reserve.variableBorrowIndex = reserveCache
                .nextVariableBorrowIndex
                .toUint128();
        }
    }

    /**
     * @dev Accumulates a predefined amount of asset to the reserve as a fixed, instantaneous income. Used for example to accumulate
     * the flash loan fee to the reserve.
     * @param reserve The reserve object
     * @param totalLiquidity The total liquidity available in the reserve
     * @param amount The amount to accumulate
     * @return The next liquidity index of the reserve
     */
    function cumulateToLiquidityIndex(
        DataTypes.ReserveData storage reserve,
        uint256 totalLiquidity,
        uint256 amount
    ) external returns (uint256) {
        //solium-disable-next-line
        uint256 result = totalLiquidity == 0
            ? WadRayMath.RAY
            : amount.rayDiv(totalLiquidity).rayMul(WadRayMath.RAY) +
                WadRayMath.RAY;
        uint256 nextLiquidityIndex = result.rayMul(reserve.liquidityIndex);
        reserve.liquidityIndex = nextLiquidityIndex.toUint128();
        return nextLiquidityIndex;
    }

    /**
     * @dev Updates the reserve current variable borrow rate, the current stable borrow rate and the current liquidity rate
     * @param reserve The reserve object
     * @param reserveCache The cached reserve data
     */
    function updateInterestRates(
        DataTypes.ReserveData storage reserve,
        DataTypes.ReserveCache memory reserveCache,
        address asset,
        uint256 availableLiquidity
    ) internal {
        (
            uint256 newLiquidityRate,
            uint256 newVariableBorrowRate
        ) = IReserveInterestRateStrategy(reserve.interestRateStrategyAddress)
                .calculateInterestRates(
                    DataTypes.CalculateInterestRatesParams({
                        asset: asset,
                        availableLiquidity: availableLiquidity,
                        totalVariableDebt: reserveCache.nextVariableBorrowIndex == 0
                            ? 0
                            : reserveCache.currVariableDebt.rayMul(
                                reserveCache.nextVariableBorrowIndex
                            ),
                        reserveFactor: reserveCache.currReserveFactor, // Use cached reserve factor
                        reserve: reserve
                    })
                );

        reserveCache.currLiquidityRate = newLiquidityRate;
        reserveCache.currVariableBorrowRate = newVariableBorrowRate;

        reserve.currentLiquidityRate = newLiquidityRate.toUint128();
        reserve.currentVariableBorrowRate = newVariableBorrowRate.toUint128();
    }

    /**
     * @dev Mints part of the repaid interest to the reserve treasury as a function of the reserveFactor for the
     * specific asset.
     * @param reserveCache The cached reserve data
     * @param reserve The reserve object
     */
    function _accrueToTreasury(
        DataTypes.ReserveCache memory reserveCache,
        DataTypes.ReserveData storage reserve
    ) internal {
        if (reserveCache.currReserveFactor == 0) { // Use cached reserve factor
            return;
        }

        uint256 prevTotalVariableDebt = reserveCache.currVariableDebt.rayMul(
            reserveCache.currVariableBorrowIndex
        );

        uint256 currTotalVariableDebt = reserveCache.currVariableDebt.rayMul(
            reserveCache.nextVariableBorrowIndex
        );

        uint256 totalDebtAccrued = currTotalVariableDebt - prevTotalVariableDebt;

        if (totalDebtAccrued == 0) {
            return;
        }

        uint256 amountToMint = totalDebtAccrued.percentMul(
            reserveCache.currReserveFactor // Use cached reserve factor
        );

        if (amountToMint != 0) {
            reserve.accruedToTreasury += amountToMint
                .rayDiv(reserveCache.nextLiquidityIndex)
                .toUint128();
        }
    }

    /**
     * @notice Updates the state of the reserve
     * @param reserve The reserve object
     * @param reserveFactor The current reserve factor
     * @param reserveCache The cached reserve data
     */
    function updateState(
        DataTypes.ReserveData storage reserve,
        uint256 reserveFactor,
        DataTypes.ReserveCache memory reserveCache
    ) internal {
        if (reserve.lastUpdateTimestamp == uint40(block.timestamp)) {
            return;
        }

        // Cache the current reserve factor to ensure consistency between _updateIndexes and _accrueToTreasury
        reserveCache.currReserveFactor = reserveFactor;

        _updateIndexes(reserve, reserveCache);
        _accrueToTreasury(reserveCache, reserve);

        reserve.lastUpdateTimestamp = uint40(block.timestamp);
    }

    /**
     * @notice Initializes a reserve
     * @param reserve The reserve object
     * @param aTokenAddress The address of the overlying aToken contract
     * @param variableDebtTokenAddress The address of the overlying variable debt token contract
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     * @param reserveFactor The reserve factor of the reserve
     */
    function initialize(
        DataTypes.ReserveData storage reserve,
        address aTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint256 reserveFactor
    ) external {
        require(
            reserve.aTokenAddress == address(0),
            Errors.RESERVE_ALREADY_INITIALIZED
        );

        reserve.aTokenAddress = aTokenAddress;
        reserve.variableDebtTokenAddress = variableDebtTokenAddress;
        reserve.interestRateStrategyAddress = interestRateStrategyAddress;
        reserve.reserveFactor = reserveFactor;
    }
}