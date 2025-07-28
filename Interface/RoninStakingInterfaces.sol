pragma solidity ^0.5.16;

// eg. StakingManager, LandStakingManager
interface StakingManager {
    function canObtainRewards(address _pool, address _user) external view returns(bool);
}

// common functions shared between Erc721 and Erc20 staking pools
interface StakingPool {
    function getPendingRewards(address _user) external view returns(uint256);
    function claimPendingRewards() external;
    function getRewardToken() external view returns(address);
}

// eg. LandStakingPool
interface Erc721StakingPool {
    function stake(uint256[] calldata _tokenIds) external;
    function unstake(uint256[] calldata _tokenIds) external;
    function getStakedLands(address _user) external view returns(uint256[] memory);
    function paused() external view returns(bool);
}

// eg. AxsStakingPool
interface Erc20StakingPool { 
    function stake(uint256 _amount) external;
    function unstake(uint256 _amount) external;
    function getStakingAmount(address _user) external view returns(uint256);
    function paused(bytes4 _method) external view returns(bool);
}

interface RoninStaking {
    function claimRewards(address[] calldata _consensusAddrList) external;
    function delegate(address _consensusAddr) external payable;
    function undelegate(address _consensusAddr, uint256 _amount) external;
    function bulkUndelegate(address[] calldata _consensusAddrs, uint256[] calldata _amounts) external;
    function redelegate(address _consensusAddrSrc, address _consensusAddrDst, uint256 _amount) external;
    function getStakingAmount(address _poolAddr, address _user) external view returns(uint256);
    function cooldownSecsToUndelegate() external view returns(uint256);
    function getRewards(address _user, address[] calldata _poolAddrList) external view returns (uint256[] memory _rewards);
}

interface RoninValidatorSet {
    function isValidatorCandidate(address _candidate) external view returns(bool);
}