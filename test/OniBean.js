const { ethers, network } = require('hardhat');
const { expect } = require('chai');
const deploy = require('./deploy');
const BigNumber = require('bignumber.js');

let deployment;

describe('OniBean', () => {
  beforeEach(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [],
    });

    deployment = await deploy();
  });

  it('should mint/burn successfully', async () => {
    const [, , alice] = await ethers.getSigners();

    const beanToSupply = new BigNumber(1000e6); // 1000 BEANs

    // supply some BEANs
    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));

    // withdraw
    await deployment.oniBean.connect(alice).burn(beanToSupply.toString(10));
  });

  it('should return rate correctly', async () => {
    const [, , alice, bob] = await ethers.getSigners();

    // rate: 1
    const beanToSupply = new BigNumber(1000e6); // 1000 BEANs
    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));
    const rate = await deployment.oniBean.getRate();
    expect(rate.toString()).equal('1000000');

    // rate: 1.1
    const beanToAdd1 = new BigNumber(100e6); // 100 BEANs
    await deployment.tokens.BEAN.connect(alice).transfer(deployment.oniBean.address, beanToAdd1.toString(10));
    const rate1 = await deployment.oniBean.getRate();
    expect(rate1.toString()).equal('1100000');

    const amountOniBean = beanToSupply.multipliedBy(1e6).dividedBy(new BigNumber(rate1.toString()));
    await deployment.oniBean.connect(bob).mint(beanToSupply.toString(10));
    const oniBeanBalance = await deployment.oniBean.balanceOf(bob.address);
    expect(amountOniBean.toString(10).split('.')[0]).equal(oniBeanBalance.toString());
  });

  it('cannot withdraw bean without oniBean', async () => {
    const [, , alice, bob] = await ethers.getSigners();

    const beanToSupply = new BigNumber(1000e6); // 1000 BEANs
    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));

    await expect(deployment.oniBean.connect(bob).burn(beanToSupply.toString())).to.be.revertedWith(
      'ERC20: burn amount exceeds balance'
    );
  });
});
