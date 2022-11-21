const { ethers, network } = require('hardhat');
const { expect } = require('chai');
const deploy = require('./deploy');
const BigNumber = require('bignumber.js');

let deployment;

describe('Borrow Fees Rate', () => {
  beforeEach(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [],
    });

    deployment = await deploy();
  });

  it('utilization rate should be correct number', async () => {
    const [deployer, , alice] = await ethers.getSigners();

    const beanToSupply = new BigNumber(1000e6); // 1000 BEANs
    const beanLiquidity = new BigNumber(900e6); // 900 BEANs

    // supply some BEANs
    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));

    let beanToBorrow = new BigNumber(0);
    while (beanToBorrow.lte(beanLiquidity)) {
      const expectedUtilizationRate = beanToBorrow
        .multipliedBy(1e18)
        .dividedBy(beanLiquidity)
        .toString(10)
        .split('.')[0];
      const utilizationRate = await deployment.oniPool.getUtilizationRate();

      expect(new BigNumber(utilizationRate.toString()).toString(10)).equal(expectedUtilizationRate);

      // deployer borrow 1 BEANs, this step in test env only!
      await deployment.oniBean.connect(deployer).poolBorrow('10000000');

      beanToBorrow = beanToBorrow.plus(10000000);
    }
  });

  it('uOptimal: 60%, borrowBase: 1.5%, rSlope1: 1%, rSlope2: 80%', async () => {
    const [deployer, , alice] = await ethers.getSigners();

    const beanToSupply = new BigNumber(1000e6); // 1000 BEANs
    const beanLiquidity = new BigNumber(900e6); // 900 BEANs

    const borrowBase = new BigNumber(15e15); // 1.5%
    const uOptimal = new BigNumber(60e16); // 60%
    const rSlope1 = new BigNumber(1e16); // 1%
    const rSlope2 = new BigNumber(80e16); // 80%

    // supply some BEANs
    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));

    let beanToBorrow = new BigNumber(0);
    while (beanToBorrow.lte(beanLiquidity)) {
      const utilizationRate = new BigNumber(
        beanToBorrow.multipliedBy(1e18).dividedBy(beanLiquidity).toString(10).split('.')[0]
      );

      let expectedBorrowFeesRate = new BigNumber(0);
      if (utilizationRate.lt(uOptimal)) {
        expectedBorrowFeesRate = borrowBase.plus(utilizationRate.multipliedBy(rSlope1).dividedBy(uOptimal));
      } else {
        expectedBorrowFeesRate = borrowBase
          .plus(rSlope1)
          .plus(utilizationRate.minus(uOptimal).multipliedBy(rSlope2).dividedBy(new BigNumber(1e18).minus(uOptimal)));
      }

      expectedBorrowFeesRate = expectedBorrowFeesRate.toString(10).split('.')[0];

      const borrowFeesRate = await deployment.oniPool.getBorrowFees();

      expect(new BigNumber(borrowFeesRate.toString()).toString(10)).equal(expectedBorrowFeesRate);

      // deployer borrow 1 BEANs, this step in test env only!
      await deployment.oniBean.connect(deployer).poolBorrow('10000000');
      beanToBorrow = beanToBorrow.plus(10000000);
    }
  });

  it('uOptimal: 80%, borrowBase: 2%, rSlope1: 0.05%, rSlope2: 75%', async () => {
    const [deployer, , alice] = await ethers.getSigners();

    const beanToSupply = new BigNumber(1000e6); // 1000 BEANs
    const beanLiquidity = new BigNumber(900e6); // 900 BEANs

    const borrowBase = new BigNumber(2e16); // 2%
    const uOptimal = new BigNumber(80e16); // 80%
    const rSlope1 = new BigNumber(5e14); // 0.05%
    const rSlope2 = new BigNumber(75e16); // 75%

    // adjust interest model
    await deployment.oniPool
      .connect(deployer)
      .setInterestParams(uOptimal.toString(10), borrowBase.toString(10), rSlope1.toString(10), rSlope2.toString(10));

    // supply some BEANs
    await deployment.oniBean.connect(alice).mint(beanToSupply.toString(10));

    let beanToBorrow = new BigNumber(0);
    while (beanToBorrow.lte(beanLiquidity)) {
      const utilizationRate = new BigNumber(
        beanToBorrow.multipliedBy(1e18).dividedBy(beanLiquidity).toString(10).split('.')[0]
      );

      let expectedBorrowFeesRate = new BigNumber(0);
      if (utilizationRate.lt(uOptimal)) {
        expectedBorrowFeesRate = borrowBase.plus(utilizationRate.multipliedBy(rSlope1).dividedBy(uOptimal));
      } else {
        expectedBorrowFeesRate = borrowBase
          .plus(rSlope1)
          .plus(utilizationRate.minus(uOptimal).multipliedBy(rSlope2).dividedBy(new BigNumber(1e18).minus(uOptimal)));
      }

      expectedBorrowFeesRate = expectedBorrowFeesRate.toString(10).split('.')[0];

      const borrowFeesRate = await deployment.oniPool.getBorrowFees();

      expect(new BigNumber(borrowFeesRate.toString()).toString(10)).equal(expectedBorrowFeesRate);

      // deployer borrow 1 BEANs, this step in test env only!
      await deployment.oniBean.connect(deployer).poolBorrow('10000000');
      beanToBorrow = beanToBorrow.plus(10000000);
    }
  });
});
