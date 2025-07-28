pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Comptroller/ComptrollerInterface.sol";
import "../CErc721Interface.sol";
import "./CErc721MainchainInterface.sol";
import "../../Lib/Error/ErrorReporter.sol";
import "../../Interface/ERC721Interface.sol";
import "../../Lib/Axie/MysticGeneValidator.sol";


/**
 * @title MetaLend's CErc721Mainchain Contract
 * @notice Manages Erc721 assets that are held on mainchain
 * @author MetaLend
 */
contract CErc721Mainchain is CErc721Interface, CErc721MainchainInterface, IERC721Receiver, CDelegationStorage, TokenErrorReporter, CAxieMysticValidatorStorage {
    /**
     * @notice Construct a new CErc721 money market
     * @param comptroller_ The address of the Comptroller
     * @param underlying_ The address of the underlying NFT contract
     * @param name_ ERC-721 name of this token
     * @param symbol_ ERC-721 symbol of this token
     */
    function initialize(
        ComptrollerInterface comptroller_,
        address underlying_,
        string memory name_,
        string memory symbol_
    ) public {
        require(msg.sender == admin, "only admin may initialize the market");

        // Set the comptroller
        uint err = _setComptroller(comptroller_);
        require(err == uint(Error.NO_ERROR), "setting comptroller failed");
        require(underlying_ != address(0), "underlying cannot be zero address");

        // Set underlying
        underlying = underlying_;

        name = name_;
        symbol = symbol_;
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives CErc721 in exchange
     * @param tokenIds The tokenIds to mint
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(
        uint256[] calldata tokenIds
    ) external returns (uint) {
        require(tokenIds.length < 51, "Too many tokens, max 50 at once.");
        
        /* Fail if mint not allowed */
        uint allowed = comptroller.mintAllowedErc721(address(this));
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.MINT_COMPTROLLER_REJECTION, allowed);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        address owner;

        for (uint i = 0; i < tokenIds.length; i++) {
            uint tokenId = tokenIds[i];

            // Protocol only supports mystic Axies as collateral
            require(MysticGeneValidator(geneValidator).isMystic(tokenId), "non-mystic axies are unsupported");

            owner = ERC721Interface(underlying).ownerOf(tokenId);
            require(owner == msg.sender, "owner and sender mismatch");

            accountTokens[owner].push(tokenId);
            tokenOwners[tokenId] = owner;

            ERC721Interface(underlying).safeTransferFrom(owner, address(this), tokenId);
        }

        emit Mint(owner, tokenIds);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sender redeems CErc721 in exchange for the underlying asset
     * @param tokenIds The tokenIds to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(
        uint256[] calldata tokenIds,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint) {
        require(tokenIds.length < 51, "Too many tokens, max 50 at once.");

        /* Fail if redeem not allowed */
        uint allowed = comptroller.redeemAllowedErc721(
            address(this),
            msg.sender,
            tokenIds,
            appraisal
        );

        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.REDEEM_COMPTROLLER_REJECTION, allowed);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        
        // removes tokens from account and transfers them back to the original owner
        removeFromAccountTokens(msg.sender, msg.sender, tokenIds, true);
        emit Redeem(msg.sender, tokenIds);
        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Removes CErc721 tokenIds from the account and transfers them to the receiver
     * @param account The account to remove the tokenIds from
     * @param receiver The account to receive the tokens
     * @param tokenIds The tokenIds to remove
     */
    function removeFromAccountTokens(
        address account,
        address receiver,
        uint[] memory tokenIds,
        bool transferOut
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
            if(transferOut){
                // transfer token to receiver
                ERC721Interface(underlying).safeTransferFrom(address(this), receiver, tokenId);
            }

            tokenOwners[tokenId] = address(0);
        }
    }

    /**
     * @notice CToken being borrowed seizes tokenIds for the liquidator
     * @param liquidator The liquidator receiving the seized tokenIds
     * @param borrower The borrower whose tokenIds are being seized
     * @param tokenIds The tokenIds to seize
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function seizeAndRedeem(
        address liquidator,
        address borrower,
        uint256[] calldata tokenIds
    ) external returns (uint) {
        require(tokenIds.length < 51, "Too many tokens, max 50 at once.");
        require(CTokenInterface(msg.sender).comptroller() == comptroller, "comptroller mismatch");
        
        /* Fail if seize not allowed */
        uint allowed = comptroller.seizeAllowedErc721(address(this), msg.sender);
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.LIQUIDATE_SEIZE_COMPTROLLER_REJECTION, allowed);
        }

        /* Fail if borrower = liquidator */
        if (borrower == liquidator) {
            return fail(Error.INVALID_ACCOUNT_PAIR, FailureInfo.LIQUIDATE_SEIZE_LIQUIDATOR_IS_BORROWER);
        }

        // removes tokens from borrower and transfers them to liquidator
        removeFromAccountTokens(borrower, liquidator, tokenIds, true);

        emit Redeem(liquidator, tokenIds);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets a new comptroller for the market
      * @dev Admin function to set a new comptroller
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setComptroller(ComptrollerInterface newComptroller) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK);
        }

        ComptrollerInterface oldComptroller = comptroller;

        // Set market's comptroller to newComptroller
        comptroller = newComptroller;

        // Emit NewComptroller(oldComptroller, newComptroller)
        emit NewComptroller(oldComptroller, newComptroller);

        return uint(Error.NO_ERROR);
    }

    function getAccountTokens(address account) external view returns (uint256[] memory) {
        return accountTokens[account];
    }

    /**
      * @notice onERC721Received implementation to support safeTransferFrom
      */
    function onERC721Received(
        address, 
        address, 
        uint256, 
        bytes calldata
    ) external returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    /**
     * @notice Set the new admin of this contract
     * @param newAdmin new admin for this contract
     */
    function setAdmin(address payable newAdmin) external {
        require(msg.sender == admin, "only the admin may call this function.");
        require(newAdmin != address(0), "new admin cannot be zero address");
        emit NewAdmin(newAdmin, admin);
        admin = newAdmin;
    } 

    /**
     * @notice Set mystic gene validator for this contract
     * @param validator contract address
     */
     function setGeneValidator(address validator) external {
        require(msg.sender == admin, "only the admin may call this function.");
        require(geneValidator != address(0), "gene validator cannot be zero address");
        emit NewAxieGeneValidator(validator, geneValidator);
        geneValidator = validator;
     }
}
