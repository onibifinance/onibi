const { ethers, network } = require('hardhat');
const { expect } = require('chai');
const deploy = require('./deploy');
const BigNumber = require('bignumber.js');

let deployment;

describe('OniPool', () => {
  beforeEach(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [],
    });

    deployment = await deploy();
  });

  it('should borrow successfully', async () => {
    const [, , alice, bob] = await ethers.getSigners();

    const beanToSupply = new BigNumber(2000e6); // 2000 BEANs
    const beanToBorrow = new BigNumber(1000e6); // 1000 BEANs
    const wethToDeposit = new BigNumber(1e18); // 1 WETH

    // alice supply some BEANs
    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));

    // bob borrow some BEANs
    await deployment.oniPool.connect(bob).borrow(alice.address, wethToDeposit.toString(10), beanToBorrow.toString(10));
  });

  it('should return correct borrow info', async () => {
    const [, , alice, bob] = await ethers.getSigners();

    const beanToSupply = new BigNumber(2000e6); // 2000 BEANs
    const beanToBorrow = new BigNumber(1000e6); // 1000 BEANs
    const wethToDeposit = new BigNumber(1e18); // 1 WETH

    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));
    await deployment.oniPool.connect(bob).borrow(bob.address, wethToDeposit.toString(10), beanToBorrow.toString(10));

    const accountBorrowInfo = await deployment.oniPool.getAccountBorrowInfo(bob.address);
    expect(accountBorrowInfo.assetValueInBeans_.toString()).equal(new BigNumber(1300e6).toString(10));
    expect(accountBorrowInfo.debtsBeans_.toString()).equal(new BigNumber(1000e6).toString(10));
    expect(accountBorrowInfo.availableBeans_.toString()).equal(new BigNumber(170e6).toString(10));
    expect(accountBorrowInfo.health_.toString()).equal(
      new BigNumber(1170e6).multipliedBy(1e6).dividedBy(new BigNumber(1000e6)).toString(10).split('.')[0]
    );
  });

  it('should return correct balances', async () => {
    const [, treasury, , bob, borrower] = await ethers.getSigners();

    const beanToSupply = new BigNumber(2000e6); // 2000 BEANs
    const beanToBorrow = new BigNumber(1000e6); // 1000 BEANs
    const wethToDeposit = new BigNumber(1e18); // 1 WETH

    await deployment.oniBean.connect(bob).mint(beanToSupply.toString(10));
    await deployment.oniPool
      .connect(bob)
      .borrow(borrower.address, wethToDeposit.toString(10), beanToBorrow.toString(10));

    const beanBalance = await deployment.tokens.BEAN.balanceOf(borrower.address);
    const treasuryFees = await deployment.tokens.BEAN.balanceOf(treasury.address);
    const oniBeanBalance = await deployment.tokens.BEAN.balanceOf(deployment.oniBean.address);
    const oniBeanDebts = await deployment.oniBean.totalDebts();
    const oniBeanRate = await deployment.oniBean.getRate();
    expect(beanBalance.toString()).equal('985000000');
    expect(treasuryFees.toString()).equal('1500000');
    expect(oniBeanBalance.toString()).equal('1013500000');
    expect(oniBeanDebts.toString()).equal('1000000000');
    expect(oniBeanRate.toString()).equal('1006750'); // 2013.5 / 2000
  });

  it('should repay correctly', async () => {
    const [, , , bob] = await ethers.getSigners();

    const beanToSupply = new BigNumber(2000e6); // 2000 BEANs
    const beanToBorrow = new BigNumber(1000e6); // 1000 BEANs
    const wethToDeposit = new BigNumber(1e18); // 1 WETH

    await deployment.oniBean.connect(bob).mint(beanToSupply.toString(10));
    await deployment.oniPool.connect(bob).borrow(bob.address, wethToDeposit.toString(10), beanToBorrow.toString(10));

    const accountBorrowInfo = await deployment.oniPool.getAccountBorrowInfo(bob.address);
    expect(accountBorrowInfo.debtsBeans_.toString()).equal(new BigNumber(1000e6).toString(10));

    await deployment.oniPool.connect(bob).repay(beanToBorrow.toString(10));

    const beanBalance = await deployment.tokens.BEAN.balanceOf(deployment.oniBean.address);
    expect(beanBalance.toString()).equal('2013500000');
  });
});
