pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Comptroller/ComptrollerInterface.sol";
import "../../CollateralStaking/Manager/CollateralStakingManagerInterface.sol";

contract CEtherStakingStorage {
    /// @notice Indicator that this is a CEtherStaking contract (for inspection)
    bool public constant isCEtherStaking = true;

    /**
     * @notice Implementation address for this contract
     */
    address public implementation;

    address payable public admin;

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

    CollateralStakingManagerInterface public collateralStakingManagerInterface;

    uint public globalCollateralLimit;
    uint public currentCollateralAmount;
}

contract CEtherStakingInterface is CEtherStakingStorage {
    /**
     * @notice Event emitted when tokens are minted (transferred into the protocol)
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
        address consensusAddr,
        address consensusAddrTarget
    ) external payable returns(uint);

    function moveToProtocol(
        address consensusAddr,
        address consensusAddrTarget
    ) external returns (uint);

    function redeem(
        address consensusAddr,
        uint redeemTokens,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function seizeAndRedeem(
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint);
}
