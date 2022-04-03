// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Include.sol";

//contract Stabilizer is Configurable {
contract Stabilizer is Initializable, Sets{
    using Config for bytes32;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 internal constant _priceFloor_      = "priceFloor";
    bytes32 internal constant _priceCeiling_    = "priceCeiling";
    bytes32 internal constant _timeSpan_        = "timeSpan";
    bytes32 internal constant _lasttime_        = "lasttime";
    bytes32 internal constant _Comptrpller_     = "Comptrpller";
    bytes32 internal constant _MER_             = "MER";
    bytes32 internal constant _MMER_            = "MMER";
    bytes32 internal constant _MUSB_            = "MUSB";
    bytes32 internal constant _USB_             = "USB";
    bytes32 internal constant _USD_             = "USD";
    bytes32 internal constant _swapRouter_      = "swapRouter";
    bytes32 internal constant _swapFactory_     = "swapFactory";
    
    function __Stabilizer_init() external initializer {
        __Stabilizer_init_unchained();
    }

    function __Stabilizer_init_unchained() internal {
        mapping (bytes32 => uint) storage config = Config.config();
        mapping (bytes32 => address) storage configA = Config.configA();
        config[_priceFloor_     ] = 0.99e18;
        config[_priceCeiling_   ] = 1.01e18;
        config[_timeSpan_       ] = 8 hours;
        config[_lasttime_       ] = block.timestamp;
        //configA[_Comptrpller_   ] = ;
        //configA[_MER_           ] = ;
        //configA[_MMER_          ] = ;
        //configA[_MUSB_          ] = ;
        //configA[_USB_           ] = ;
        configA[_USD_           ] = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;     // BUSD
        configA[_swapRouter_    ] = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
        configA[_swapFactory_   ] = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    }

    function _getPairInfo() internal view returns(address USB, address USD, address pair, uint x, uint y) {
        mapping (bytes32 => address) storage configA = Config.configA();
        USB = configA[_USB_];
        USD = configA[_USD_];
        pair = IUniswapV2Factory(configA[_swapFactory_]).getPair(USD, USB);
        x = IERC20(USB).balanceOf(pair);
        y = IERC20(USD).balanceOf(pair);
    }
    
    function _price2(address pair, uint x, uint y) internal pure returns(uint) {
        if(pair == address(0) || x == 0)
            return 0;
        return y.mul(1e18).div(x);
    }

    function price2() public view returns(uint) {
        ( , , address pair, uint x, uint y) = _getPairInfo();
        return _price2(pair, x, y);
    }

    function needStabilize() external view returns(bool) {
        return _needStabilize(price2());
    }
    function _needStabilize(uint p2) internal view returns(bool) {
        mapping (bytes32 => uint) storage config = Config.config();
        return p2 > 0 && (p2 <= config[_priceFloor_] || p2 >= config[_priceCeiling_] || block.timestamp >= config[_lasttime_].add(config[_timeSpan_]));
    }

    function _sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _calcDelta(uint x, uint y) internal pure returns(uint) {
        if(x > y)
            (x, y) = (y, x);
        return _sqrt(x.mul(9).add(y.mul(4000*997)).mul(x)).sub(x.mul(1997)).div(2*997);
    }
    
    function stabilize() external {
        (address USB, address USD, address pair, uint x, uint y) = _getPairInfo();
        uint p2 = _price2(pair, x, y);
        if(!_needStabilize(p2))
            return;
        uint delta = _calcDelta(x, y);
        //IComptroller comptroller = IComptroller(_Comptrpller_.getA());
        IUniswapV2Router01 router = IUniswapV2Router01(_swapRouter_.getA());
        address[] memory path = new address[](2);
        address MUSB = _MUSB_.getA();
        if(p2 > 1e18) {
            uint balUSB = IERC20(USB).balanceOf(address(this));
            if(balUSB < delta) {
                //if(0 == comptroller.borrowAllowed(MUSB, address(this), delta - balUSB))
                if(0 != IMBep20(MUSB).borrow(delta - balUSB))
                    delta = balUSB;
                if(delta == 0)
                    return;
            }
            (path[0], path[1]) = (USB, USD);
            IERC20(USB).safeApprove_(address(router), delta);
            router.swapExactTokensForTokens(delta, 0, path, address(this), block.timestamp);
        } else if(p2 < 1e18 && p2 > 0) {
            uint balUSD = IERC20(USD).balanceOf(address(this));
            if(balUSD < delta) {
                address MER = _MER_.getA();
                pair = IUniswapV2Factory(_swapFactory_.getA()).getPair(MER, USD);
                y = IERC20(USD).balanceOf(pair);
                if(pair != address(0) && y > delta - balUSD && IERC20(MER).balanceOf(address(this)) >= (x = router.getAmountIn(delta - balUSD, IERC20(MER).balanceOf(pair), y))) {
                    (path[0], path[1]) = (MER, USD);
                    IERC20(MER).safeApprove_(address(router), x);
                    router.swapTokensForExactTokens(delta - balUSD, x, path, address(this), block.timestamp);
                } else
                    delta = balUSD;
            }
            if(delta == 0)
                return;
            (path[0], path[1]) = (USD, USB);
            IERC20(USD).safeApprove_(address(router), delta);
            router.swapExactTokensForTokens(delta, 0, path, address(this), block.timestamp);
            uint repayAmt = Math.min(IERC20(USB).balanceOf(address(this)), IMBep20(MUSB).borrowBalanceCurrent(address(this)));
            //if(0 == comptroller.repayBorrowAllowed(MUSB, address(this), address(this), repayAmt)) {
            IERC20(USB).safeApprove_(MUSB, repayAmt);
            IMBep20(MUSB).repayBorrow(repayAmt);
        } else
            return;
        emit Stabilize(p2, delta);
    }
    event Stabilize(uint p2, uint delta);

    function mintMMER_(uint amtMER) external governance returns(uint) {
        address MMER = _MMER_.getA();
        IERC20(_MER_.getA()).safeApprove_(MMER, amtMER);
        return IMBep20(MMER).mint(amtMER);
    }

    function redeemMMER_(uint amtMMER) external governance returns(uint) {
        return IMBep20(_MMER_.getA()).redeem(amtMMER);
    }
}


interface IMBep20 {
    function borrowBalanceCurrent(address account) external returns (uint);
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    //function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    //function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    //function liquidateBorrow(address borrower, uint repayAmount, MTokenInterface mTokenCollateral) external returns (uint);
    //function sweepToken(EIP20NonStandardInterface token) external;
    //function _addReserves(uint addAmount) external returns (uint);
}

interface IComptroller {
    function borrowAllowed(address cToken, address borrower, uint borrowAmount) external returns (uint);
    function repayBorrowAllowed(address cToken, address payer, address borrower, uint repayAmount) external returns (uint);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        payable
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
}