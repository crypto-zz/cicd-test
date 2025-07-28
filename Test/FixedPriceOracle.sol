pragma solidity ^0.5.16;

import "../CToken/CTokenInterfaces.sol";

contract PriceOracleInterface {
    function getUnderlyingPrice(CTokenInterface cToken) external view returns (uint);
}

contract FixedPriceOracle is PriceOracleInterface {
    uint public price;

    constructor(uint _price) public {
        price = _price;
    }

    function getUnderlyingPrice(CTokenInterface cToken) public view returns (uint) {
        cToken;
        return price;
    }

    function assetPrices(address asset) public view returns (uint) {
        asset;
        return price;
    }
}