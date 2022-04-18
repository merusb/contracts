pragma solidity ^0.5.16;

import "./KBep20.sol";
import "./SafeMath.sol";

interface IBinancePool {
    function stake() external payable;
    function getRelayerFee() external view returns (uint);
}

/**
 * @title Compound's KBNB Contract
 * @notice KToken which wraps Ether
 * @author Compound
 */
contract KBNB is KBep20 {
    using SafeMath for uint;

    address public  binancePool;
    address public  rewardsPool;
    uint    public  lastCash;
    
    /**
     * @notice Construct a new KBNB money market
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
                        uint8 decimals_,
                        address binancePool_,
                        address rewardsPool_) public {
        // KToken initialize does the bulk of the work
        super.initialize(comptroller_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, decimals_);
    
        // Set underlying and sanity check it
        underlying = underlying_;                       // aBNBb
        //EIP20Interface(underlying).totalSupply();
                        
        binancePool = binancePool_;
        rewardsPool = rewardsPool_;
        lastCash    = EIP20Interface(underlying).balanceOf(address(this));
    }

    function _beforeSettleRewards() internal {
        uint delta = EIP20Interface(underlying).balanceOf(address(this)).sub(lastCash);
        if(delta > 0)
            EIP20Interface(underlying).transfer(rewardsPool, delta);
    }
    modifier settleRewards {
        _beforeSettleRewards();
        _;
        _afterSettleRewards();
    }
    function _afterSettleRewards() internal {
        uint cash = EIP20Interface(underlying).balanceOf(address(this));
        if(lastCash != cash)
            lastCash = cash;
    }

    /*** User Interface ***/

   /**
     * @notice Sender supplies assets into the market and receives kTokens in exchange
     * @dev Reverts upon any failure
     */
    function mintInBNB() public payable settleRewards {
        (uint err,) = mintInternal(msg.value);
        requireNoError(err, "mint failed");
    }
    /**
     * @notice Sender supplies assets into the market and receives kTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint mintAmount) external settleRewards returns (uint) {
        (uint err,) = mintInternal(mintAmount);
        return err;
    }

    /**
     * @notice Sender redeems kTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeekTokens The number of kTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint redeekTokens) external settleRewards returns (uint) {
        return redeemInternal(redeekTokens);
    }

    /**
     * @notice Sender redeems kTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlying(uint redeemAmount) external settleRewards returns (uint) {
        return redeemUnderlyingInternal(redeemAmount);
    }

    /**
      * @notice Sender borrows assets from the protocol to their own address
      * @param borrowAmount The amount of the underlying asset to borrow
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function borrow(uint borrowAmount) external settleRewards returns (uint) {
        return borrowInternal(borrowAmount);
    }

    /**
     * @notice Sender repays their own borrow
     * @dev Reverts upon any failure
     */
    function repayBorrowInBNB() external payable settleRewards {
        (uint err,) = repayBorrowInternal(msg.value);
        requireNoError(err, "repayBorrow failed");
    }
    function repayBorrow(uint repayAmount) external settleRewards returns (uint) {
        (uint err,) = repayBorrowInternal(repayAmount);
        return err;
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @dev Reverts upon any failure
     * @param borrower the account with the debt being payed off
     */
    function repayBorrowBehalfInBNB(address borrower) external payable settleRewards {
        (uint err,) = repayBorrowBehalfInternal(borrower, msg.value);
        requireNoError(err, "repayBorrowBehalf failed");
    }
    function repayBorrowBehalf(address borrower, uint repayAmount) external settleRewards returns (uint) {
        (uint err,) = repayBorrowBehalfInternal(borrower, repayAmount);
        return err;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @dev Reverts upon any failure
     * @param borrower The borrower of this kToken to be liquidated
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrowInBNB(address borrower, KToken kTokenCollateral) external payable settleRewards {
        (uint err,) = liquidateBorrowInternal(borrower, msg.value, kTokenCollateral);
        requireNoError(err, "liquidateBorrow failed");
    }
    function liquidateBorrow(address borrower, uint repayAmount, KTokenInterface kTokenCollateral) external settleRewards returns (uint) {
        (uint err,) = liquidateBorrowInternal(borrower, repayAmount, kTokenCollateral);
        return err;
    }

    /**
     * @notice The sender adds to reserves.
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _addReservesInBNB() external payable settleRewards returns (uint) {
        return _addReservesInternal(msg.value);
    }
    function _addReserves(uint addAmount) external settleRewards returns (uint) {
        return _addReservesInternal(addAmount);
    }

    /**
     * @notice Send Ether to KBNB to mint
     */
    function () external payable {
        mintInBNB();
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of Ether, before this message
     * @dev This excludes the value of the current message, if any
     * @return The quantity of Ether owned by this contract
     */
    //function getCashPrior() internal view returns (uint) {
    //    (MathError err, uint startingBalance) = subUInt(address(this).balance, msg.value);
    //    require(err == MathError.NO_ERROR);
    //    return startingBalance;
    //}

    /**
     * @notice Perform the actual transfer in, which is a no-op
     * @param from Address sending the Ether
     * @param amount Amount of Ether being sent
     * @return The actual amount of Ether transferred
     */
    function doTransferIn(address from, uint amount) internal returns (uint) {
        if(msg.value == 0)
            return super.doTransferIn(from, amount);

        // Sanity checks
        require(msg.sender == from, "sender mismatch");
        require(msg.value == amount, "value mismatch");
        IBinancePool(binancePool).stake.value(msg.value)();
        return msg.value.sub(IBinancePool(binancePool).getRelayerFee());
    }

    //function doTransferOut(address payable to, uint amount) internal {
    //    /* Send the Ether, with minimal gas and revert on failure */
    //    to.transfer(amount);
    //}

    function requireNoError(uint errCode, string memory message) internal pure {
        if (errCode == uint(Error.NO_ERROR)) {
            return;
        }

        bytes memory fullMessage = new bytes(bytes(message).length + 5);
        uint i;

        for (i = 0; i < bytes(message).length; i++) {
            fullMessage[i] = bytes(message)[i];
        }

        fullMessage[i+0] = byte(uint8(32));
        fullMessage[i+1] = byte(uint8(40));
        fullMessage[i+2] = byte(uint8(48 + ( errCode / 10 )));
        fullMessage[i+3] = byte(uint8(48 + ( errCode % 10 )));
        fullMessage[i+4] = byte(uint8(41));

        require(errCode == uint(Error.NO_ERROR), string(fullMessage));
    }
}
