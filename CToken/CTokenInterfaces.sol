pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../Comptroller/ComptrollerInterface.sol";
import "../InterestRateModel/InterestRateModel.sol";
import "../Interface/EIP20NonStandardInterface.sol";
import "../CErc721/CErc721Interface.sol";
import "../Oracle/AppraisalStruct.sol";
import "../Oracle/AppraisalOracleInterface.sol";
import "../CErc20/CErc20CollateralInterface.sol";

contract CTokenStorage {
    /**
     * @dev Guard variable for re-entrancy checks
     */
    bool internal _notEntered;

    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public decimals;

    /**
     * @notice Maximum borrow rate that can ever be applied (.0005% / block)
     */

    uint internal constant borrowRateMaxMantissa = 0.0005e16;

    /**
     * @notice Maximum fraction of interest that can be set aside for reserves
     */
    uint internal constant reserveFactorMaxMantissa = 1e18;

    /**
     * @notice Administrator for this contract
     */
    address payable public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address payable public pendingAdmin;

    /**
     * @notice Contract which oversees inter-cToken operations
     */
    ComptrollerInterface public comptroller;

    /**
     * @notice Model which tells what the current interest rate should be
     */
    InterestRateModel public interestRateModel;

    /**
     * @notice Initial exchange rate used when minting the first CTokens (used when totalSupply = 0)
     */
    uint internal initialExchangeRateMantissa;

    /**
     * @notice Fraction of interest currently set aside for reserves
     */
    uint public reserveFactorMantissa;

    /**
     * @notice Block number that interest was last accrued at
     */
    uint public accrualBlockNumber;

    /**
     * @notice Accumulator of the total earned interest rate since the opening of the market
     */
    uint public borrowIndex;

    /**
     * @notice Total amount of outstanding borrows of the underlying in this market
     */
    uint public totalBorrows;

    /**
     * @notice Total amount of reserves of the underlying held in this market
     */
    uint public totalReserves;

    /**
     * @notice Total number of tokens in circulation
     */
    uint public totalSupply;

    /**
     * @notice Official record of token balances for each account
     */
    mapping (address => uint) internal accountTokens;

    /**
     * @notice Approved token transfer amounts on behalf of others
     */
    mapping (address => mapping (address => uint)) internal transferAllowances;

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }

    /**
     * @notice Mapping of account addresses to outstanding borrow balances
     */
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /**
     * @notice Share of seized collateral that is added to reserves
     */
    uint public constant protocolSeizeShareMantissa = 2.8e16; //2.8%
}

contract CTokenStorageUpgradeV1 {
    /**
     * @notice partnership admin address for claiming partnership reserves which are 5% from total reserves
     */
    address payable public partnershipAdmin;
    uint public partnershipReserves;
    uint internal constant partnershipPercentage = 5e16; //5%
}

contract CTokenStorageUpgradeV2 {
    uint public underlyingBalance;
    // discontinued storage slot
    bool internal underlyingBalanceSetRetrospectively;
}

contract CTokenInterface is CTokenStorage {
    /*** Market Events ***/

    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is liquidated - ERC721
     */
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address cErc721TokenCollateral, uint256[] tokenIds);

    /**
     * @notice Event emitted when a borrow is liquidated - ERC20 | cToken
     */
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address cErc20CollateralToken, uint256 seizeTokens);


    /*** Admin Events ***/

    /**
     * @notice Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @notice Event emitted when comptroller is changed
     */
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when interestRateModel is changed
     */
    event NewMarketInterestRateModel(InterestRateModel oldInterestRateModel, InterestRateModel newInterestRateModel);

    /**
     * @notice Event emitted when the reserve factor is changed
     */
    event NewReserveFactor(uint oldReserveFactorMantissa, uint newReserveFactorMantissa);

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint addAmount, uint newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced
     */
    event ReservesReduced(address admin, uint reduceAmount, uint newTotalReserves);

    /**
     * @notice Event emitted when partnership admin claims partnership reserves
     */
    event PartnershipReservesClaimed(address partnershipAdmin, uint claimedAmount);

    /**
     * @notice EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * @notice EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);

    /**
     * @notice Failure event
     */
    event Failure(uint error, uint info, uint detail);


    /*** User Interface ***/
    function balanceOf(address owner) external view returns (uint);
    function balanceOfUnderlying(address owner) external returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) public view returns (uint);
    function exchangeRateCurrent() public returns (uint);
    function exchangeRateStored() public view returns (uint);
    function getCash() external view returns (uint);
    function accrueInterest() public returns (uint);
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);

    /*** Admin Functions ***/

    function _setPendingAdmin(address payable newPendingAdmin) external returns (uint);
    function _acceptAdmin() external returns (uint);
    function _setComptroller(ComptrollerInterface newComptroller) public returns (uint);
    function _setReserveFactor(uint newReserveFactorMantissa) external returns (uint);
    function _reduceReserves(uint reduceAmount) external returns (uint);
    function _setInterestRateModel(InterestRateModel newInterestRateModel) public returns (uint);

    /*** Partnership Admin Functions ***/
    function _claimPartnershipReserves() external returns (uint);
    function _setPartnershipAdmin(address payable newAdmin) external;
}

contract CErc20Storage {
    /**
     * @notice Underlying asset for this CToken
     */
    address public underlying;
}

contract CErc20Interface {

    /*** User Interface ***/

    function mint(uint mintAmount) external returns (uint);
    function redeem(
        uint redeemTokens,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function redeemUnderlying(
        uint redeemAmount,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function borrow(
        uint borrowAmount,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(
        address borrower,
        uint repayAmount,
        CTokenInterface cTokenCollateral,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function liquidateBorrowAndRedeemErc721Mainchain(
        address borrower,
        uint repayAmount,
        CErc721Interface cErc721TokenCollateral,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function liquidateBorrowAndRedeemErc721Staking(
        address borrower,
        uint repayAmount,
        CErc721Interface cErc721TokenCollateral,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function liquidateBorrowAndRedeemErc20CollateralStaking(
        address borrower,
        uint repayAmount,
        CErc20CollateralInterface cErc20CollateralToken,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function sweepToken(EIP20NonStandardInterface token) external;


    /*** Admin Functions ***/

    function _addReserves(uint addAmount) external returns (uint);
}

contract CEtherInterface {

    /*** User Interface ***/

    function mint() external payable;
    function redeem(
        uint redeemTokens,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function redeemUnderlying(
        uint redeemAmount,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function borrow(
        uint borrowAmount,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint);
    function repayBorrow() external payable;
    function repayBorrowBehalf(address borrower) external payable;
    function liquidateBorrow(
        address borrower,
        CTokenInterface cTokenCollateral,
        AppraisalStruct.Wire memory appraisal
    ) public payable;
    function liquidateBorrowAndRedeemErc721Mainchain(
        address borrower,
        CErc721Interface cErc721TokenCollateral,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public payable;
    function liquidateBorrowAndRedeemErc721Staking(
        address borrower,
        CErc721Interface cErc721TokenCollateral,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public payable;
    function liquidateBorrowAndRedeemErc20CollateralStaking(
        address borrower,
        CErc20CollateralInterface cErc20CollateralToken,
        AppraisalStruct.Wire memory appraisal
    ) public payable;
    function sweepToken(EIP20NonStandardInterface token) external;


    /*** Admin Functions ***/

    function _addReserves() external payable returns (uint);
}

contract CDelegationStorage {
    /**
     * @notice Implementation address for this contract
     */
    address public implementation;
}

contract CProxyInterface is CDelegationStorage {
    /**
     * @notice Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     */
    function _setImplementation(address implementation_) public;
}
