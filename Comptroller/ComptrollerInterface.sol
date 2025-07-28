pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../Oracle/AppraisalStruct.sol";
import "../Oracle/PriceOracle.sol";
import "../CErc721/CErc721Interface.sol";
import "../CErc20/CErc20CollateralInterface.sol";

contract ComptrollerInterface {
    /*** Policy Hooks ***/
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    function mintAllowed(
        address cToken,
        address minter
    ) external returns (uint);

    function mintAllowedErc721(
        address cErc721Token
    ) external returns (uint);

    function mintAllowedErc20Collateral(
        address cErc20CollateralToken) 
        external returns (uint);

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint redeemTokens,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);

    function redeemAllowedErc721(
        address cErc721Token,
        address redeemer,
        uint256[] calldata tokenIds,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function redeemAllowedErc20Collateral(
        address cErc20CollateralToken,
        address redeemer,
        uint redeemTokens,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function redeemVerify(
        uint redeemAmount,
        uint redeemTokens
    ) external;

    function borrowAllowed(
        address cToken,
        address borrower,
        uint borrowAmount,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external returns (uint);

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint repayAmount,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function liquidateBorrowAllowedErc721(
        address cTokenBorrowed,
        address cErc721TokenCollateral,
        address borrower,
        uint repayAmount,
        uint256[] calldata tokenIds,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint);

    function seizeAllowedErc721(
        address cErc721TokenCollateral,
        address cTokenBorrowed
    ) external returns (uint);

    function seizeAllowedErc20Collateral(
        address cErc20CollateralToken,
        address cTokenBorrowed
    ) external returns (uint);

    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint transferTokens,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint repayAmount
    ) external view returns (uint, uint);

    function liquidateCalculateSeizeCErc20Collateral(
        address cTokenBorrowed,
        address cErc20CollateralToken,
        uint repayAmount
    ) external view returns (uint, uint);


    function getCollateralFactorMantissa(address asset) external view returns (uint);

    function getCloseFactorMantissa() external view returns (uint);

    function getMarketLiquidationDiscount(address market) external view returns (uint);

    function getMarketLiquidationIncentive(address market) external view returns (uint);

    function getBorrowGuardianPaused(address cToken) external view returns (bool);

    function getAllMarkets() external view returns (CTokenInterface[] memory);

    function getAllErc721Markets() external view returns (CErc721Interface[] memory);

    function getAllErc20CollateralMarkets() external view returns (CErc20CollateralInterface[] memory);

    function getOracle() external view returns (PriceOracle);

    function isMarketListed(address cToken) external view returns (bool);
}
