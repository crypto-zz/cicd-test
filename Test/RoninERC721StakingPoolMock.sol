pragma solidity ^0.5.16;

import "../Interface/RoninStakingInterfaces.sol";
import "../Interface/EIP20Interface.sol";
import "../Interface/ERC721Interface.sol";
import "./RoninERC721StakingManagerMock.sol";

contract RoninERC721StakingPoolMock is StakingPool, Erc721StakingPool, IERC721Receiver {   
    address public manager;
    address public rewardToken;
    address public underlyingToken;

    mapping(address => uint256) public stakingCount;
    mapping(uint256 => address) public tokensPerUser;
    mapping(address => uint256[]) accountTokens;

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
        return RoninERC721StakingManagerMock(manager).getPendingRewards(_user);
    }

    function claimPendingRewards() external {
        RoninERC721StakingManagerMock stakingManager = RoninERC721StakingManagerMock(manager);
        require(stakingManager.canObtainRewards(address(this), msg.sender), "Cannot claim rewards");
        stakingManager.claimRewards(msg.sender);
    }
    
    function getRewardToken() external view returns(address){
        return rewardToken;
    }

    function paused() external view returns(bool) {
        return false;
    }

    function stake(uint256[] calldata _tokenIds) external {
        for(uint i = 0; i < _tokenIds.length; i++){
            tokensPerUser[_tokenIds[i]] = msg.sender;
            ERC721Interface(underlyingToken).safeTransferFrom(msg.sender, address(this), _tokenIds[i]);
            accountTokens[msg.sender].push(_tokenIds[i]);
        }
        stakingCount[msg.sender] += _tokenIds.length;
    }

    function unstake(uint256[] calldata _tokenIds) external {
        for(uint i = 0; i < _tokenIds.length; i++){
            tokensPerUser[_tokenIds[i]] = address(0);
            ERC721Interface(underlyingToken).safeTransferFrom(address(this), msg.sender, _tokenIds[i]);
        }
        removeFromAccountTokens(msg.sender, _tokenIds);
        stakingCount[msg.sender] -= _tokenIds.length;
    }

    function removeFromAccountTokens(
        address account,
        uint[] memory tokenIds
    ) internal {
        for (uint i = 0; i < tokenIds.length; i++) {
            uint tokenId = tokenIds[i];
            uint256[] memory accountTokenIds = accountTokens[account];
            uint len = accountTokenIds.length;
            uint tokenIdIndex = len;

            for (uint j = 0; j < len; j++) {
                if (tokenId == accountTokenIds[j]) {
                    tokenIdIndex = j;
                    break;
                }
            }

            require(tokenIdIndex < len, "tokenId not found");

            // copy last item in list to location of item to be removed, reduce length by 1
            uint256[] storage storedList = accountTokens[account];
            storedList[tokenIdIndex] = storedList[storedList.length - 1];
            storedList.length--;
        }
    }

    function getStakedLands(address _user) external view returns(uint256[] memory) {
        return accountTokens[_user];
    }

    function onERC721Received(
        address, 
        address, 
        uint256, 
        bytes calldata
    ) external returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}