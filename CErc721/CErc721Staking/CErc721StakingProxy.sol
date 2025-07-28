pragma solidity ^0.5.16;

import "./CErc721StakingInterface.sol";
pragma experimental ABIEncoderV2;

/**
 * @title MetaLend's CErc721StakingProxy Contract
 * @notice Proxies to CErc721Staking implementation
 * @author MetaLend
 */
contract CErc721StakingProxy is CErc721StakingStorage {
    /**
     * @notice Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Construct a new market
     * @param comptroller_ The address of the Comptroller
     * @param underlying_ The address of the Appraisal Oracle
     * @param name_ ERC-721 name of this token
     * @param symbol_ ERC-721 symbol of this token
     * @param collateralStakingManagerInterface_ the protocol staking manager interface which handles mediator contracts and supported markets
     * @param admin_ Address of the administrator of this token
     * @param implementation_ The address of the implementation the contract delegates to
     */
    constructor(
        ComptrollerInterface comptroller_,
        address underlying_,
        string memory name_,
        string memory symbol_,
        CollateralStakingManagerInterface collateralStakingManagerInterface_,
        address payable admin_,
        address implementation_
        //CollateralStakingManagerInterface
    ) public {
        // Creator of the contract is admin during initialization
        admin = msg.sender;

        // First delegate gets to initialize the delegator (i.e. storage contract)
        delegateTo(implementation_, abi.encodeWithSignature("initialize(address,address,string,string,address)",
            comptroller_,
            underlying_,
            name_,
            symbol_,
            collateralStakingManagerInterface_));

        // New implementations always get set via the setter (post-initialize)
        _setImplementation(implementation_);

        require(admin_ != address(0), "new admin cannot be zero address");
        // Set the proper admin now that initialization is done
        admin = admin_;
    }

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     */
    function _setImplementation(address implementation_) public {
        require(msg.sender == admin, "CErc721StakingProxy::_setImplementation: Caller must be admin");
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
