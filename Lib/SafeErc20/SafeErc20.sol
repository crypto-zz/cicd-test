pragma solidity ^0.5.16;

import "../../Interface/EIP20NonStandardInterface.sol";
import "../../Interface/EIP20Interface.sol";

/**
 * @title SafeErc20 library
 * @notice Provides safeTransfer and safeTransferFrom functions for ERC20
 * @author MetaLend
 */
library SafeErc20 {
    function safeTransfer(address tokenContract, address to, uint256 value) internal {
        EIP20NonStandardInterface(tokenContract).transfer(to, value);
            
        bool success;
        assembly {
            switch returndatasize()
                case 0 {                       // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                      // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                      // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_FAILED");
    }

    function safeTransferFrom(address tokenContract, address from, address to, uint256 value) internal {
        EIP20NonStandardInterface(tokenContract).transferFrom(from, to, value);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {                       // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                      // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                      // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_IN_FAILED");
    }
}