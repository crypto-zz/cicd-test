pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../Lib/Error/ErrorReporter.sol";
import "../Oracle/PriceOracle.sol";
import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";
import "../Lib/Math/ExponentialNoError.sol";

/**
 * @title MetaLend's Comptroller Contract
 * @author MetaLend
 */
contract Comptroller is ComptrollerV1Storage, ComptrollerInterface, ComptrollerErrorReporter, ExponentialNoError {
    /// @notice Emitted when an admin supports a market
    event MarketListed(address cToken);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(address cToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(address market, uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

    /// @notice Emitted when liquidation discount is changed by admin
    event NewLiquidationDiscount(address market, uint oldLiquidationDiscountMantissa, uint newLiquidationDiscountMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(address cToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a cToken is changed
    event NewBorrowCap(CTokenInterface indexed cToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    constructor() public {
        admin = msg.sender;
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param cToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(address cToken, address minter) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[cToken], "mint is paused");

        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param cErc721Token The market to verify the mint against
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowedErc721(address cErc721Token) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[cErc721Token], "mint is paused");

        if (!markets[cErc721Token].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param cErc20CollateralToken The market to verify the mint against
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowedErc20Collateral(address cErc20CollateralToken) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[cErc20CollateralToken], "mint is paused");

        if (!markets[cErc20CollateralToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param cToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of cTokens to exchange for the underlying asset in the market
     * @param appraisal The appraisal of Erc721 assets
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(
        address cToken,
        address redeemer,
        uint redeemTokens,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        uint allowed = redeemAllowedInternal(cToken, redeemer, redeemTokens, appraisal);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(
        address cToken,
        address redeemer,
        uint redeemTokens,
        AppraisalStruct.Wire memory appraisal
    ) internal view returns (uint) {
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = liquidityAssessor.getHypotheticalAccountLiquidity(
            redeemer,
            CTokenInterface(cToken),
            CErc20CollateralInterface(0),
            redeemTokens,
            0,
            CErc721Interface(0),
            new uint256[](0),
            appraisal
        );

        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param cErc721Token The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param tokenIds The tokenIds to redeem
     * @param appraisal The appraisal of Erc721 assets
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowedErc721(
        address cErc721Token,
        address redeemer,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        require(tokenIds.length < 51, "Too many tokens, max 50 at once.");
        
        if (!markets[cErc721Token].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = liquidityAssessor.getHypotheticalAccountLiquidity(
            redeemer,
            CTokenInterface(0),
            CErc20CollateralInterface(0),
            0,
            0,
            CErc721Interface(address(cErc721Token)),
            tokenIds,
            appraisal
        );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param cErc20CollateralToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The tokens to redeem
     * @param appraisal The appraisal of Erc721 assets
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowedErc20Collateral(
        address cErc20CollateralToken,
        address redeemer,
        uint redeemTokens,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint) {
        if (!markets[cErc20CollateralToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = liquidityAssessor.getHypotheticalAccountLiquidity(
            redeemer,
            CTokenInterface(0),
            CErc20CollateralInterface(cErc20CollateralToken),
            redeemTokens,
            0,
            CErc721Interface(0),
            new uint256[](0),
            appraisal
        );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(uint redeemAmount, uint redeemTokens) external {
        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param cToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @param appraisal The appraisal of Erc721 assets
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function borrowAllowed(
        address cToken,
        address borrower,
        uint borrowAmount,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[cToken], "borrow is paused");

        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (oracle.getUnderlyingPrice(CTokenInterface(cToken)) == 0) {
            return uint(Error.PRICE_ERROR);
        }

        for (uint i = 0; i < allMarkets.length; i++) {
            address market = address(allMarkets[i]);
            if(CTokenInterface(market).borrowBalanceStored(borrower) > 0 && market != cToken) {
                return uint(Error.BORROW_MULTIPLE_MARKETS);
            }
        }

        uint borrowCap = borrowCaps[cToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = CTokenInterface(cToken).totalBorrows();
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (Error err, , uint shortfall) = liquidityAssessor.getHypotheticalAccountLiquidity(
            borrower,
            CTokenInterface(cToken),
            CErc20CollateralInterface(0),
            0,
            borrowAmount,
            CErc721Interface(0),
            new uint256[](0),
            appraisal
        );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param cToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external returns (uint) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     * @param appraisal The appraisal of Erc721 assets
     */
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint repayAmount,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint) {
        return liquidityAssessor.liquidateBorrowAllowed(
            cTokenBorrowed,
            cTokenCollateral,
            borrower,
            repayAmount,
            appraisal
        );
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cErc721TokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     * @param tokenIds The tokenIds to seize
     * @param appraisal The appraisal of Erc721 assets
     */
    function liquidateBorrowAllowedErc721(
        address cTokenBorrowed,
        address cErc721TokenCollateral,
        address borrower,
        uint repayAmount,
        uint256[] calldata tokenIds,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint) {
        if(CTokenInterface(cTokenBorrowed).borrowBalanceStored(borrower) == 0) {
            return uint(Error.LIQUIDATE_INACTIVE_BORROW);
        }

        return liquidityAssessor.liquidateBorrowAllowedErc721(
            cTokenBorrowed,
            cErc721TokenCollateral,
            borrower,
            repayAmount,
            tokenIds,
            appraisal
        );
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (!markets[cTokenCollateral].isListed || !markets[cTokenBorrowed].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (CTokenInterface(cTokenCollateral).comptroller() != CTokenInterface(cTokenBorrowed).comptroller()) {
            return uint(Error.COMPTROLLER_MISMATCH);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param cErc721TokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     */
    function seizeAllowedErc721(
        address cErc721TokenCollateral,
        address cTokenBorrowed
    ) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        if (!markets[cErc721TokenCollateral].isListed || !markets[cTokenBorrowed].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        return uint(Error.NO_ERROR);
    }

    function seizeAllowedErc20Collateral(
        address cErc20CollateralToken,
        address cTokenBorrowed
    ) external returns (uint) {
         // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        if (!markets[cErc20CollateralToken].isListed || !markets[cTokenBorrowed].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param cToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     * @param appraisal The appraisal of Erc721 assets
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint transferTokens,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint allowed = redeemAllowedInternal(cToken, src, transferTokens, appraisal);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in cToken.liquidateBorrowFresh)
     * @param cTokenBorrowed The address of the borrowed cToken
     * @param cTokenCollateral The address of the collateral cToken
     * @param actualRepayAmount The amount of cTokenBorrowed underlying to convert into cTokenCollateral tokens
     * @return (errorCode, number of cTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint actualRepayAmount
    ) external view returns (uint, uint) {
        return liquidityAssessor.liquidateCalculateSeizeTokens(
            cTokenBorrowed,
            cTokenCollateral,
            actualRepayAmount
        );
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation for cErc20CollateralToken collateral
     * @param cTokenBorrowed The address of the borrowed cToken
     * @param cErc20CollateralToken The address of the collateral cErc20CollateralToken
     * @param repayAmount The amount of cTokenBorrowed underlying to convert into cErc20CollateralToken tokens
     * @return (errorCode, number of cErc20CollateralToken tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeCErc20Collateral(
        address cTokenBorrowed,
        address cErc20CollateralToken,
        uint repayAmount
    ) external view returns (uint, uint) {
        return liquidityAssessor.liquidateCalculateSeizeCErc20Collateral(
            cTokenBorrowed,
            cErc20CollateralToken,
            repayAmount
        );
    }

    /*** Admin Functions ***/

    /**
      * @notice Sets a new price oracle for the comptroller
      * @dev Admin function to set a new price oracle
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setPriceOracle(PriceOracle newOracle) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK);
        }

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets the closeFactor used when liquidating borrows
      * @dev Admin function to set closeFactor
      * @param newCloseFactorMantissa New close factor, scaled by 1e18
      * @return uint 0=success, otherwise a failure
      */
    function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {
        // Check caller is admin
    	require(msg.sender == admin, "only admin can set close factor");

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets the collateralFactor for a market
      * @dev Admin function to set per-market collateralFactor
      * @param cToken The market to set the factor on
      * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
      * @param isErc721 Whether the market is for an Erc721 asset
      * @param isErc20Collateral Whether the market is for an Erc20Collateral asset
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setCollateralFactor(
        address cToken,
        uint newCollateralFactorMantissa,
        bool isErc721,
        bool isErc20Collateral
    ) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);
        }

        // Verify market is listed
        Market storage market = markets[cToken];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        if (!isErc721 && !isErc20Collateral && newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(CTokenInterface(cToken)) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(cToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets liquidationIncentive for ERC20 market
      * @dev Admin function to set liquidationIncentive
      * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setLiquidationIncentiveForMarket(address market, uint newLiquidationIncentiveMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissaPerMarket[market];

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissaPerMarket[market] = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(market, oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets liquidationDiscount for ERC721 market
      * @dev Admin function to set liquidationDiscount
      * @param newLiquidationDiscountMantissa New liquidationDiscount scaled by 1e18
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setLiquidationDiscountForMarket(address market, uint newLiquidationDiscountMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Save current value for use in log
        uint oldLiquidationDiscountMantissa = liquidationDiscountMantissaPerMarket[market];

        // Set liquidation discount to new discount
        liquidationDiscountMantissaPerMarket[market] = newLiquidationDiscountMantissa;

        // Emit event with old discount, new discount
        emit NewLiquidationDiscount(market, oldLiquidationDiscountMantissa, newLiquidationDiscountMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Add the market to the markets mapping and set it as listed
      * @dev Admin function to set isListed and add support for the market
      * @param cToken The address of the market (token) to list
      * @param isErc721 Whether the market is for an Erc721 asset
      * @param isErc20Collateral Whether the market is for an Erc20Collateral asset
      * @return uint 0=success, otherwise a failure. (See enum Error for details)
      */
    function _supportMarket(address cToken, bool isErc721, bool isErc20Collateral) external returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[cToken].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        markets[cToken] = Market({isListed: true, collateralFactorMantissa: 0});

        if (isErc721 && isErc20Collateral) {
            return fail(Error.INVALID_MARKET, FailureInfo.SUPPORT_MARKET_IS_VALID_CHECK);
        }
        if (isErc721) {
            _addMarketInternalErc721(cToken);
        } else if (isErc20Collateral) {
            _addMarketInternalErc20Collateral(cToken);
        } else {
            _addMarketInternal(cToken);
        }

        emit MarketListed(cToken);

        return uint(Error.NO_ERROR);
    }

    function _addMarketInternalErc721(address cErc721Token) internal {
        for (uint i = 0; i < allErc721Markets.length; i ++) {
            require(allErc721Markets[i] != CErc721Interface(cErc721Token), "market already added");
        }
        allErc721Markets.push(CErc721Interface(cErc721Token));
    }

    function _addMarketInternalErc20Collateral(address cErc20CollateralToken) internal {
        for (uint i = 0; i < allErc20CollateralMarkets.length; i ++) {
            require(allErc20CollateralMarkets[i] != CErc20CollateralInterface(cErc20CollateralToken), "market already added");
        }
        allErc20CollateralMarkets.push(CErc20CollateralInterface(cErc20CollateralToken));
    }

    function _addMarketInternal(address cToken) internal {
        for (uint i = 0; i < allMarkets.length; i ++) {
            require(allMarkets[i] != CTokenInterface(cToken), "market already added");
        }
        allMarkets.push(CTokenInterface(cToken));
    }

    /**
      * @notice Set the given borrow caps for the given cToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
      * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
      * @param cTokens The addresses of the markets (tokens) to change the borrow caps for
      * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
      */
    function _setMarketBorrowCaps(CTokenInterface[] calldata cTokens, uint[] calldata newBorrowCaps) external {
    	require(msg.sender == admin || msg.sender == borrowCapGuardian, "only admin or borrow cap guardian can set borrow caps");

        uint numMarkets = cTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for(uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(cTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(cTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");
        require(newBorrowCapGuardian != address(0), "borrow cap guardian cannot be zero address");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) public returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK);
        }
        require(newPauseGuardian != address(0), "pause guardian cannot be zero address");

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint(Error.NO_ERROR);
    }

    function _setMintPaused(address cToken, bool state) public returns (bool) {
        require(markets[cToken].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[cToken] = state;
        emit ActionPaused(cToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(address cToken, bool state) public returns (bool) {
        require(markets[cToken].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[cToken] = state;
        emit ActionPaused(cToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    function isMarketListed(address cToken) external view returns (bool) {
        return markets[cToken].isListed;
    }

    function getCollateralFactorMantissa(address asset) external view returns (uint) {
        return markets[asset].collateralFactorMantissa;
    }

    function getAllMarkets() external view returns (CTokenInterface[] memory) {
        return allMarkets;
    }

    function getAllErc721Markets() external view returns (CErc721Interface[] memory) {
        return allErc721Markets;
    }

    function getAllErc20CollateralMarkets() external view returns (CErc20CollateralInterface[] memory) {
        return allErc20CollateralMarkets;
    }

    function _setLiquidityAssessor(LiquidityAssessorInterface newLiquidityAssessor) external {
        require(msg.sender == admin);
        liquidityAssessor = newLiquidityAssessor;
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    function getCloseFactorMantissa() external view returns (uint) {
        return closeFactorMantissa;
    }

    function getMarketLiquidationDiscount(address market) external view returns (uint) {
        return liquidationDiscountMantissaPerMarket[market];
    }

    function getMarketLiquidationIncentive(address market) external view returns (uint) {
        return liquidationIncentiveMantissaPerMarket[market];
    }

    function getBorrowGuardianPaused(address cToken) external view returns (bool) {
        return borrowGuardianPaused[cToken];
    }

    function getOracle() external view returns (PriceOracle) {
        return oracle;
    }
}