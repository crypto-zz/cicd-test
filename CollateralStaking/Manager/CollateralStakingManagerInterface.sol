pragma solidity ^0.5.16;

contract CollateralStakingManagerStorage {
    // struct for staking pool with underlying token
    struct MarketPoolWire {
        address stakingPool;
        address underlyingToken;
    }
    
    /// @notice Indicator that this is a CollateralStakingManager contract (for inspection)
    bool public constant isCollateralStakingManager = true;

    // implementaiton for proxy
    address public implementation;

    // implementation for all mediator contracts
    address public collateralStakingMediatorImplementation;

    /**
     * MetaLend admin
     */
    address public admin;
    address payable public royaltiesReceiver;
    // scale 0 <=> 10000, 1% = 100
    uint public rewardsRoyaltiesPercentage;

    // mapping from user address to own userCollateralMediator
    mapping(address => address) internal userCollateralMediator;

    // supported protocol CErcStaking markets
    mapping(address => bool) public cErcStakingMarket;

    // mapping from CErcStaking market address to stakingPool, underlyingToken
    mapping(address => MarketPoolWire) public marketPoolWire;
}

contract CollateralStakingManagerStorageUpgrade { 
    address public restakingPoolErc20;
    address public restakingUnderlying;
    uint256 public totalRestakingAmount;
    address public restakingManager;
    bool public moveUncollateralizedPaused;
    uint256 public totalAccruedRewards;
}

contract CollateralStakingManagerStorageUpgradeV2 { 
    address public roninStaking;
    address public roninValidatorSet;
    uint256 public totalDelegatingAmountRon;
    address public redelegatingManager;
    uint256 public totalAccruedRewardsRon;
    mapping(address => bool) public supportedValidators;
}

contract CollateralStakingManagerStorageUpgradeV3 {
    address public cEtherStakingMarket;
    address[] public supportedValidatorsList;
}

contract CollateralStakingManagerInterface is 
    CollateralStakingManagerStorage, 
    CollateralStakingManagerStorageUpgrade, 
    CollateralStakingManagerStorageUpgradeV2,
    CollateralStakingManagerStorageUpgradeV3 
{
    event NewCollateralStakingMediator(address indexed user);
    event NewStakingMarket(address indexed cErcStakingMarket, address stakingPool, address underlyingToken);
    event NewCollateralStakingMediatorImplementation(address previousImpl, address newImpl);
    event NewAdmin(address indexed newAdmin, address indexed previousAdmin);
    event NewRewardsRoyaltiesPercentage(uint256 indexed newPercentage, uint256 indexed previousPercentage);
    event NewRoyaltiesReceiver(address indexed newReceiver, address indexed previousReceiver);
    event NewRestakingManager(address indexed newRestakingManager, address indexed previousRestakingManager);
    event MoveCollateralPausedChanged(bool indexed newValue);
    event NewRestakingUnderlying(address indexed newRestakingUnderlying, address indexed previousRestakingUnderlying);
    event NewRestakingPool(address indexed newRestakingPool, address indexed previousRestakingPool);
    event NewRoninStaking(address indexed newRoninStaking, address indexed previousRoninStaking);
    event NewRoninValidatorSet(address indexed newRoninValidatorSet, address indexed previousRoninValidatorSet);
    event NewRedelegatingManager(address indexed newRedelegatingManager, address indexed previousRedelegatingManager);
    event ValidatorSupported(address indexed validator, bool indexed supported);
    event NewCEtherStakingMarket(address indexed newCEtherStakingMarket, address indexed previousCEtherStakingMarket);

    /**
     * public functions
     */
    function feeDenominator() public pure returns (uint256);
    function stakeInitialUncollateralizedErc20(uint256 amount) external;
    function delegateInitialUncollateralizedRon(address consensusAddr) external payable;
    function getSupportedValidatorsList() external view returns(address[] memory);

    /**
     * called only by Mediator contract
     */
    function decreaseTotalRestakingAmount(uint256 amount) external;
    function increaseTotalRestakingAmount(uint256 amount) external;
    function increaseTotalAccruedRewards(uint256 amount) external;
    function decreaseTotalDelegatingAmount(uint256 amount) external;
    function increaseTotalDelegatingAmount(uint256 amount) external;
    function increaseTotalAccruedRewardsRon(uint256 amount) external;
    
    /**
     * called only by CErcStaking contract
     */
    function getCollateralStakingMediator(address user) external view returns(address);
    function getOrCreateCollateralStakingMediator(address payable user) external returns(address);

    /**
     * called only by MetaLend admin
     */
    function supportCErcStakingMarket(
        address market, 
        address stakingPool, 
        address underlyingToken, 
        bool isErc721, 
        bool isErc20
    ) external;
    function setRewardRoyaltiesPercentage(uint256 newPercentage) external;
    function setAdmin(address newAdmin) external;
    function setRoyaltiesReceiver(address payable newReceiver) external;
    function setRestakingPoolErc20(address restakingPool) external;
    function setRestakingUnderlying(address underlying) external;
    function setCollateralStakingMediatorImplementation(address newImplementation) external;
    function setRestakingManager(address newManager) external;
    function setMoveUncollateralizedPaused(bool value) external;
    function setRoninStaking(address newRoninStaking) external;
    function setRoninValidatorSet(address newRoninValidatorSet) external;
    function setRedelegatingManager(address newRedelegatingManager) external;
    function supportValidators(address[] calldata validators) external;
    function supportCEtherStakingMarket(address newMarket) external;
}
