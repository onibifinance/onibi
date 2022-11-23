// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/*
- / _ \    _ _       (_)    | |__      (_)
 | (_) |  | ' \      | |    | '_ \     | |
  \___/   |_||_|    _|_|_   |_.__/    _|_|_
_|"""""| _|"""""| _|"""""| _|"""""| _|"""""|
"`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-'
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./library/CurveLib.sol";

contract Swapper is Initializable {
    address private constant CURVE_ETH_WBTC_USDT_POOL = address(0xD51a44d3FaE010294C616388b506AcdA1bfAAE46);
    address private constant CURVE_3CRV_POOL = address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    address private constant CURVE_BEAN_3CRV_POOL = address(0xc9C32cd16Bf7eFB85Ff14e0c8603cc90F6F2eE49);
    address private constant USDT = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address private constant BEAN = address(0xBEA0000029AD1c77D3d5D23Ba2D8893dB9d1Efab);

    function initialize() external initializer {}

    receive() external payable {}

    function sellAsset() external payable {
        // receive ETH from sender
        uint256 amount = msg.value;
        if (amount == 0) return;

        // swap ETH to USDT
        CurveExchangeETH(CURVE_ETH_WBTC_USDT_POOL).exchange{value: amount}(2, 1, amount, 0, true);

        // approve USDT
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));

        if (usdtBalance > 0) {
            IERC20(USDT).approve(CURVE_3CRV_POOL, 0);
            IERC20(USDT).approve(CURVE_3CRV_POOL, usdtBalance);

            // add USDT liquidity
            CurveExchange(CURVE_3CRV_POOL).add_liquidity([0, 0, usdtBalance], 0);

            uint256 crv3Balance = IERC20(CURVE_3CRV_POOL).balanceOf(address(this));

            // swap crv3 to BEAN
            CurveExchange(CURVE_BEAN_3CRV_POOL).exchange(1, 0, crv3Balance, 0);

            IERC20(BEAN).transfer(msg.sender, IERC20(BEAN).balanceOf(address(this)));
        }
    }
}
