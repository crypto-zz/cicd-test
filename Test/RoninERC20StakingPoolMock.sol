pragma solidity ^0.5.16;

import "../Interface/RoninStakingInterfaces.sol";
import "../Interface/EIP20Interface.sol";
import "./RoninERC20StakingManagerMock.sol";
import "../Lib/SafeErc20/SafeErc20.sol";

contract RoninERC20StakingPoolMock is StakingPool, Erc20StakingPool {
    address public manager;
    address public rewardToken;
    address public underlyingToken;

    mapping(address => uint256) public stakingCount;
    mapping(uint256 => address) public tokensPerUser;

    constructor(
        address manager_,
        address rewardToken_,
        address underlyingToken_
    ) public {
        manager = manager_;
        rewardToken = rewardToken_;
        underlyingToken = underlyingToken_;
    }
    
    function getPendingRewards(address _user) external view returns(uint256) {
        return RoninERC20StakingManagerMock(manager).getPendingRewards(_user);
    }

    function claimPendingRewards() external {
        RoninERC20StakingManagerMock stakingManager = RoninERC20StakingManagerMock(manager);
        require(stakingManager.canObtainRewards(address(this), msg.sender), "Cannot claim rewards");
        stakingManager.claimRewards(msg.sender);
    }
    
    function getRewardToken() external view returns(address){
        return rewardToken;
    }

    function paused(bytes4 _method) external view returns(bool) {
        return false;
    }

    function stake(uint256 amount) external {
        SafeErc20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        stakingCount[msg.sender] += amount;
    }

    function unstake(uint256 amount) external {
        SafeErc20.safeTransfer(underlyingToken, msg.sender, amount);
        stakingCount[msg.sender] -= amount;
    }

    function getStakingAmount(address _user) external view returns(uint256) {
        return stakingCount[_user];
    }
}