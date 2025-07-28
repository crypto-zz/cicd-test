pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CToken.sol";
import "./CTokenInterfaces.sol";

/**
 * @title MetaLend's CErc20 Contract
 * @notice CTokens which wrap an EIP-20 underlying
 * @author MetaLend
 */
contract CErc20 is CToken, CErc20Interface {
    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function initialize(address underlying_,
                        ComptrollerInterface comptroller_,
                        InterestRateModel interestRateModel_,
                        uint initialExchangeRateMantissa_,
                        string memory name_,
                        string memory symbol_,
                        uint8 decimals_) public {
        // CToken initialize does the bulk of the work
        super.initialize(
            comptroller_,
            interestRateModel_,
            initialExchangeRateMantissa_,
            name_,
            symbol_,
            decimals_
        );

        require(underlying_ != address(0), "underlying cannot be zero address");
        // Set underlying and sanity check it
        underlying = underlying_;
        EIP20Interface(underlying).totalSupply();
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives cTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint mintAmount) external returns (uint) {
        (uint err,) = mintInternal(mintAmount);
        return err;
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
     * @param repayAmount The amount to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrow(uint repayAmount) external returns (uint) {
        (uint err,) = repayBorrowInternal(repayAmount);
        return err;
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint) {
        (uint err,) = repayBorrowBehalfInternal(borrower, repayAmount);
        return err;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(
        address borrower,
        uint repayAmount,
        CTokenInterface cTokenCollateral,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        (uint err,) = liquidateBorrowInternal(borrower, repayAmount, cTokenCollateral, appraisal);
        return err;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The mainchain collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cErc721TokenCollateral The market in which to seize collateral from the borrower
     * @param tokenIds The tokenIds to seize
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrowAndRedeemErc721Mainchain(
        address borrower,
        uint repayAmount,
        CErc721Interface cErc721TokenCollateral,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        (uint err,) = liquidateBorrowInternalErc721(
            LiquidateBorrowKind.ERC721_REDEEM_MAINCHAIN,
            borrower,
            repayAmount,
            cErc721TokenCollateral,
            tokenIds,
            appraisal
        );
        return err;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The staking collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cErc721TokenCollateral The market in which to seize collateral from the borrower
     * @param tokenIds The tokenIds to seize
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrowAndRedeemErc721Staking(
        address borrower,
        uint repayAmount,
        CErc721Interface cErc721TokenCollateral,
        uint256[] memory tokenIds,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        (uint err,) = liquidateBorrowInternalErc721(
            LiquidateBorrowKind.ERC721_REDEEM_STAKING,
            borrower,
            repayAmount,
            cErc721TokenCollateral,
            tokenIds,
            appraisal
        );
        return err;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The staking collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cErc20CollateralToken The market in which to seize collateral from the borrower
     * @param appraisal The appraisal of Erc721 assets
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrowAndRedeemErc20CollateralStaking(
        address borrower,
        uint repayAmount,
        CErc20CollateralInterface cErc20CollateralToken,
        AppraisalStruct.Wire memory appraisal
    ) public returns (uint) {
        (uint err,) = liquidateBorrowInternalErc20Collateral(
            LiquidateBorrowKind.ERC20_COLLATERAL_REDEEM_STAKING,
            borrower,
            repayAmount,
            cErc20CollateralToken,
            appraisal
        );
        return err;
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin (timelock)
     * @param token The address of the ERC-20 token to sweep
     */
    function sweepToken(EIP20NonStandardInterface token) external {
    	require(address(token) != underlying, "CErc20::sweepToken: can not sweep underlying token");
    	uint256 balance = token.balanceOf(address(this));
    	token.transfer(admin, balance);
    }

    /**
     * @notice The sender adds to reserves.
     * @param addAmount The amount fo underlying token to add as reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _addReserves(uint addAmount) external returns (uint) {
        return _addReservesInternal(addAmount);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view returns (uint) {
        return underlyingBalance;
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     *      This will revert due to insufficient balance or insufficient allowance.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     * @param amountAdjusted is unsused for CErc20 itself. It serves a purpose for CEther contract.
     */
    function doTransferIn(address from, uint amount, uint amountAdjusted) internal returns (uint) {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        uint balanceBefore = EIP20Interface(underlying).balanceOf(address(this));
        token.transferFrom(from, address(this), amount);

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

        // Calculate the amount that was *actually* transferred
        uint balanceAfter = EIP20Interface(underlying).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        uint transferredAmount = balanceAfter - balanceBefore; // underflow already checked above, just subtract
        underlyingBalance = add_(underlyingBalance, transferredAmount);
        return transferredAmount;
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     *      error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
     *      insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
     *      it is >= amount, this should not revert in normal conditions.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferOut(address payable to, uint amount) internal {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        token.transfer(to, amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {                      // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                     // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                     // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
        underlyingBalance = sub_(underlyingBalance, amount);
    }

    function addCash(uint256 amount) external {
        doTransferIn(msg.sender, amount, 0);
    }
}
