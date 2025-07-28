pragma solidity ^0.5.16;

import "../CToken/CTokenInterfaces.sol";

contract PriceOracleInterface {
    function getUnderlyingPrice(CTokenInterface cToken) external view returns (uint);
}

contract CustomPriceOracle is PriceOracleInterface {
    mapping(address => uint) public price;

    constructor() public {}

    function getUnderlyingPrice(CTokenInterface cToken) public view returns (uint) {
        cToken;
        return price[address(cToken)];
    }

    function assetPrices(address asset) public view returns (uint) {
        asset;
        return price[address(asset)];
    }

    function setPrice(CTokenInterface cToken, uint value) external {
      price[address(cToken)] = value;
    }
}