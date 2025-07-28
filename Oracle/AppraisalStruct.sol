pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

/**
 * @notice Appraisal created off-chain
 * appraisalTokens: list of CErc721 token addresses
 * appraisalLengths: list of count of tokenIds per CErc721 token
 * appraisalTokenIds: list of tokenIds across the CErc721 tokens
 * appraisalGoodUntil: the block number when this appraisal expires
 * signature: the signature created by the off-chain appraiser
 */
library AppraisalStruct {
    struct Wire {
        address[] appraisalTokens;
        uint[] appraisalLengths;
        uint[] appraisalTokenIds;
        uint[] appraisalValues;
        uint appraisalGoodUntil;
        bytes signature;
    }
}