// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WadRayMath} from "../math/WadRayMath.sol";
import {MathUtils} from "../math/MathUtils.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {ReserveLogic} from "./ReserveLogic.sol";

/**
 * @title BorrowLogic library
 * @author ZeroLend
 * @notice Implements the base logic for borrow/repay
 */
library BorrowLogic {
    using WadRayMath for uint256;
    using ReserveLogic for DataTypes.ReserveData;

    /**
     * @dev Implements the borrow feature
     * @param reserve The reserve object
     * @param userConfig The user configuration
     * @param asset The address of the underlying asset
     * @param user The address of the user
     * @param onBehalfOf The address that will receive the debt
     * @param amount The amount to be borrowed
     * @param interestRateMode The interest rate mode
     * @param reserveFactor The reserve factor
     * @param referralCode The referral code
     * @param releaseUnderlying Whether to release the underlying asset
     * @return The final amount borrowed
     */
    function executeBorrow(
        DataTypes.ReserveData storage reserve,
        DataTypes.UserConfigurationMap storage userConfig,
        address asset,
        address user,
        address onBehalfOf,
        uint256 amount,
        uint256 interestRateMode,
        uint256 reserveFactor,
        uint16 referralCode,
        bool releaseUnderlying
    ) external returns (uint256) {
        DataTypes.ReserveCache memory reserveCache = reserve.cache();
        reserve.updateState(reserveFactor, reserveCache);

        // Validate borrow
        // ... (existing validation logic)

        // Update interest rates
        reserve.updateInterestRates(
            reserveCache,
            asset,
            reserve.cachedAvailableLiquidity()
        );

        // Update user debt
        // ... (existing debt update logic)

        if (releaseUnderlying) {
            // Transfer underlying asset to user
            // ... (existing transfer logic)
        }

        return amount;
    }
}