// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/*
- / _ \    _ _       (_)    | |__      (_)
 | (_) |  | ' \      | |    | '_ \     | |
  \___/   |_||_|    _|_|_   |_.__/    _|_|_
_|"""""| _|"""""| _|"""""| _|"""""| _|"""""|
"`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-'
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./library/CurveLib.sol";

interface UsdtERC20 {
    function approve(address spender, uint value) external;
    function balanceOf(address owner) external view returns (uint);
}

contract Swapper is Initializable {
    address private constant CURVE_ETH_WBTC_USDT_POOL = address(0xD51a44d3FaE010294C616388b506AcdA1bfAAE46);
    address private constant CURVE_3CRV_POOL = address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    address private constant CURVE_3CRV_TOKEN = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
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
        CurveExchangeETH(CURVE_ETH_WBTC_USDT_POOL).exchange{value: amount}(2, 0, amount, 0, true);

        // approve USDT
        uint usdtBalance = IERC20(USDT).balanceOf(address(this));

        if (usdtBalance > 0) {
            UsdtERC20(USDT).approve(CURVE_3CRV_POOL, 0);
            UsdtERC20(USDT).approve(CURVE_3CRV_POOL, usdtBalance);

            // add USDT liquidity
            CurveExchange(CURVE_3CRV_POOL).add_liquidity([0, 0, usdtBalance], 0);

            // swap crv3 to BEAN
            uint256 crv3Balance = IERC20(CURVE_3CRV_TOKEN).balanceOf(address(this));
            IERC20(CURVE_3CRV_TOKEN).approve(CURVE_BEAN_3CRV_POOL, 0);
            IERC20(CURVE_3CRV_TOKEN).approve(CURVE_BEAN_3CRV_POOL, crv3Balance);

            CurveExchange(CURVE_BEAN_3CRV_POOL).exchange(1, 0, crv3Balance, 0);

            IERC20(BEAN).transfer(msg.sender, IERC20(BEAN).balanceOf(address(this)));
        }
    }
}
