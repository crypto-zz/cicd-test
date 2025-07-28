pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./PriceOracle.sol";
import "../Interface/EIP20Interface.sol";

/**
 * Example Usage:
 *  Network: Ronin
 *  Katana Router: 0x7d0556d55ca1a92708681e2e231733ebd922597d
 *  
 *  AXS: 0x97a9107c1793bc407d6f527b77e7fff4d812bece
 *  WETH: 0xc99a6a985ed2cac1ef41640596c5a5f9f4e19ef5
 *  
 *  Decimals: 18
 *
 * Output: Price of 1 AXS (1e18) in WETH from corresponding Liquidity-Provider (0xc6344bc1604fcab1a5aad712d766796e2b7a70b9)
 */

interface KatanaRouter {

    function getAmountsOut(
        uint256 _amountIn, 
        address[] calldata path
    ) external view returns (uint256[] memory);
}

contract KatanaTWAPOracle is PriceOracle {
    event NewAdmin(address indexed newAdmin, address indexed previousAdmin);

    uint8 public constant baseDecimals = 18;
    address public owner;
    address public router;

    struct KatanaLP {
        address[] pricePair;
        uint8 inputDecimals;
    }

    mapping (address => KatanaLP) internal cTokenToKatanaLP;

    constructor (address _router) public {
        owner = msg.sender;
        router = _router;
    }

    function getUnderlyingPrice(CTokenInterface cToken) public view returns (uint256) {
        KatanaLP memory katanaLP = cTokenToKatanaLP[address(cToken)];

        if (katanaLP.pricePair.length != 2 || 
            katanaLP.pricePair[0] == address(0) || 
            katanaLP.pricePair[1] == address(0)) {
            return 0;
        }

        if (katanaLP.pricePair[0] == katanaLP.pricePair[1]) {
            return 1e18;
        }

        // Base is set to a single token of the input asset
        uint baseInput = uint(10) ** katanaLP.inputDecimals;

        uint256[] memory outputPrice = KatanaRouter(router).getAmountsOut(baseInput, katanaLP.pricePair);
        if (outputPrice.length != 2) {
            return 0;
        }
        return outputPrice[1] * uint(10) ** (baseDecimals - katanaLP.inputDecimals);
    }

    function getUnderlyingDecimals(address cToken) external view returns (uint8) {
        return cTokenToKatanaLP[cToken].inputDecimals;
    }

    function setKatanaPair(
        address cToken, 
        address input, 
        address output
    ) external {
        require(msg.sender == owner);

        uint8 inputDecimals = EIP20Interface(input).decimals();
        require(inputDecimals <= baseDecimals, "Incompatible input");

        // Writing directly to struct from state variable to avoid read-path allocation 
        address[] memory pricePair;
        pricePair = new address[](2);
        pricePair[0] = input;
        pricePair[1] = output;

        cTokenToKatanaLP[cToken] = KatanaLP(pricePair, inputDecimals);
    }

    /**
     * @notice Set the new admin of this contract
     * @param newAdmin new admin for this contract
     */
    function setAdmin(address newAdmin) external {
        require(msg.sender == owner, "only the admin may call this function.");
        require(newAdmin != address(0), "new admin cannot be zero address");
        emit NewAdmin(newAdmin, owner);
        owner = newAdmin;
    }
}

