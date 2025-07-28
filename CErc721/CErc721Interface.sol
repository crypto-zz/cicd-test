pragma solidity ^0.5.16;

/**
 * @title MetaLend's CErc721 Contract
 * @author MetaLend
 */
contract CErc721Interface {
    function getAccountTokens(address account) external view returns (uint256[] memory);

    function tokenOwners(uint tokenId) external view returns (address);
}