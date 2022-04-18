pragma solidity ^0.5.16;

import "./KBep20.sol";
import "./USB.sol";

contract KUSB is KBep20 {
    function doTransferIn(address from, uint amount) internal returns (uint) {
        USB(underlying).burn(from, amount);
		return amount;
    }

    function doTransferOut(address payable to, uint amount) internal {
        USB(underlying).mint(to, amount);
    }

    function getCashPrior() internal view returns (uint) {
        return 1e9 * 1e18;
    }
}
