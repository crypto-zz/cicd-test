pragma solidity ^0.5.16;

import "../Manager/CollateralStakingManagerInterface.sol";
import "../../CErc721/CErc721Staking/CErc721StakingInterface.sol";

contract CollateralStakingMediatorStorage {
    /// @notice Indicator that this is a CollateralStakingMediator contract (for inspection)
    bool public constant isCollateralStakingMediator = true;

    // manager which holds all data for CollateralStakingMediator that is shared among all mediator contracts
    CollateralStakingManagerInterface public collateralStakingManager;
    
    // the owner (user) of the mediator, each mediating contact belongs to EOA
    address payable internal owner;

    // during creation the proxy is initialized only once
    bool internal initialized;
}

contract CollateralStakingMediatorStorageUpgrade {
    uint256 public uncollateralizedStakingAmount;
    // mapping pool to uint256 rewards
    mapping(address => uint256) public accruedRewards;
}

contract CollateralStakingMediatorStorageUpgradeV2 {
    // discontinued storage slot
    uint256 public uncollateralizedDelegatingAmountRon;
    uint256 public accruedRewardsRon;
    bool internal _entered;
    // mapping pool to cooldown block
    mapping(address => uint256) public poolToUndelegateCooldown;
    // discontinued storage slot
    mapping(address => uint256) public uncollateralizedDelegatingAmountPerValidator;
}

contract CollateralStakingMediatorStorageUpgradeV3 {
    // discontinued storage slot
    mapping (address => uint256) public collateralizedDelegatingAmountPerValidator;
    
    address[] public activeCollateralizedValidators;
    // true - validator used for collateral
    mapping (address => bool) public validatorUsedForCollateral;
    mapping (address => address) public validatorToRestakingTarget;
}

contract CollateralStakingMediatorInterface is 
    CollateralStakingMediatorStorage, 
    CollateralStakingMediatorStorageUpgrade, 
    CollateralStakingMediatorStorageUpgradeV2, 
    CollateralStakingMediatorStorageUpgradeV3 
{
    /**
     * called only by CErcStaking contract
     */
    function stakeErc721(uint256[] calldata tokenIds) external;
    function stakeErc20(uint256 amount) external;
    function unstakeErc721(uint256[] calldata tokenIds, address receiver) external;
    function unstakeErc20(uint256 amount, address receiver) external;
    function moveUncollateralizedErc20ToProtocol(uint256 amount) external;
    
    /**
     * called only by owner of mediator contract
     */
    function claimPendingRewards(address stakingPool, address stakingManager) external;
    function unstakeUncollateralizedErc20(uint256 amount) external;
    function stakeUncollateralizedErc20(uint256 amount) external;
    function claimRewardsRon(address[] calldata consensusAddrList) external;
    function undelegateUncollateralizedRon(address[] calldata consensusAddrList, uint256[] calldata amounts) external;
    function delegateUncollateralizedRon(address consensusAddr) external payable;
    function setValidatorTargetsForRestaking(address consensusAddrSrc, address consensusAddrDst) external;

    /**
     * called only by CEtherStaking contract
     */
    function moveUncollateralizedRonToProtocol(address consensusAddr, address consensusAddrTarget) external;
    function redeemCollateralizedRon(address[] calldata consensusAddrList, uint[] calldata redeemTokens, address payable to) external;
    function delegateCollateralizedRon(address consensusAddr, address consensusAddrTarget) external payable;

    /**
     * called only by restaking manager
     */
    function restakePendingRewards(address stakingPool, address stakingManager) external;
    function redelegateRewards(address[] calldata consensusAddrList) external;

    /**
     * public
     */
    function getPendingRewards(address stakingPool) external view returns(uint256);
    function canClaimRewards(address stakingManager, address stakingPool) external view returns(bool);
    function getOwner() external view returns(address);
    function getActiveCollateralizedValidators() external view returns(address[] memory);
}
