pragma solidity ^0.5.16;

import "../Interface/RoninStakingInterfaces.sol";
import "./RoninERC20StakingPoolMock.sol";
import "../Lib/SafeErc20/SafeErc20.sol";

contract RoninERC20StakingManagerMock is StakingManager {
    uint256 public constant reward = 1;
    uint256 public constant blocksPerDay = 28800;

    mapping(address => mapping(address => uint256)) public lastBlockClaimed;


    function canObtainRewards(address _pool, address _user) external view returns(bool){
        if(lastBlockClaimed[_pool][_user] == 0){
            return true;
        }
        uint256 currentBlock = block.number;
        if(currentBlock > lastBlockClaimed[_pool][_user] + blocksPerDay){
            return true;
        } else {
            return false;
        }
    }

    function unlockObtain(address _pool, address _user) external {
        lastBlockClaimed[_pool][_user] = 0;
    }

    function getPendingRewards(address _user) external view returns(uint256) {
        return RoninERC20StakingPoolMock(msg.sender).stakingCount(_user) * reward;
    }

    function claimRewards(address _user) external {
        uint256 tokenAmount = RoninERC20StakingPoolMock(msg.sender).stakingCount(_user);
        address rewardToken = RoninERC20StakingPoolMock(msg.sender).getRewardToken();
        uint256 rewardAmount = tokenAmount * reward;
        SafeErc20.safeTransfer(rewardToken, _user, rewardAmount);
        lastBlockClaimed[msg.sender][_user] = block.number;
    }
}