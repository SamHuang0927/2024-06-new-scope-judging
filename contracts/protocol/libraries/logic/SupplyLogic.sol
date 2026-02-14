// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WadRayMath} from "../math/WadRayMath.sol";
import {MathUtils} from "../math/MathUtils.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {ReserveLogic} from "./ReserveLogic.sol";

/**
 * @title SupplyLogic library
 * @author ZeroLend
 * @notice Implements the base logic for supply/withdraw
 */
library SupplyLogic {
    using WadRayMath for uint256;
    using ReserveLogic for DataTypes.ReserveData;

    /**
     * @dev Implements the supply feature
     * @param reserve The reserve object
     * @param userConfig The user configuration
     * @param balance The user balance
     * @param totalSupply The total supply
     * @param params The additional parameters needed to execute the supply function
     * @return The amount of shares minted
     */
    function executeSupply(
        DataTypes.ReserveData storage reserve,
        DataTypes.UserConfigurationMap storage userConfig,
        uint256 balance,
        uint256 totalSupply,
        DataTypes.ExecuteSupplyParams memory params
    ) external returns (DataTypes.SharesType memory) {
        DataTypes.ReserveCache memory reserveCache = reserve.cache();
        reserve.updateState(params.reserveFactor, reserveCache);

        uint256 amountInShares = 0;
        if (totalSupply == 0) {
            amountInShares = params.amount;
        } else {
            amountInShares = params.amount.rayDiv(reserveCache.nextLiquidityIndex);
        }

        reserve.updateInterestRates(
            reserveCache,
            params.asset,
            reserve.cachedAvailableLiquidity()
        );

        // Update user state
        balance += amountInShares;
        userConfig.setUsingAsCollateral(reserve.id, true);

        return DataTypes.SharesType(amountInShares, params.amount);
    }
}