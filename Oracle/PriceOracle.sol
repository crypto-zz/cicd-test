pragma solidity ^0.5.16;

import "../CToken/CTokenInterfaces.sol";

contract PriceOracle {
    /**
      * @notice Get the underlying price of a cToken asset
      * @param cToken The cToken to get the underlying price of
      * @return The underlying asset price mantissa (scaled by 1e18).
      *  Zero means the price is unavailable.
      */
    function getUnderlyingPrice(CTokenInterface cToken) external view returns (uint);

    /**
      * @notice Get the decimals of an underlying asset of cToken
      * @param cToken The address of the cToken to get underlying asset decimals of
      * @return The decimals of the underlying asset of cToken
      */
    function getUnderlyingDecimals(address cToken) external view returns (uint8);
}
