pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../Comptroller/ComptrollerInterface.sol";
import "../CErc20CollateralInterface.sol";
import "../../Lib/Error/ErrorReporter.sol";
import "./CErc20StakingInterface.sol";
import "../../Interface/EIP20NonStandardInterface.sol";
import "../../Interface/EIP20Interface.sol";
import "../../CollateralStaking/Manager/CollateralStakingManagerInterface.sol";
import "../../CollateralStaking/Mediator/CollateralStakingMediatorInterface.sol";
import "../../Lib/Math/SafeMath.sol";
import "../../Lib/SafeErc20/SafeErc20.sol";

/**
 * @title MetaLend's CErc20Staking Collateral Contract
 * @notice Manages Erc20 assets that are in third party staking contract
 * @author MetaLend
 */

contract CErc20Staking is CErc20CollateralInterface, CErc20StakingInterface, TokenErrorReporter {
    using SafeMath for uint256;
    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param comptroller_ The address of the Comptroller
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param collateralStakingManagerInterface_ the protocol staking manager interface which handles mediator contracts and supported markets
     */
    function initialize(
        address underlying_,
        ComptrollerInterface comptroller_,
        string memory name_,
        string memory symbol_,
        CollateralStakingManagerInterface collateralStakingManagerInterface_
    ) public {
        require(msg.sender == admin, "only admin may initialize the market");

        // Set the comptroller
        uint err = _setComptroller(comptroller_);
        require(err == uint(Error.NO_ERROR), "setting comptroller failed");
        require(underlying_ != address(0), "underlying cannot be zero address");

        underlying = underlying_;
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
     * @notice Sender supplies assets into the market
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(
        uint mintAmount
    ) external returns (uint) {
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
        address mediator = collateralStakingManagerInterface.getOrCreateCollateralStakingMediator(msg.sender);
        SafeErc20.safeTransferFrom(underlying, msg.sender, mediator, mintAmount);
        accountTokens[msg.sender] = accountTokens[msg.sender].add(mintAmount);
        CollateralStakingMediatorInterface(mediator).stakeErc20(mintAmount);

        emit Mint(msg.sender, mintAmount);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice ability to move assets between uncollatarized staking and protocol
     * @dev this function is unique to CErc20Staking which underlying represents staking pool for uncollateralized assets
     * @param mintAmount the amount to move from uncollateralized assets to protocol
     */
    function moveUncollateralizedToProtocol(
        uint256 mintAmount
    ) external returns (uint256) {
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
        address mediator = collateralStakingManagerInterface.getCollateralStakingMediator(msg.sender);
        require(mediator != address(0), "Mediator does not exist");
        CollateralStakingMediatorInterface(mediator).moveUncollateralizedErc20ToProtocol(mintAmount);
        accountTokens[msg.sender] = accountTokens[msg.sender].add(mintAmount);

        emit Mint(msg.sender, mintAmount);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sender redeems collateral
     * @param redeemTokens The tokens to redeem
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(
        uint redeemTokens,
        AppraisalStruct.Wire calldata appraisal
    ) external returns (uint) {
        require(redeemTokens <= accountTokens[msg.sender], "user has insufficient tokens to redeem");

        uint allowed = comptroller.redeemAllowedErc20Collateral(address(this), msg.sender, redeemTokens, appraisal);
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.REDEEM_COMPTROLLER_REJECTION, allowed);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        currentCollateralAmount = currentCollateralAmount.sub(redeemTokens);
        accountTokens[msg.sender] = accountTokens[msg.sender].sub(redeemTokens);
        /**
         * unstake tokens from borrowers staking mediator and send them to owner
         */
        address mediator = collateralStakingManagerInterface.getCollateralStakingMediator(msg.sender);
        require(mediator != address(0), "Mediator does not exist");
        CollateralStakingMediatorInterface(mediator).unstakeErc20(redeemTokens, msg.sender);

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
        require(seizeTokens <= accountTokens[borrower], "user has insufficient tokens to seize");
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
        accountTokens[borrower] = accountTokens[borrower].sub(seizeTokens);
        /**
         * unstake tokens from borrowers staking mediator and send them to liquidator
         */
        address mediator = collateralStakingManagerInterface.getCollateralStakingMediator(borrower);
        require(mediator != address(0), "Mediator does not exist");
        CollateralStakingMediatorInterface(mediator).unstakeErc20(seizeTokens, liquidator);

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

    function getAccountTokens(address account) external view returns (uint) {
        return accountTokens[account];
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
