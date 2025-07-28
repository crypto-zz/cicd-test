pragma solidity ^0.5.16;

/**
 * @title MetaLend's CErc20 Collateral Contract
 * @dev cerc20 markets which are used only as a collateral (no borrowing/lending functionality)
 * @author MetaLend
 */
contract CErc20CollateralInterface {
    function getAccountTokens(address account) external view returns (uint);
    function newFunc(address a) external view returns (uint);
}
