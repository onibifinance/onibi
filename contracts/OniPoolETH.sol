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
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./OniPool.sol";
import "./library/WETH9.sol";

contract OniPoolETH is OniPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // @dev for receive ether
    receive() external payable {}

    // @dev borrowers supply asset and borrow BEAN
    // contract allow to borrow up-to 90% asset value
    // consider set beanAmount to a lower value for safe from liquidation
    // if you want to add more asset only, please set beanAmount to zero
    function borrow(
        address _borrower,
        uint256,
        uint256 _beanAmount
    ) external payable override nonReentrant {
        if (msg.value > 0) {
            // update asset info
            totalDeposited = totalDeposited.add(msg.value);
            accountInfo[_borrower].totalAsset = accountInfo[_borrower].totalAsset.add(msg.value);

            // deposit WETH
            WETH9(assetInfo.token).deposit{value: msg.value}();
        }

        uint256 beanAmount_;
        uint256 feesAmount_;
        if (_beanAmount > 0) {
            (beanAmount_, feesAmount_) = _borrowBean(_borrower, _beanAmount);
        }

        emit Borrow(_borrower, msg.value, beanAmount_, feesAmount_);
    }

    // @dev borrowers repay BEAN, return asset if repay all debts
    function repay(uint256 _beanAmount) external override nonReentrant {
        _beanAmount = Math.min(_beanAmount, accountInfo[msg.sender].totalDebts);

        // update debts
        totalDebts = totalDebts.sub(_beanAmount);
        accountInfo[msg.sender].totalDebts = accountInfo[msg.sender].totalDebts.sub(_beanAmount);

        IERC20(bean).safeTransferFrom(msg.sender, address(this), _beanAmount);
        IERC20(bean).approve(oniBean, 0);
        IERC20(bean).approve(oniBean, _beanAmount);
        OniBean(oniBean).poolRepay(_beanAmount);

        // withdraw asset if clean debts
        if (accountInfo[msg.sender].totalDebts == 0) {
            // withdraw from WETH
            WETH9(assetInfo.token).withdraw(accountInfo[msg.sender].totalAsset);
            payable(address(msg.sender)).transfer(accountInfo[msg.sender].totalAsset);

            totalDeposited = totalDeposited.sub(accountInfo[msg.sender].totalAsset);
            accountInfo[msg.sender].totalAsset = 0;
        }

        emit Repay(msg.sender, _beanAmount);
    }
}
