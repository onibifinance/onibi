// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/*
- / _ \    _ _       (_)    | |__      (_)
 | (_) |  | ' \      | |    | '_ \     | |
  \___/   |_||_|    _|_|_   |_.__/    _|_|_
_|"""""| _|"""""| _|"""""| _|"""""| _|"""""|
"`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-'
*/

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./OniPool.sol";
import "./library/WETH9.sol";

contract BorrowHelper {
    WETH9 public weth;
    IERC20 public bean;
    OniPool public oniPool;

    constructor(
        OniPool _oniPool,
        IERC20 _bean,
        WETH9 _weth
    ) {
        weth = _weth;
        bean = _bean;
        oniPool = _oniPool;
    }

    function borrow(uint256 _beanAmount) external payable {
        uint256 ethValue = msg.value;

        // deposit WETH
        weth.deposit{value: ethValue}();

        weth.approve(address(oniPool), 0);
        weth.approve(address(oniPool), ethValue);

        oniPool.borrow(msg.sender, ethValue, _beanAmount);
    }
}
