pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../CErc721/CErc721Interface.sol";
import "../Lib/Error/ErrorReporter.sol";
import "../Lib/Math/ExponentialNoError.sol";
import "../Comptroller/ComptrollerInterface.sol";
import "../Oracle/AppraisalOracleInterface.sol";
import "../CErc20/CErc20CollateralInterface.sol";

/**
 * @title MetaLend's LiquidityAssessor Contract
 * @notice Performs liquidity checks used by various CToken operations
 * @author MetaLend
 */
contract LiquidityAssessor is ComptrollerErrorReporter, ExponentialNoError {
    event NewAdmin(address indexed newAdmin, address indexed previousAdmin);
    
    address public admin;

    ComptrollerInterface public comptroller;

    AppraisalOracleInterface public appraisalOracle;

    constructor() public {
        // Set admin to caller
        admin = msg.sender;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @param account The account to assess
     * @param appraisal The appraisal of Erc721 assets
     * @return (possible error code (semi-opaque),
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(
        address account,
        AppraisalStruct.Wire memory appraisal
    ) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidity(
            account,
            CTokenInterface(0),
            CErc20CollateralInterface(0),
            0,
            0,
            CErc721Interface(0),
            new uint256[](0),
            appraisal
        );

        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine the total borrows of an account
     * @param account The account to assess
     * @return account total borrows
     */
    function getTotalBorrows(
        address account
    ) external view returns (uint) {
        CTokenInterface[] memory accountAssets = comptroller.getAllMarkets();
        uint sumBorrow = 0;

        for (uint i = 0; i < accountAssets.length; i++) {
            CTokenInterface asset = accountAssets[i];
            uint borrowBalance = 0;
            uint oErr;
            uint cTokenBalance;
            uint exchangeRateMantissa;

            (oErr, cTokenBalance, borrowBalance, exchangeRateMantissa) = asset.getAccountSnapshot(account);
            if (oErr != 0) {
                return 0;
            }

            // Get the normalized price of the asset
            uint oraclePriceMantissa = comptroller.getOracle().getUnderlyingPrice(asset);
            if (oraclePriceMantissa == 0) {
                return 0;
            }
            Exp memory oraclePrice = Exp({mantissa: oraclePriceMantissa});
            sumBorrow = mul_ScalarTruncateAddUInt(oraclePrice, borrowBalance, sumBorrow);
        }

        return sumBorrow;
    }

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `cTokenBalance` is the number of cTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint borrowBalance;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param account The account to determine liquidity for
     * @param cTokenModify The market to hypothetically redeem/borrow in
     * @param cErc20CollateralTokenModify The market to hypothetically redeem in
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @param cErc721TokenModify The market to hypothetically redeem in
     * @param redeemErc721TokenIds The tokenIds to hypothetically redeem
     * @param appraisal The appraisal of Erc721 assets
     * @dev Note that we calculate the exchangeRateStored for each collateral cToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        CTokenInterface cTokenModify,
        CErc20CollateralInterface cErc20CollateralTokenModify,
        uint redeemTokens,
        uint borrowAmount,
        CErc721Interface cErc721TokenModify,
        uint256[] memory redeemErc721TokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public view returns (Error, uint, uint) {
        require(appraisalOracle.verifyAppraisals(appraisal), "appraisal is invalid");

        AccountLiquidityLocalVars memory accountVars; // Holds all our calculation results
        Error oErr;

        oErr = updateCTokenAccountLiquidity(account, cTokenModify, redeemTokens, borrowAmount, accountVars);
        if (oErr != Error.NO_ERROR) {
            return (oErr, 0, 0);
        }
        oErr = updateCErc721AccountLiquidity(account, cErc721TokenModify, redeemErc721TokenIds, appraisal, accountVars);
        if (oErr != Error.NO_ERROR) {
            return (oErr, 0, 0);
        }
        oErr = updateCErc20CollateralAccountLiquidity(account, cErc20CollateralTokenModify, redeemTokens, borrowAmount, accountVars);
        if (oErr != Error.NO_ERROR) {
            return (oErr, 0, 0);
        }

        // These are safe, as the underflow condition is checked first
        if (accountVars.sumCollateral > accountVars.sumBorrowPlusEffects) {
            return (Error.NO_ERROR, accountVars.sumCollateral - accountVars.sumBorrowPlusEffects, 0);
        } else {
            return (Error.NO_ERROR, 0, accountVars.sumBorrowPlusEffects - accountVars.sumCollateral);
        }
    }

    function updateCTokenAccountLiquidity(
        address account,
        CTokenInterface cTokenModify,
        uint redeemTokens,
        uint borrowAmount,
        AccountLiquidityLocalVars memory accountLiquidityState
    ) internal view returns (Error) {
        uint oErr;
        uint cTokenBalance;
        Exp memory exchangeRate;
        uint exchangeRateMantissa;
        CTokenInterface[] memory accountAssets = comptroller.getAllMarkets();
        for (uint i = 0; i < accountAssets.length; i++) {
            CTokenInterface asset = accountAssets[i];

            // Read the balances and exchange rate from the cToken
            (oErr, cTokenBalance, accountLiquidityState.borrowBalance, exchangeRateMantissa) = asset.getAccountSnapshot(account);
            if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return Error.SNAPSHOT_ERROR;
            }
            accountLiquidityState.collateralFactor = Exp({mantissa: comptroller.getCollateralFactorMantissa(address(asset))});
            exchangeRate = Exp({mantissa: exchangeRateMantissa});

            // Get the normalized price of the asset
            accountLiquidityState.oraclePriceMantissa = comptroller.getOracle().getUnderlyingPrice(asset);
            if (accountLiquidityState.oraclePriceMantissa == 0) {
                return Error.PRICE_ERROR;
            }
            accountLiquidityState.oraclePrice = Exp({mantissa: accountLiquidityState.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            accountLiquidityState.tokensToDenom = mul_(mul_(accountLiquidityState.collateralFactor, exchangeRate), accountLiquidityState.oraclePrice);

            // sumCollateral += tokensToDenom * cTokenBalance
            accountLiquidityState.sumCollateral = mul_ScalarTruncateAddUInt(accountLiquidityState.tokensToDenom, cTokenBalance, accountLiquidityState.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            accountLiquidityState.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(accountLiquidityState.oraclePrice, accountLiquidityState.borrowBalance, accountLiquidityState.sumBorrowPlusEffects);

            // Calculate effects of interacting with cTokenModify
            if (asset == cTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                accountLiquidityState.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(accountLiquidityState.tokensToDenom, redeemTokens, accountLiquidityState.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                accountLiquidityState.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(accountLiquidityState.oraclePrice, borrowAmount, accountLiquidityState.sumBorrowPlusEffects);
            }
        }
        return Error.NO_ERROR;
    }

    function updateCErc721AccountLiquidity(
        address account,
        CErc721Interface cErc721TokenModify,
        uint256[] memory redeemErc721TokenIds,
        AppraisalStruct.Wire memory appraisal,
        AccountLiquidityLocalVars memory accountLiquidityState
    ) internal view returns (Error) {
        Exp memory sumErc721Collateral;
        uint256[] memory accountErc721Tokens;
        CErc721Interface[] memory accountErc721Assets = comptroller.getAllErc721Markets();
        require(accountErc721Assets.length == appraisal.appraisalTokens.length, "appraisal has wrong amount of tokens");

        for (uint i = 0; i < accountErc721Assets.length; i++) {
            CErc721Interface erc721Asset = accountErc721Assets[i];
            accountErc721Tokens = erc721Asset.getAccountTokens(account);
            accountLiquidityState.collateralFactor = Exp({mantissa: comptroller.getCollateralFactorMantissa(address(erc721Asset))});

            if (accountErc721Tokens.length == 0) {
                continue;
            }
            // this forces an ordering on appraisalLengths based on the order of getAllErc721Markets
            require(accountErc721Tokens.length == appraisal.appraisalLengths[i], "appraisal has wrong amount of tokenIds");

            sumErc721Collateral = Exp({mantissa: 0});
            for (uint j = 0; j < accountErc721Tokens.length; j++) {
                accountLiquidityState.oraclePriceMantissa = getAppraisal(appraisal, address(erc721Asset), accountErc721Tokens[j]);
                if (accountLiquidityState.oraclePriceMantissa == 0) {
                    return Error.PRICE_ERROR;
                }
                accountLiquidityState.oraclePrice = Exp({mantissa: accountLiquidityState.oraclePriceMantissa});

                // sumErc721Collateral += oraclePrice
                sumErc721Collateral = add_(accountLiquidityState.oraclePrice, sumErc721Collateral);
            }

            // sumCollateral += sumErc721Collateral * collateralFactor
            accountLiquidityState.sumCollateral = add_(truncate(mul_(sumErc721Collateral, accountLiquidityState.collateralFactor)), accountLiquidityState.sumCollateral);

            // Calculate effects of interacting with cErc721TokenModify
            if (erc721Asset == cErc721TokenModify) {
                sumErc721Collateral = Exp({mantissa: 0});
                for (uint j = 0; j < redeemErc721TokenIds.length; j++) {
                    accountLiquidityState.oraclePriceMantissa = getAppraisal(appraisal, address(erc721Asset), redeemErc721TokenIds[j]);
                    if (accountLiquidityState.oraclePriceMantissa == 0) {
                        return Error.PRICE_ERROR;
                    }
                    accountLiquidityState.oraclePrice = Exp({mantissa: accountLiquidityState.oraclePriceMantissa});

                    // sumErc721Collateral += oraclePrice
                    sumErc721Collateral = add_(accountLiquidityState.oraclePrice, sumErc721Collateral);
                }

                // redeem effect
                // sumBorrowPlusEffects += sumErc721Collateral
                accountLiquidityState.sumBorrowPlusEffects = add_(truncate(mul_(sumErc721Collateral, accountLiquidityState.collateralFactor)), accountLiquidityState.sumBorrowPlusEffects);
            }
        }
        return Error.NO_ERROR;
    }

    function updateCErc20CollateralAccountLiquidity(
        address account,
        CErc20CollateralInterface cErc20CollateralTokenModify,
        uint redeemTokens,
        uint borrowAmount,
        AccountLiquidityLocalVars memory accountLiquidityState
    ) internal view returns (Error) {
        uint accountErc20CollateralTokens;
        CErc20CollateralInterface[] memory accountErc20CollateralAssets;

        accountErc20CollateralAssets = comptroller.getAllErc20CollateralMarkets();
        for (uint i = 0; i < accountErc20CollateralAssets.length; i++) {
            CErc20CollateralInterface asset = accountErc20CollateralAssets[i];
            accountErc20CollateralTokens = asset.getAccountTokens(account);

            if (accountErc20CollateralTokens == 0) {
                continue;
            }
            accountLiquidityState.collateralFactor = Exp({mantissa: comptroller.getCollateralFactorMantissa(address(asset))});

            // Get the normalized price of the asset
            accountLiquidityState.oraclePriceMantissa = comptroller.getOracle().getUnderlyingPrice(CTokenInterface(address(asset)));
            if (accountLiquidityState.oraclePriceMantissa == 0) {
                return Error.PRICE_ERROR;
            }
            accountLiquidityState.oraclePrice = Exp({mantissa: accountLiquidityState.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            accountLiquidityState.tokensToDenom = mul_(accountLiquidityState.collateralFactor, accountLiquidityState.oraclePrice);

            // sumCollateral += tokensToDenom * cTokenBalance
            accountLiquidityState.sumCollateral = mul_ScalarTruncateAddUInt(accountLiquidityState.tokensToDenom, accountErc20CollateralTokens, accountLiquidityState.sumCollateral);

            // Calculate effects for interacting with cErc20CollateralTokenModify
            if (asset == cErc20CollateralTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                accountLiquidityState.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(accountLiquidityState.tokensToDenom, redeemTokens, accountLiquidityState.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                accountLiquidityState.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(accountLiquidityState.oraclePrice, borrowAmount, accountLiquidityState.sumBorrowPlusEffects);
            }
        }
        return Error.NO_ERROR;
    }

    /**
     * @notice Get the appraised value of a tokenId
     * @param wire The appraisal of Erc721 assets
     * @param cErc721Token The token to appraise
     * @param tokenId The tokenId to appraise
     * @return The value in wei of a tokenId, scaled by 1e18
     */
    function getAppraisal(
        AppraisalStruct.Wire memory wire,
        address cErc721Token,
        uint256 tokenId
    ) public pure returns (uint) {
        uint cursor = 0;
        for (uint i = 0; i < wire.appraisalTokens.length; i++) {
            address token = wire.appraisalTokens[i];

            for (uint j = 0; j < wire.appraisalLengths[i]; j++) {
                uint256 tokenId_ = wire.appraisalTokenIds[cursor];

                if (tokenId_  == tokenId && token == cErc721Token) {
                    return wire.appraisalValues[cursor];
                }
                cursor++;
            }
        }

        // nothing found
        return 0;
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint repayAmount,
        AppraisalStruct.Wire memory appraisal
    ) public view returns (uint) {
        if (!comptroller.isMarketListed(cTokenBorrowed) || !comptroller.isMarketListed(cTokenCollateral)) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        uint borrowBalance = CTokenInterface(cTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(CTokenInterface(cTokenBorrowed))) {
            require(borrowBalance >= repayAmount, "Can not repay more than the total borrow");
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            (uint err, , uint shortfall) = getAccountLiquidity(borrower, appraisal);
            if (err != uint(Error.NO_ERROR)) {
                return uint(err);
            }

            if (shortfall == 0) {
                return uint(Error.INSUFFICIENT_SHORTFALL);
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint maxClose = mul_ScalarTruncate(Exp({mantissa: comptroller.getCloseFactorMantissa()}), borrowBalance);
            if (repayAmount > maxClose) {
                return uint(Error.TOO_MUCH_REPAY);
            }
        }
        return uint(Error.NO_ERROR);
    }

    struct LiquidateBorrowLocalVars {
        Exp sumAppraisals;
        uint sumAppraisalsModified;
        Exp sumAdditionalShortfall;
        Exp collateralFactor;
        Exp liquidationDiscount;
        uint priceMantissa;
        uint normalizedRepayAmount;
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cErc721TokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     * @param tokenIds The tokenIds to seize
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrowAllowedErc721(
        address cTokenBorrowed,
        address cErc721TokenCollateral,
        address borrower,
        uint repayAmount,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public view returns (uint) {

        LiquidateBorrowLocalVars memory vars;

        if (!comptroller.isMarketListed(cTokenBorrowed) || !comptroller.isMarketListed(cErc721TokenCollateral)) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        uint liquidationDiscountLocal = comptroller.getMarketLiquidationDiscount(cErc721TokenCollateral);
        if (liquidationDiscountLocal == 0) {
            return uint(Error.INVALID_LIQUIDATION_DISCOUNT);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (uint err, , uint shortfall) = getAccountLiquidity(borrower, appraisal);
        if (err != uint(Error.NO_ERROR)) {
            return uint(err);
        }

        if (shortfall == 0) {
            return uint(Error.INSUFFICIENT_SHORTFALL);
        }

        vars.priceMantissa = comptroller.getOracle().getUnderlyingPrice(CTokenInterface(cTokenBorrowed));
        if (vars.priceMantissa == 0) {
            return uint(Error.PRICE_ERROR);
        }
        uint8 underlyingDecimals = comptroller.getOracle().getUnderlyingDecimals(cTokenBorrowed);
        if (underlyingDecimals > 0 && underlyingDecimals < 18) {
            vars.priceMantissa = vars.priceMantissa / uint(10) ** (18 - underlyingDecimals);
        }
        // normalizedRepayAmount = repayAmount * underlyingPrice // exchangeRate is NOT involved
        vars.normalizedRepayAmount = mul_ScalarTruncate(Exp({mantissa: vars.priceMantissa}), repayAmount);

        // emulate getHypotheticalLiquidity to see impact of transferring
        // out collateral and transferring in repayAmount

        // no close factor for liquidating erc721 collateral, however we minimize excess
        // liquidation over the shortfall.
        // this is different than regular cToken liquidation, where the entire borrow
        // balance (multiplied by close factor) is open for liquidation.
        vars.collateralFactor = Exp({mantissa: comptroller.getCollateralFactorMantissa(address(cErc721TokenCollateral))});
        vars.liquidationDiscount = Exp({mantissa: liquidationDiscountLocal});
        for (uint i = 0; i < tokenIds.length; i++) {
            uint tokenId = tokenIds[i];

            if (CErc721Interface(cErc721TokenCollateral).tokenOwners(tokenId) != borrower) {
                return uint(Error.REJECTION);
            }

            uint appraisalValue = getAppraisal(appraisal, cErc721TokenCollateral, tokenId);
            // this situation isn't possible because the appraisal passed into getAccountLiquidity
            // must contain all owned tokenIds, otherwise it errors
            // if (appraisalValue == 0) {
            //     return uint(Error.PRICE_ERROR);
            // }
            Exp memory appraisalExp = Exp({mantissa: appraisalValue});
            vars.sumAppraisals = add_(appraisalExp, vars.sumAppraisals);
            vars.sumAppraisalsModified = truncate(mul_(vars.sumAppraisals, vars.liquidationDiscount));

            // increase shortfall because collateral is transferred out
            vars.sumAdditionalShortfall = add_(appraisalExp, vars.sumAdditionalShortfall);
            uint shortfallModified = add_(truncate(mul_(vars.sumAdditionalShortfall, vars.collateralFactor)), shortfall);

            // if there are still more tokens desired after exceeding shortfall, then fail.
            if (vars.sumAppraisalsModified > shortfallModified  && i != tokenIds.length - 1) {
                return uint(Error.TOO_MUCH_REPAY);
            }
        }

        if (vars.normalizedRepayAmount != vars.sumAppraisalsModified) {
            return uint(Error.INVALID_REPAY);
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
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = comptroller.getOracle().getUnderlyingPrice(CTokenInterface(cTokenBorrowed));
        uint priceCollateralMantissa = comptroller.getOracle().getUnderlyingPrice(CTokenInterface(cTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }
        
        uint liquidationIncentiveLocal = comptroller.getMarketLiquidationIncentive(cTokenCollateral);
        if (liquidationIncentiveLocal == 0) {
            return (uint(Error.INVALID_LIQUIDATION_INCENTIVE), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = CTokenInterface(cTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(Exp({mantissa: liquidationIncentiveLocal}), Exp({mantissa: priceBorrowedMantissa}));
        denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation for cErc20Collateral collateral
     * @param cTokenBorrowed The address of the borrowed cToken
     * @param cErc20CollateralToken The address of the collateral cErc20Collateral
     * @param repayAmount The amount of cTokenBorrowed underlying to convert into cErc20Collateral tokens
     * @return (errorCode, number of cErc20Collateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeCErc20Collateral(
        address cTokenBorrowed,
        address cErc20CollateralToken,
        uint repayAmount
    ) external view returns (uint, uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = comptroller.getOracle().getUnderlyingPrice(CTokenInterface(cTokenBorrowed));
        uint priceCollateralMantissa = comptroller.getOracle().getUnderlyingPrice(CTokenInterface(cErc20CollateralToken));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        uint liquidationIncentiveLocal = comptroller.getMarketLiquidationIncentive(cErc20CollateralToken);
        if (liquidationIncentiveLocal == 0) {
            return (uint(Error.INVALID_LIQUIDATION_INCENTIVE), 0);
        }

        uint seizeTokens;
        Exp memory numerator;
        Exp memory ratio;

        numerator = mul_(Exp({mantissa: liquidationIncentiveLocal}), Exp({mantissa: priceBorrowedMantissa}));
        ratio = div_(numerator, Exp({mantissa: priceCollateralMantissa}));

        seizeTokens = mul_ScalarTruncate(ratio, repayAmount);

        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /**
     * @notice Returns true if the given cToken market has been deprecated
     * @dev All borrows in a deprecated cToken market can be immediately liquidated
     * @param cToken The market to check if deprecated
     */
    function isDeprecated(CTokenInterface cToken) public view returns (bool) {
        return comptroller.getCollateralFactorMantissa(address(cToken)) == 0 &&
            comptroller.getBorrowGuardianPaused(address(cToken)) == true &&
            cToken.reserveFactorMantissa() == 1e18;
    }

    function _setComptroller(ComptrollerInterface newComptroller) external {
        require(msg.sender == admin);
        comptroller = newComptroller;
    }

    function _setAppraisalOracle(AppraisalOracleInterface newAppraisalOracle) external {
        require(msg.sender == admin);
        appraisalOracle = newAppraisalOracle;
    }

    /**
     * @notice Set the new admin of this contract
     * @param newAdmin new admin for this contract
     */
    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "only the admin may call this function.");
        require(newAdmin != address(0), "admin cannot be zero address");
        emit NewAdmin(newAdmin, admin);
        admin = newAdmin;
    }
}
