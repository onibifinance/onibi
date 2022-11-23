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
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./OniBean.sol";
import "./library/WETH9.sol";
import "./library/ChainLinkFeed.sol";

contract OniPoolETH is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant BASE_RATE = 1e18;

    // interest model
    uint256 private constant DEFAULT_BORROW_BASE_RATE = 15e15; // 1.5%
    uint256 private constant DEFAULT_OPTIMAL_UTILIZATION_RATE = 60e16; // 60%
    uint256 private constant DEFAULT_R_SLOPE_1 = 1e16; // 1%
    uint256 private constant DEFAULT_R_SLOPE_2 = 80e16; // 80%

    // reserve rate
    uint256 private constant RESERVE_RATE = 10e16; // 10%

    // borrow up-to COLLATERAL_RATE collateral asset USD value
    uint256 private constant COLLATERAL_RATE = 90e16; // 90%

    // treasury fees
    uint256 private constant TREASURY_FEE_RATE = 10e16; // 10% borrow fees

    // liquidation fees
    uint256 private constant LIQUIDATION_PENALTY = 1e16; // 1% borrowing position

    struct InterestParams {
        uint256 borrowBaseRate;
        uint256 optimalUtilizationRate;
        uint256 rSlope1;
        uint256 rSlope2;
    }

    struct AssetInfo {
        // asset token address
        address token;
        // chainlink price feed
        address priceFeed;
    }

    struct AccountInfo {
        // total asset supplied
        uint256 totalAsset;
        // total BEAN borrowed
        uint256 totalDebts;
    }

    // @dev trac total deposited asset
    uint256 public totalDeposited;

    // @dev track total borrowed BEAN exclude fees
    uint256 public totalDebts;

    // @dev BEAN token address
    address public bean;

    // @dev oniBEAN token address
    address public oniBean;

    // @dev treasury address
    address public treasury;

    // @dev interest model parameters
    InterestParams public interestParams;

    // @dev collateral asset info
    AssetInfo public assetInfo;

    // @dev account => AccountInfo
    mapping(address => AccountInfo) public accountInfo;

    event Borrow(address indexed borrower, uint256 assetAmount, uint256 beanAmount, uint256 feesAmount);
    event Repay(address indexed borrower, uint256 repayAmount);
    event Liquidate(address indexed liquidator, address indexed borrower, uint256 debtsAmount, uint256 feesAmount);

    // @dev for receive ether
    receive() external payable {}

    function initialize(
        address _bean,
        address _oniBean,
        address _asset,
        address _assetPriceFeed,
        address _treasury,
        uint256 _borrowBaseRate,
        uint256 _optimalUtilizationRate,
        uint256 _rSlope1,
        uint256 _rSlope2
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        bean = _bean;
        oniBean = _oniBean;
        assetInfo.token = _asset;
        assetInfo.priceFeed = _assetPriceFeed;
        treasury = _treasury;

        interestParams.borrowBaseRate = _borrowBaseRate == 0 ? DEFAULT_BORROW_BASE_RATE : _borrowBaseRate;
        interestParams.optimalUtilizationRate = _optimalUtilizationRate == 0
            ? DEFAULT_OPTIMAL_UTILIZATION_RATE
            : _optimalUtilizationRate;
        interestParams.rSlope1 = _rSlope1 == 0 ? DEFAULT_R_SLOPE_1 : _rSlope1;
        interestParams.rSlope2 = _rSlope2 == 0 ? DEFAULT_R_SLOPE_2 : _rSlope2;
    }

    // @dev return BEAN liquidity info
    function getLiquidityInfo()
        public
        view
        returns (
            uint256 balance_,
            uint256 reserve_,
            uint256 available_,
            uint256 debts_
        )
    {
        balance_ = OniBean(oniBean).getBalance();
        debts_ = OniBean(oniBean).totalDebts();

        // ReserveAmount = TotalBalance * RESERVE_RATE
        reserve_ = balance_.mul(RESERVE_RATE).div(BASE_RATE);
        // AvailableAmount = TotalBalance - DebtsAmount - ReserveAmount
        available_ = balance_.sub(reserve_).sub(debts_);
    }

    // @dev return utilization rate
    function getUtilizationRate() public view returns (uint256) {
        (uint256 balance_, uint256 reserve_, , uint256 debts_) = getLiquidityInfo();
        if (balance_ == 0) return 0;

        // Utilization = Debts / Liquidity
        uint256 liquidity = balance_.sub(reserve_);
        return debts_.mul(1e18).div(liquidity);
    }

    // @dev return borrow fees
    function getBorrowFees() public view returns (uint256) {
        uint256 u = getUtilizationRate();

        uint256 borrowFeesRate;
        if (u < interestParams.optimalUtilizationRate) {
            // r = borrowBaseRate + rSlope1 * U / optimalUtilizationRate
            borrowFeesRate = interestParams.borrowBaseRate.add(
                u.mul(interestParams.rSlope1).div(interestParams.optimalUtilizationRate)
            );
        } else {
            // r = borrowBaseRate + rSlope1 + (U - optimalUtilizationRate) / (1 - optimalUtilizationRate) * rSlope2
            uint256 uAbove = u.sub(interestParams.optimalUtilizationRate);
            uint256 uBelow = BASE_RATE.sub(interestParams.optimalUtilizationRate);
            borrowFeesRate = interestParams.borrowBaseRate.add(interestParams.rSlope1).add(
                uAbove.mul(interestParams.rSlope2).div(uBelow)
            );
        }

        return borrowFeesRate;
    }

    // @dev return asset price USD in asset's decimals
    function getAssetPriceUSD() public view returns (uint256) {
        (, int256 price, , , ) = ChainLinkFeed(assetInfo.priceFeed).latestRoundData();
        uint8 feedDecimals = ChainLinkFeed(assetInfo.priceFeed).decimals();
        uint8 assetDecimals = ERC20(assetInfo.token).decimals();

        return uint256(price).mul(10**assetDecimals).div(10**feedDecimals);
    }

    // @dev return amount of BEAN can be borrowed with amount of asset
    function getAssetQuota(uint256 _assetAmount) public view returns (uint256) {
        uint256 priceUSD = getAssetPriceUSD();
        uint8 assetDecimals = ERC20(assetInfo.token).decimals();

        // BeanAmount = AssetAmount * AssetPriceUSD * CollateralRate / BaseRate
        uint256 beanAmount = _assetAmount.mul(priceUSD).mul(COLLATERAL_RATE).div(BASE_RATE).div(BASE_RATE);
        return beanAmount.mul(1e6).div(10**assetDecimals);
    }

    // @dev return account borrow info
    function getAccountBorrowInfo(address _borrower)
        public
        view
        returns (
            uint256 assetValueInBeans_,
            uint256 availableBeans_,
            uint256 debtsBeans_,
            uint256 health_
        )
    {
        uint8 assetDecimals = ERC20(assetInfo.token).decimals();

        // valuation of asset in BEANS with 6 decimals
        assetValueInBeans_ = accountInfo[_borrower]
            .totalAsset
            .mul(getAssetPriceUSD())
            .mul(1e6)
            .div(10**assetDecimals)
            .div(10**assetDecimals);

        debtsBeans_ = accountInfo[_borrower].totalDebts;

        // MaximumBorrowBean = AssetValueUSD * COLLATERAL_RATE
        uint256 maximumBorrowBean = assetValueInBeans_.mul(COLLATERAL_RATE).div(1e18);

        // AvailableBeans = MaximumBorrowBean - DebtsBeans | 6 decimals
        availableBeans_ = maximumBorrowBean > debtsBeans_ ? maximumBorrowBean.sub(debtsBeans_) : 0;

        // Health = MaximumBorrowBean / DebtsBeans
        // 0 < Health < 1 ==> liquidation risk
        health_ = debtsBeans_ > 0 ? maximumBorrowBean.mul(1e6).div(debtsBeans_) : 0;
    }

    // @dev borrowers supply asset and borrow BEAN
    // contract allow to borrow up-to 90% asset value
    // consider set beanAmount to a lower value for safe from liquidation
    // if you want to add more asset only, please set beanAmount to zero
    function borrow(address _borrower, uint256 _beanAmount) external payable nonReentrant {
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
    function repay(uint256 _beanAmount) external nonReentrant {
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

    // @dev liquidate borrowing position
    // liquidator transfers BEAN and repay borrowing debts
    // liquidator receive 100% collateral asset of borrowing position
    function liquidate(address _borrower) external nonReentrant {
        (, , uint256 debtsBeans_, uint256 health_) = getAccountBorrowInfo(_borrower);
        require(health_ < 1e6, "not yet");

        uint256 penaltyFees = debtsBeans_.mul(LIQUIDATION_PENALTY).div(1e18);
        uint256 beanAmount = debtsBeans_.add(penaltyFees);

        IERC20(bean).safeTransferFrom(msg.sender, address(this), beanAmount);

        _distributeFees(penaltyFees);

        IERC20(bean).approve(oniBean, 0);
        IERC20(bean).approve(oniBean, debtsBeans_);
        OniBean(oniBean).poolRepay(debtsBeans_);

        IERC20(assetInfo.token).safeTransfer(msg.sender, accountInfo[_borrower].totalAsset);

        delete accountInfo[_borrower];

        emit Liquidate(msg.sender, _borrower, debtsBeans_, penaltyFees);
    }

    function _borrowBean(address _borrower, uint256 _beanAmount)
        internal
        returns (uint256 beanAmount_, uint256 feesAmount_)
    {
        (, uint256 availableBeans_, , ) = getAccountBorrowInfo(_borrower);
        require(_beanAmount <= availableBeans_, "insufficient asset value");

        (, , uint256 available_, ) = getLiquidityInfo();
        require(_beanAmount <= available_, "insufficient liquidity");

        uint256 currentBorrowFeesRate = getBorrowFees();

        // track total fees will be paid
        uint256 feesAmount = _beanAmount.mul(currentBorrowFeesRate).div(1e18);
        uint256 borrowAmount = _beanAmount.sub(feesAmount);

        // update new debts
        totalDebts = totalDebts.add(_beanAmount);
        accountInfo[_borrower].totalDebts = accountInfo[_borrower].totalDebts.add(_beanAmount);

        // request BEAN from oniBean
        OniBean(oniBean).poolBorrow(_beanAmount);

        // transfer BEAN to borrower
        IERC20(bean).safeTransfer(_borrower, borrowAmount);

        // distribute fees
        _distributeFees(feesAmount);

        return (_beanAmount, feesAmount);
    }

    function _distributeFees(uint256 _feesTotal) internal {
        uint256 treasuryAmount = _feesTotal.mul(TREASURY_FEE_RATE).div(BASE_RATE);
        uint256 protocolAmount = _feesTotal.sub(treasuryAmount);

        IERC20(bean).safeTransfer(treasury, treasuryAmount);
        IERC20(bean).safeTransfer(oniBean, protocolAmount);
    }

    // @dev treasury address change
    function setTreasury(address _treasury) external {
        require(treasury == msg.sender, "!treasury");
        treasury = _treasury;
    }

    // @dev governance adjust borrow fee rate parameters
    function setInterestParams(
        uint256 _optimalUtilizationRate,
        uint256 _borrowBaseRate,
        uint256 _rSlope1,
        uint256 _rSlope2
    ) external onlyOwner {
        interestParams.optimalUtilizationRate = _optimalUtilizationRate;
        interestParams.borrowBaseRate = _borrowBaseRate;
        interestParams.rSlope1 = _rSlope1;
        interestParams.rSlope2 = _rSlope2;
    }
}
