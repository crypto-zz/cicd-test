pragma solidity ^0.5.16;

import "./CollateralStakingManagerInterface.sol";

/**
 * @title MetaLend's CollateralStakingManagerProxy Contract
 * @notice Proxies to CollateralStakingManager implementation
 * @author MetaLend
 */
contract CollateralStakingManagerProxy is CollateralStakingManagerStorage {
    /**
     * @notice Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Construct a new staking manager
     * @param royaltiesReceiver_ of the royalties receiver from rewards
     * @param collateralStakingMediatorImplementation_ of the staking mediator implementation for proxies
     * @param rewardsRoyaltiesPercentage_ The amount for percentage cut from staking rewards
     * @param admin_ Address of the administrator of this manager
     * @param implementation_ The address of the implementation the contract delegates to
     */
    constructor(
        address payable royaltiesReceiver_,
        address collateralStakingMediatorImplementation_,
        uint rewardsRoyaltiesPercentage_,
        address admin_,
        address implementation_
    ) public {
        // Creator of the contract is admin during initialization
        admin = msg.sender;

        // First delegate gets to initialize the delegator (i.e. storage contract)
        delegateTo(implementation_, abi.encodeWithSignature("initialize(address,address,uint256)",
            royaltiesReceiver_,
            collateralStakingMediatorImplementation_,
            rewardsRoyaltiesPercentage_));

        // New implementations always get set via the setter (post-initialize)
        _setImplementation(implementation_);

        require(admin_ != address(0), "admin cannot be zero address");
        // Set the proper admin now that initialization is done
        admin = admin_;
    }

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     */
    function _setImplementation(address implementation_) public {
        require(msg.sender == admin, "CollateralStakingManagerProxy::_setImplementation: Caller must be admin");
        require(implementation_ != address(0), "implementation contract cannot be zero address");

        address oldImplementation = implementation;
        implementation = implementation_;

        emit NewImplementation(oldImplementation, implementation);
    }

    /**
     * @notice Internal method to delegate execution to another contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param callee The contract to delegatecall
     * @param data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
     */
    function delegateTo(address callee, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = callee.delegatecall(data);
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize)
            }
        }
        return returnData;
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller whatever the implementation returns
     * or forwards reverts.
     */
    function() payable external {
        // delegate all other functions to current implementation
        (bool success,) = implementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize)

            switch success
            case 0 {revert(free_mem_ptr, returndatasize)}
            default {return (free_mem_ptr, returndatasize)}
        }
    }
}
