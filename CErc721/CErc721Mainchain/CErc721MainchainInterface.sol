pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Oracle/AppraisalStruct.sol";
import "../../Comptroller/ComptrollerInterface.sol";
import "../../Oracle/AppraisalOracleInterface.sol";

contract CErc721MainchainStorage {
    address payable public admin;

    string public name;

    string public symbol;

    ComptrollerInterface public comptroller;

    mapping(address => uint256[]) public accountTokens;

    mapping(uint256 => address) public tokenOwners;

    address public underlying;
}

contract CErc721MainchainInterface is CErc721MainchainStorage {
    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint256[] tokenIds);

    event Transfer(address indexed from, address indexed to, uint256[] tokenIds);

    event NewAdmin(address indexed newAdmin, address indexed previousAdmin);
    
    event NewAxieGeneValidator(address indexed newGeneValidator, address indexed previousGeneValidator);

    /**
     * @notice Event emitted when comptroller is changed
     */
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint256[] tokenIds);

    function mint(
        uint256[] calldata tokenIds
    ) external returns (uint);

    function redeem(
        uint256[] calldata tokenIds,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint);

    function seizeAndRedeem(
        address liquidator,
        address borrower,
        uint256[] calldata tokenIds
    ) external returns (uint);
}

contract CAxieMysticValidatorStorage {
    /**
     * @notice Validator contract to check Axie for mystic genes
     */
    address public geneValidator;
}
