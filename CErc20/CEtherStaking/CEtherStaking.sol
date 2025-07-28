pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Lib/Error/ErrorReporter.sol";
import "./CEtherStakingInterface.sol";
import "../../CollateralStaking/Manager/CollateralStakingManagerInterface.sol";
import "../../CollateralStaking/Mediator/CollateralStakingMediatorInterface.sol";
import "../../Interface/RoninStakingInterfaces.sol";
import "../../Lib/Math/SafeMath.sol";

/**
 * @title MetaLend's CEtherStaking Collateral Contract
 * @notice Manages Ether-like assets that are in third party staking contract
 * @author MetaLend
 */

contract CEtherStaking is CErc20CollateralInterface, CEtherStakingInterface, TokenErrorReporter {
    using SafeMath for uint256;
    /**
     * @notice Initialize the new money market
     * @param comptroller_ The address of the Comptroller
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param collateralStakingManagerInterface_ the protocol staking manager interface which handles mediator contracts and supported markets
     */
    function initialize(
        ComptrollerInterface comptroller_,
        string memory name_,
        string memory symbol_,
        CollateralStakingManagerInterface collateralStakingManagerInterface_
    ) public {
        require(msg.sender == admin, "only admin may initialize the market");

        // Set the comptroller
        uint err = _setComptroller(comptroller_);
        require(err == uint(Error.NO_ERROR), "setting comptroller failed");

        name = name_;
        symbol = symbol_;
        
        require(
            CollateralStakingManagerInterface(collateralStakingManagerInterface_)
                .isCollateralStakingManager(), "Not a valid CollateralStakingManager"
        );
        collateralStakingManagerInterface = collateralStakingManagerInterface_;
        emit NewCollateralStakingManager(address(collateralStakingManagerInterface_), address(0));
    }

    /*** User Interface ***/

    /**
     * @notice this function stakes towards a validator and writes a collateralized RON state
     * @dev the tokens will start counting towards users accountTokens for protocol after lock up is over
     * @param consensusAddr the validator to use for staking of collateralized RON
     * @param consensusAddrTarget target for restaking rewards of the collateralized validator
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(
        address consensusAddr,
        address consensusAddrTarget
    ) external payable returns(uint) {
        address mediator = collateralStakingManagerInterface.getCollateralStakingMediator(msg.sender);
        if (mediator != address(0)) {
            // if mediator already exists and has a stake towards given validator get the value to check limit
            uint256 existingAmount = RoninStaking(collateralStakingManagerInterface.roninStaking()).getStakingAmount(consensusAddr, mediator);
            currentCollateralAmount = currentCollateralAmount.add(existingAmount);
        }

        currentCollateralAmount = currentCollateralAmount.add(msg.value);
        require(currentCollateralAmount <= globalCollateralLimit, 
            string(
                abi.encodePacked("Staking would exceed global cap for ", name)
            )
        );

        uint allowed = comptroller.mintAllowedErc20Collateral(address(this));
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.MINT_COMPTROLLER_REJECTION, allowed);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        if (mediator == address(0)) {
            mediator = collateralStakingManagerInterface.getOrCreateCollateralStakingMediator(msg.sender);
        }
        CollateralStakingMediatorInterface(mediator).delegateCollateralizedRon.value(msg.value)(consensusAddr, consensusAddrTarget);

        emit Mint(msg.sender, msg.value);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sender supplies assets into the market
     * @param consensusAddr The validator from which to move the tokens to protocol
     * @param consensusAddrTarget target for restaking rewards of the collateralized validator
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function moveToProtocol(
        address consensusAddr,
        address consensusAddrTarget
    ) external returns (uint) {
        address mediator = collateralStakingManagerInterface.getCollateralStakingMediator(msg.sender);
        require(mediator != address(0), "Mediator does not exist");

        uint256 mintAmount = RoninStaking(collateralStakingManagerInterface.roninStaking()).getStakingAmount(consensusAddr, mediator);
        require(mintAmount > 0, "No tokens to move to protocol");

        currentCollateralAmount = currentCollateralAmount.add(mintAmount);
        require(currentCollateralAmount <= globalCollateralLimit, 
            string(
                abi.encodePacked("Staking would exceed global cap for ", name)
            )
        );

        uint allowed = comptroller.mintAllowedErc20Collateral(address(this));
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.MINT_COMPTROLLER_REJECTION, allowed);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        CollateralStakingMediatorInterface(mediator).moveUncollateralizedRonToProtocol(consensusAddr, consensusAddrTarget);

        emit Mint(msg.sender, mintAmount);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sender redeems collateral
     * @param consensusAddr The validator from witch to redeem tokens
     * @param redeemTokens The tokens to redeem
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(
        address consensusAddr,
        uint redeemTokens,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint) {
        address mediator = collateralStakingManagerInterface.getCollateralStakingMediator(msg.sender);
        require(mediator != address(0), "Mediator does not exist");

        require(redeemTokens <= RoninStaking(collateralStakingManagerInterface.roninStaking()).getStakingAmount(consensusAddr, mediator), "Insufficient tokens to redeem");

        uint allowed = comptroller.redeemAllowedErc20Collateral(address(this), msg.sender, redeemTokens, appraisal);
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.REDEEM_COMPTROLLER_REJECTION, allowed);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        currentCollateralAmount = currentCollateralAmount.sub(redeemTokens);        
        address[] memory consensusAddrList = new address[](1);
        consensusAddrList[0] = consensusAddr;
        uint256[] memory redeemTokensArr = new uint256[](1);
        redeemTokensArr[0] = redeemTokens;
        CollateralStakingMediatorInterface(mediator).redeemCollateralizedRon(consensusAddrList, redeemTokensArr, msg.sender);

        emit Redeem(msg.sender, redeemTokens);
        return uint(Error.NO_ERROR);
    }

    /**
     * @notice CToken being borrowed seizes tokens for the liquidator
     * @param liquidator The liquidator receiving the seized tokens
     * @param borrower The borrower whose tokens are being seized
     * @param seizeTokens The number of tokens to seize
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function seizeAndRedeem(
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint) {
        address mediator = collateralStakingManagerInterface.getCollateralStakingMediator(borrower);
        require(mediator != address(0), "Mediator does not exist");
        require(seizeTokens <= getAccountTokens(borrower), "user has insufficient tokens to seize");
        require(CTokenInterface(msg.sender).comptroller() == comptroller, "comptroller mismatch");

         /* Fail if seize not allowed */
        uint allowed = comptroller.seizeAllowedErc20Collateral(address(this), msg.sender);
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.LIQUIDATE_SEIZE_COMPTROLLER_REJECTION, allowed);
        }

        /* Fail if borrower = liquidator */
        if (borrower == liquidator) {
            return fail(Error.INVALID_ACCOUNT_PAIR, FailureInfo.LIQUIDATE_SEIZE_LIQUIDATOR_IS_BORROWER);
        }

        // Extract from borrower
        currentCollateralAmount = currentCollateralAmount.sub(seizeTokens);
        address[] memory userActiveValidators = CollateralStakingMediatorInterface(mediator).getActiveCollateralizedValidators();
        uint256 combinedAmount;
        uint256[] memory amountsPerValidator = new uint256[](userActiveValidators.length);
        address[] memory withdrawValidators = new address[](userActiveValidators.length);

        for (uint256 i = 0; i < userActiveValidators.length; i++) {
            address consensusAddr = userActiveValidators[i];
            if (CollateralStakingMediatorInterface(mediator).poolToUndelegateCooldown(consensusAddr) >= block.timestamp) {
                continue;
            }
            uint256 amountPerValidator = RoninStaking(collateralStakingManagerInterface.roninStaking()).getStakingAmount(consensusAddr, mediator);
            combinedAmount = combinedAmount.add(amountPerValidator);
            if (combinedAmount >= seizeTokens) {
                uint256 remainingAmount = amountPerValidator.add(seizeTokens).sub(combinedAmount);
                amountsPerValidator[i] = remainingAmount;
                withdrawValidators[i] = consensusAddr;
                break;
            } else {
                amountsPerValidator[i] = amountPerValidator;
                withdrawValidators[i] = consensusAddr;
            }
        }

        CollateralStakingMediatorInterface(mediator).redeemCollateralizedRon(withdrawValidators, amountsPerValidator, address(uint160(liquidator)));

        emit Transfer(borrower, liquidator, seizeTokens);

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

    function getAccountTokens(address account) public view returns (uint) {
        address mediator = collateralStakingManagerInterface.getCollateralStakingMediator(account);
        if (mediator == address(0)) {
            return 0;
        }
        CollateralStakingMediatorInterface mediatorContract = CollateralStakingMediatorInterface(mediator);
        address[] memory userActiveValidators = mediatorContract.getActiveCollateralizedValidators();
        uint256 accountTokens;
        for (uint256 i = 0; i < userActiveValidators.length; i++) {
            address validator = userActiveValidators[i];
            uint256 cooldown = mediatorContract.poolToUndelegateCooldown(validator);
            if (cooldown < block.timestamp) {
                accountTokens = accountTokens.add(RoninStaking(collateralStakingManagerInterface.roninStaking()).getStakingAmount(validator, mediator));
            }
        }
        return accountTokens;
    }

    /**
      * @notice Sets a new collateralStakingManagerInterface for the market
      * @dev Admin function to set a new collateralStakingManagerInterface
      */
    function _setCollateralStakingManager(address newCollateralStakingManagerInterface) external {
        require(msg.sender == admin, "Not allowed");
        require(
            CollateralStakingManagerInterface(newCollateralStakingManagerInterface)
                .isCollateralStakingManager(), "Not a valid CollateralStakingManager"
        );
        emit NewCollateralStakingManager(newCollateralStakingManagerInterface, address(collateralStakingManagerInterface));
        collateralStakingManagerInterface = CollateralStakingManagerInterface(newCollateralStakingManagerInterface);
    }

    /**
     * @notice Sets a new limit for maximum amount of tokenKind in protocol
     * @dev used for revert during mint if the staking amount + current amount of tokenKind in protocol would exceed the global limit
     */
    function _setGlobalCollateralLimit(uint newLimit) external {
        require(msg.sender == admin, "Not allowed");
        emit NewGlobalCollateralLimit(newLimit, globalCollateralLimit);
        globalCollateralLimit = newLimit;
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
}
