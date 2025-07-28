pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../Lib/Error/ErrorReporter.sol";
import "../Oracle/AppraisalStruct.sol";
import "../CToken/CTokenInterfaces.sol";

contract LiquidityAssessorInterface is ComptrollerErrorReporter {
    function getAccountLiquidity(
        address account,
        AppraisalStruct.Wire memory appraisal
    ) public view returns (uint, uint, uint);

    function getTotalBorrows(
        address account
    ) external view returns (uint);

    function getHypotheticalAccountLiquidity(
        address account,
        CTokenInterface cTokenModify,
        CErc20CollateralInterface cErc20CollateralTokenModify,
        uint redeemTokens,
        uint borrowAmount,
        CErc721Interface cErc721TokenModify,
        uint256[] memory redeemErc721TokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public view returns (Error, uint, uint);

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint repayAmount,
        AppraisalStruct.Wire memory appraisal
    ) public view returns (uint);

    function liquidateBorrowAllowedErc721(
        address cTokenBorrowed,
        address cErc721TokenCollateral,
        address borrower,
        uint repayAmount,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public view returns (uint);

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint actualRepayAmount
    ) external view returns (uint, uint);

    function liquidateCalculateSeizeCErc20Collateral(
        address cTokenBorrowed,
        address cErc20CollateralToken,
        uint repayAmount
    ) external view returns (uint, uint);
}
