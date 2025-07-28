pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./ECVerify.sol";
import "./AppraisalStruct.sol";

/**
 * @title MetaLend's AppraisalOracle Contract
 * @notice Validates appraisals and data created off-chain
 * @author MetaLend
 */
contract AppraisalOracle {
    event NewAdmin(address indexed newAdmin, address indexed previousAdmin);
    event NewAppraiser(address indexed newAppraiser);

    using ECVerify for bytes32;

    address public admin;

    address _appraiser;

    constructor() public {
        admin = msg.sender;
    }

    /**
     * @notice Checks if address is current appraiser
     * @param _address The address to check
     * @return Whether the address is the current appraiser
     */
    function _isAppraiser(address _address) public view returns (bool) {
        return _appraiser == _address;
    }

    /**
     * @notice Sets the address of the appraiser
     * @param newAppraiser The address to set
     */
    function _setAppraiser(address newAppraiser) external {
        require(msg.sender == admin);
        require(newAppraiser != address(0), "appraiser cannot be zero address");
        emit NewAppraiser(newAppraiser);
        _appraiser = newAppraiser;
    }

    /**
     * @notice Checks if the data was created by the current appraiser
     * @param hash The hash of data to check
     * @param signature The signature to check
     * @return Whether the data was created by the current appraiser
     */
    function verifySignature(
        bytes32 hash,
        bytes memory signature
    ) public view returns (bool) {
        address signer = hash.recover(signature);
        return _isAppraiser(signer);
    }

    /**
     * @notice Checks if the appraisal was created by the current appraiser
     * @param wire The appraisal data to check
     * @return Whether the appraisal was created by the current appraiser
     */
    function verifyAppraisals(
        AppraisalStruct.Wire calldata wire
    ) external view returns (bool) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                wire.appraisalTokens,
                wire.appraisalLengths,
                wire.appraisalTokenIds,
                wire.appraisalValues,
                wire.appraisalGoodUntil
            )
        );
        return verifySignature(hash, wire.signature) &&
            wire.appraisalGoodUntil >= getBlockNumber() &&
            wire.appraisalTokens.length == wire.appraisalLengths.length &&
            wire.appraisalTokenIds.length == wire.appraisalValues.length;
    }

    function getBlockNumber() internal view returns (uint) {
        return block.number;
    }

    /**
     * @notice Set the new admin of this contract
     * @param newAdmin new admin for this contract
     */
    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "only the admin may call this function.");
        require(newAdmin != address(0), "admin cannot be zero address");
        emit NewAdmin(newAdmin, admin);
        admin = newAdmin;
    }
}
