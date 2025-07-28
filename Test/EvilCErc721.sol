pragma solidity ^0.5.16;

import "../CollateralStaking/Manager/CollateralStakingManagerInterface.sol";

contract EvilCErc721 {
    CollateralStakingManagerInterface manager;

    constructor(address manager_) public {
        manager = CollateralStakingManagerInterface(manager_);
    }

    function create() external {
        manager.getOrCreateCollateralStakingMediator(msg.sender);
    }
}
