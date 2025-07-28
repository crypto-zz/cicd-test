pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CToken.sol";
import "./CTokenInterfaces.sol";

/**
 * @title MetaLend's CEther Contract
 * @notice CToken which wraps Ether
 * @author MetaLend
 */
contract CEther is CToken, CEtherInterface {
    /**
     * @notice Construct a new CEther money market
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function initialize(ComptrollerInterface comptroller_,
                InterestRateModel interestRateModel_,
                uint initialExchangeRateMantissa_,
                string memory name_,
                string memory symbol_,
                uint8 decimals_) public {
        // Creator of the contract is admin during initialization
        super.initialize(
            comptroller_,
            interestRateModel_,
            initialExchangeRateMantissa_,
            name_,
            symbol_,
            decimals_
        );
    }


    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives cTokens in exchange
     * @dev Reverts upon any failure
     */
    function mint() external payable {
        (uint err,) = mintInternal(msg.value);
        requireNoError(err, "mint failed");
    }

    /**
     * @notice Sender redeems cTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of cTokens to redeem into underlying
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(
        uint redeemTokens,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        return redeemInternal(redeemTokens, appraisal, false);
    }

    /**
     * @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlying(
        uint redeemAmount,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        return redeemInternal(redeemAmount, appraisal, true);
    }

    /**
      * @notice Sender borrows assets from the protocol to their own address
      * @param borrowAmount The amount of the underlying asset to borrow
      * @param appraisal The appraisal of Erc721 assets
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function borrow(
        uint borrowAmount,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        return borrowInternal(borrowAmount, appraisal);
    }

    /**
     * @notice Sender repays their own borrow
     * @dev Reverts upon any failure
     */
    function repayBorrow() external payable {
        (uint err,) = repayBorrowInternal(msg.value);
        requireNoError(err, "repayBorrow failed");
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @dev Reverts upon any failure
     * @param borrower the account with the debt being payed off
     */
    function repayBorrowBehalf(address borrower) external payable {
        (uint err,) = repayBorrowBehalfInternal(borrower, msg.value);
        requireNoError(err, "repayBorrowBehalf failed");
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @dev Reverts upon any failure
     * @param borrower The borrower of this cToken to be liquidated
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     * @param appraisal The appraisal of Erc721 assets
     */
    function liquidateBorrow(
        address borrower,
        CTokenInterface cTokenCollateral,
        AppraisalStruct.Wire memory appraisal
    ) public payable {
        (uint err,) = liquidateBorrowInternal(borrower, msg.value, cTokenCollateral, appraisal);
        requireNoError(err, "liquidateBorrow failed");
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The mainchain collateral seized is transferred to the liquidator and redeemed across the bridge.
     * @param borrower The borrower of this cToken to be liquidated
     * @param cErc721TokenCollateral The market in which to seize collateral from the borrower
     * @param tokenIds The tokenIds to seize
     * @param appraisal The appraisal of Erc721 assets
     */
    function liquidateBorrowAndRedeemErc721Mainchain(
        address borrower,
        CErc721Interface cErc721TokenCollateral,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public payable {
        (uint err,) = liquidateBorrowInternalErc721(
            LiquidateBorrowKind.ERC721_REDEEM_MAINCHAIN,
            borrower,
            msg.value,
            cErc721TokenCollateral,
            tokenIds,
            appraisal
        );
        requireNoError(err, "liquidateBorrowAndRedeemErc721Mainchain failed");
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The staking collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param cErc721TokenCollateral The market in which to seize collateral from the borrower
     * @param tokenIds The tokenIds to seize
     * @param appraisal The appraisal of Erc721 assets
     */
    function liquidateBorrowAndRedeemErc721Staking(
        address borrower,
        CErc721Interface cErc721TokenCollateral,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public payable {
        (uint err,) = liquidateBorrowInternalErc721(
            LiquidateBorrowKind.ERC721_REDEEM_STAKING,
            borrower,
            msg.value,
            cErc721TokenCollateral,
            tokenIds,
            appraisal
        );
        requireNoError(err, "liquidateBorrowAndRedeemErc721Staking failed");
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The staking collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param cErc20CollateralToken The market in which to seize collateral from the borrower
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrowAndRedeemErc20CollateralStaking(
        address borrower,
        CErc20CollateralInterface cErc20CollateralToken,
        AppraisalStruct.Wire memory appraisal
    ) public payable {
        (uint err,) = liquidateBorrowInternalErc20Collateral(
            LiquidateBorrowKind.ERC20_COLLATERAL_REDEEM_STAKING,
            borrower,
            msg.value,
            cErc20CollateralToken,
            appraisal
        );
        requireNoError(err, "liquidateBorrowAndRedeemErc20Staking failed");
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin (timelock)
     * @param token The address of the ERC-20 token to sweep
     */
    function sweepToken(EIP20NonStandardInterface token) external {
    	uint256 balance = token.balanceOf(address(this));
    	token.transfer(admin, balance);
    }

    /**
     * @notice The sender adds to reserves.
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _addReserves() external payable returns (uint) {
        return _addReservesInternal(msg.value);
    }

    /**
     * @notice Send Ether to CEther to mint
     */
    function () external payable {
        (uint err,) = mintInternal(msg.value);
        requireNoError(err, "mint failed");
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of Ether, before this message
     * @dev This excludes the value of the current message, if any
     * @return The quantity of Ether owned by this contract
     */
    function getCashPrior() internal view returns (uint) {
        (MathError err, uint startingBalance) = subUInt(address(this).balance, msg.value);
        require(err == MathError.NO_ERROR);
        return startingBalance;
    }

    /**
     * @notice Perform the actual transfer in, which is a no-op
     * @param from Address sending the Ether
     * @param amount Amount of Ether being sent
     * @param amountAdjusted Serves as a modifier for amount for liquidation usecase when overpay is converted to lendable assets
     *  In that scenario, msg.value is split in two parts - one which repays accountBorrows and the other which mints new lendable assets
     *  For minting and repaying, amountAdjusted is passed as 0 value.
     * @return The actual amount of Ether transferred
     */
    function doTransferIn(address from, uint amount, uint amountAdjusted) internal returns (uint) {
        // Sanity checks
        require(msg.sender == from, "sender mismatch");
        (MathError err, uint msgValueAdjusted) = subUInt(msg.value, amountAdjusted);
        require(err == MathError.NO_ERROR, "doTransferIn amount adjusted underflow");
        require(msgValueAdjusted == amount, "value mismatch");
        return amount;
    }

    function doTransferOut(address payable to, uint amount) internal {
        (bool success, ) = to.call.value(amount)("");
        require(success, "Failed to send value");
    }

    function requireNoError(uint errCode, string memory message) internal pure {
        if (errCode == uint(Error.NO_ERROR)) {
            return;
        }

        require(errCode == uint(Error.NO_ERROR), 
            string(
                abi.encodePacked(
                    message, " (", uint8(48 + ( errCode / 10 )), uint8(48 + ( errCode % 10 )), ")") 
            )
        );
    }

    function addCash() external payable {
        doTransferIn(msg.sender, msg.value, 0);
    }
}
