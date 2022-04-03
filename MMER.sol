pragma solidity ^0.5.16;

import "./MBep20.sol";

contract MMER is MBep20 {
    address public minter;

    /*** User Interface ***/

    function setMinter(address minter_) external {
        require(msg.sender == admin, "only admin");
        minter = minter_;
    }

    /**
     * @notice Sender supplies assets into the market and receives mTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint mintAmount) external returns (uint) {
        require(msg.sender == minter || minter == address(0), "only minter");
        (uint err,) = mintInternal(mintAmount);
        return err;
    }

}
