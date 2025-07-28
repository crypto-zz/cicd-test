pragma solidity ^0.5.16;

import "../Oracle/PriceOracle.sol";
import "../CErc721/CErc721Interface.sol";
import "../LiquidityAssessor/LiquidityAssessorInterface.sol";
import "../Oracle/AppraisalOracleInterface.sol";
import "../Interface/CompComptrollerInterface.sol";
import "../CErc20/CErc20CollateralInterface.sol";
import "../Interface/CErc20BridgedInterface.sol";

contract UnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
    address public comptrollerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingComptrollerImplementation;
}

contract ComptrollerV1Storage is UnitrollerAdminStorage {

    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint public closeFactorMantissa;

    /**
     * @notice Multiplier representing the bonus on collateral that a liquidator receives
     */
    uint public liquidationIncentiveMantissa;

    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;

        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;
    }

    /**
     * @notice Official mapping of cTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;


    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;

    /// @notice A list of all markets
    CTokenInterface[] public allMarkets;

    // @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    // @notice Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint) public borrowCaps;

    /**
     * @notice Oracle which gives the price of any given ERC721 asset
     */
    AppraisalOracleInterface public appraisalOracle;

    /// @notice A list of all ERC721 markets
    CErc721Interface[] public allErc721Markets;

    CompComptrollerInterface public compComptroller;

    LiquidityAssessorInterface public liquidityAssessor;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint public liquidationDiscountMantissa;

    /// @notice A list of all ERC20Bridged markets
    /// @dev this is discontinued storage slot
    CErc20BridgedInterface[] public allErc20BridgedMarkets;

    /// @notice liquidation discount per market address
    mapping(address => uint) public liquidationDiscountMantissaPerMarket;

    /// @notice liquidation incentive per market address
    mapping(address => uint) public liquidationIncentiveMantissaPerMarket;

    /// @notice A list of all ERC20 collateral markets
    CErc20CollateralInterface[] public allErc20CollateralMarkets;
}
