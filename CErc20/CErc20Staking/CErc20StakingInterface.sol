pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Comptroller/ComptrollerInterface.sol";
import "../../CollateralStaking/Manager/CollateralStakingManagerInterface.sol";

contract CErc20StakingStorage {
    /// @notice Indicator that this is a CErc20Staking contract (for inspection)
    bool public constant isCErc20Staking = true;

    /**
     * @notice Implementation address for this contract
     */
    address public implementation;

    address payable public admin;
    /**
     * @notice Underlying asset for this CToken
     */
    address public underlying;

    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice Contract which oversees inter-cToken operations
     */
    ComptrollerInterface public comptroller;

    /**
     * @notice Official record of token balances for each account
     */
    mapping (address => uint) internal accountTokens;

    CollateralStakingManagerInterface public collateralStakingManagerInterface;

    uint public globalCollateralLimit;
    uint public currentCollateralAmount;
}

contract CErc20StakingInterface is CErc20StakingStorage {
    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint mintTokens);

    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * @notice Event emitted when comptroller is changed
     */
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemTokens);

    event NewAdmin(address indexed newAdmin, address indexed previousAdmin);
    
    event NewCollateralStakingManager(address indexed newCollateralStakingManager, address indexed previousCollateralStakingManager);

    event NewGlobalCollateralLimit(uint256 indexed newLimit, uint256 indexed previousLimit);

    function mint(
        uint mintAmount
    ) external returns (uint);

    function redeem(
        uint redeemTokens,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function seizeAndRedeem(
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint);

    function moveUncollateralizedToProtocol(
        uint256 mintAmount
    ) external returns (uint256);
}
