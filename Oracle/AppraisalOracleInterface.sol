pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./AppraisalStruct.sol";

contract AppraisalOracleInterface {
    function _isAppraiser(address _address) public view returns (bool);

    function _setAppraiser(address _newAppraiser) external;

    function verifySignature(
        bytes32 hash,
        bytes memory signature
    ) public view returns (bool);

    function verifyAppraisals(
        AppraisalStruct.Wire calldata wire
    ) external view returns (bool);
}
