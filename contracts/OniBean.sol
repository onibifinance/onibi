// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/*
- / _ \    _ _       (_)    | |__      (_)
 | (_) |  | ' \      | |    | '_ \     | |
  \___/   |_||_|    _|_|_   |_.__/    _|_|_
_|"""""| _|"""""| _|"""""| _|"""""| _|"""""|
"`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-' "`-0-0-'
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

// Supply BEAN into Pool, get oniBEAN
// Burn oniBEAN, get BEAN + interest
contract OniBean is Ownable, ERC20Votes, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string private constant POOL_NAME = "OniBean";
    string private constant POOL_SYMBOL = "oniBEAN";
    // the same decimals with BEAN
    uint8 private constant POOL_DECIMALS = 6;

    // @dev track total BEAN debts
    uint256 public totalDebts;

    // @dev BEAN token address
    address public immutable bean;

    // @dev poll address => permission
    mapping(address => bool) public poolPermissions;

    // @dev emit when suppliers supply BEAN
    event Mint(address indexed supplier, uint256 indexed bean, uint256 indexed oniBean);
    // @dev emit when suppliers withdraw BEAN
    event Burn(address indexed supplier, uint256 indexed bean, uint256 indexed oniBean);

    // @dev emit when pool permission granted
    event Granted(address indexed pool, bool permission);

    modifier onlyPool() {
        require(poolPermissions[msg.sender], "!pool");
        _;
    }

    constructor(address _bean) ERC20(POOL_NAME, POOL_SYMBOL) ERC20Permit(POOL_NAME) {
        bean = _bean;
    }

    function decimals() public view virtual override returns (uint8) {
        return POOL_DECIMALS;
    }

    // @dev TotalBean = BeanBalance + BeanDebts
    function getBalance() public view returns (uint256) {
        return IERC20(bean).balanceOf(address(this)).add(totalDebts);
    }

    // @dev how many BEAN per oniBEAN?
    function getRate() public view returns (uint256) {
        if (totalSupply() == 0) return 1e6; // 1 BEAN
        return getBalance().mul(1e6).div(totalSupply());
    }

    // @dev mint oniBEAN
    function mint(uint256 _amountBean) external nonReentrant {
        uint256 rate = getRate();
        uint256 amountToMint = _amountBean.mul(1e6).div(rate);
        _mint(msg.sender, amountToMint);

        IERC20(bean).safeTransferFrom(msg.sender, address(this), _amountBean);

        emit Mint(msg.sender, _amountBean, amountToMint);
    }

    // @dev burn oniBEAN, get BEAN
    function burn(uint256 _amountOniBean) external nonReentrant {
        uint256 rate = getRate();
        uint256 amountBean = _amountOniBean.mul(rate).div(1e6);
        _burn(msg.sender, _amountOniBean);

        IERC20(bean).safeTransfer(msg.sender, amountBean);

        emit Burn(msg.sender, amountBean, _amountOniBean);
    }

    // @dev pools borrow BEAN, issue debts
    function poolBorrow(uint256 _amountBean) external onlyPool {
        IERC20(bean).safeTransfer(msg.sender, _amountBean);

        totalDebts = totalDebts.add(_amountBean);
    }

    // @dev pools repay BEAN, reduce debts
    function poolRepay(uint256 _amountBean) external onlyPool {
        IERC20(bean).safeTransferFrom(msg.sender, address(this), _amountBean);

        totalDebts = totalDebts.sub(_amountBean);
    }

    // @dev set pool permission
    function setPoolPermission(address _pool, bool _permission) external onlyOwner {
        poolPermissions[_pool] = _permission;

        emit Granted(_pool, _permission);
    }
}
