pragma solidity ^0.5.16;

import "./CollateralStakingMediatorInterface.sol";

/**
 * @title MetaLend's CollateralStakingMediatorProxy Contract
 * @notice Proxies to CollateralStakingMediator implementation
 * @author MetaLend
 */
contract CollateralStakingMediatorProxy is CollateralStakingMediatorStorage {
    /**
     * @notice Construct the mediator contract
     * @param collateralStakingManager_ the shared staking manager contract (creator of this contract)
     * @param owner_ The owner of the mediator contract (user with collateral in protocol)
     * @param implementation_ The implementation of mediator contract stored in staking manager
     */
    constructor(
        address collateralStakingManager_,
        address payable owner_,
        address implementation_
    ) public {
        delegateTo(implementation_, abi.encodeWithSignature("initialize(address,address)",
            collateralStakingManager_,
            owner_
        ));
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
        // delegate all other functions to current implementation got from CollateralStakingManager
        address implementation = collateralStakingManager.collateralStakingMediatorImplementation();
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
