const { ethers, network } = require('hardhat');
const { expect } = require('chai');
const deploy = require('./deploy');
const BigNumber = require('bignumber.js');

let deployment;

describe('BorrowHelper', () => {
  beforeEach(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [],
    });

    deployment = await deploy();
  });

  it('should borrow successfully', async () => {
    const [, , alice, , borrower] = await ethers.getSigners();

    const beanToSupply = new BigNumber(2000e6); // 2000 BEANs
    const beanToBorrow = new BigNumber(1000e6); // 1000 BEANs
    const wethToDeposit = new BigNumber(1e18); // 1 WETH

    // alice supply some BEANs
    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));

    // bob borrow some BEANs
    await deployment.borrowHelper
      .connect(borrower)
      .borrow(beanToBorrow.toString(10), { value: wethToDeposit.toString(10) });
    const beanBalance = await deployment.tokens.BEAN.balanceOf(borrower.address);
    expect(beanBalance.toString()).equal('985000000');
  });
});
