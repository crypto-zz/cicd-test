pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Comptroller/ComptrollerInterface.sol";
import "./CEtherStakingInterface.sol";

contract CEtherStakingProxy is CEtherStakingStorage {
    /**
     * @notice Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Initialize the new money market
     * @param comptroller_ The address of the Comptroller
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param admin_ Address of the administrator of this token
     * @param collateralStakingManagerInterface_ the protocol staking manager interface which handles mediator contracts and supported markets
     * @param implementation_ The address of the implementation the contract delegates to
     */
    constructor(ComptrollerInterface comptroller_,
                string memory name_,
                string memory symbol_,
                address payable admin_,
                CollateralStakingManagerInterface collateralStakingManagerInterface_,
                address implementation_) public {
        // Creator of the contract is admin during initialization
        admin = msg.sender;

        // First delegate gets to initialize the delegator (i.e. storage contract)
        delegateTo(implementation_, abi.encodeWithSignature("initialize(address,string,string,address)",
            comptroller_,
            name_,
            symbol_,
            collateralStakingManagerInterface_));

        // New implementations always get set via the setter (post-initialize)
        _setImplementation(implementation_);

        // Set the proper admin now that initialization is done
        require(admin_ != address(0), "admin cannot be zero address");
        admin = admin_;
    }

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     */
    function _setImplementation(address implementation_) public {
        require(msg.sender == admin, "CEtherStakingProxy::_setImplementation: Caller must be admin");
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