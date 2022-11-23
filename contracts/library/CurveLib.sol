// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/*
- / _ \    _ _       (_)    | |__      (_)
 | (_) |  | ' \      | |    | '_ \     | |
  \___/   |_||_|    _|_|_   |_.__/    _|_|_
_|"""""| _|"""""| _|"""""| _|"""""| _|"""""|
"`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-'
*/

interface CurveExchange {
    function add_liquidity(uint256[3] memory amounts, uint256 minAmount) external;

    function exchange(
        uint256 fromToken,
        uint256 toToken,
        uint256 amount,
        uint256 minAmount
    ) external;
}

interface CurveExchangeETH {
    function exchange(
        uint256 fromToken,
        uint256 toToken,
        uint256 amount,
        uint256 minAmount,
        bool useETH
    ) external payable;
}
