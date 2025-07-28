pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Oracle/AppraisalStruct.sol";
import "../../Comptroller/ComptrollerInterface.sol";
import "../../Oracle/AppraisalOracleInterface.sol";
import "../../CollateralStaking/Manager/CollateralStakingManagerInterface.sol";

contract CErc721StakingStorage {
    /// @notice Indicator that this is a CErc721Staking contract (for inspection)
    bool public constant isCErc721Staking = true;

    /**
     * @notice Implementation address for this contract
     */
    address public implementation;

    address payable public admin;

    string public name;

    string public symbol;

    ComptrollerInterface public comptroller;

    mapping(address => uint256[]) public accountTokens;

    mapping(uint256 => address) public tokenOwners;

    address public underlying;

    CollateralStakingManagerInterface public collateralStakingManagerInterface;
}

contract CErc721StakingInterface is CErc721StakingStorage {
    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint256[] tokenIds);

    /**
     * @notice Event emitted when comptroller is changed
     */
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint256[] tokenIds);

    event NewAdmin(address indexed newAdmin, address indexed previousAdmin);
    
    event NewCollateralStakingManager(address indexed newCollateralStakingManager, address indexed previousCollateralStakingManager);

    function mint(
        uint256[] calldata tokenIds
    ) external returns (uint);

    function redeem(
        uint256[] calldata tokenIds,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function seizeAndRedeem(
        address liquidator,
        address borrower,
        uint256[] calldata tokenIds
    ) external returns (uint);
}
