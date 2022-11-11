const { ethers } = require('hardhat');
const BigNumber = require('bignumber.js');

module.exports = async function deploy() {
  const [deployer, treasury, alice, bob] = await ethers.getSigners();

  // BEAN
  const Token = await ethers.getContractFactory('Token');
  const BEAN = await Token.connect(deployer).deploy('BEAN', 'BEAN', 6);
  await BEAN.deployed();
  // WETH
  const WETH9 = await ethers.getContractFactory('WETH9');
  const WETH = await WETH9.connect(deployer).deploy();
  await WETH.deployed();

  const MockChainLinkFeed = await ethers.getContractFactory('MockChainLinkFeed');
  const wethFeed = await MockChainLinkFeed.connect(deployer).deploy(1300e8); // $1300
  await wethFeed.deployed();
  const wbtcFeed = await MockChainLinkFeed.connect(deployer).deploy(20000e8); // $20000
  await wbtcFeed.deployed();

  const OniBean = await ethers.getContractFactory('OniBean');
  const oniBean = await OniBean.connect(deployer).deploy(BEAN.address);
  await oniBean.deployed();

  const OnibiAdmin = await ethers.getContractFactory('OnibiAdmin');
  const proxyAdmin = await OnibiAdmin.connect(deployer).deploy();
  await proxyAdmin.deployed();

  const OniPool = await ethers.getContractFactory('OniPool');
  const oniPoolImpl = await OniPool.connect(deployer).deploy();
  await oniPoolImpl.deployed();

  const TransparentUpgradeableProxy = await ethers.getContractFactory('TransparentUpgradeableProxy');
  const initializeData = OniPool.interface.encodeFunctionData('initialize', [
    BEAN.address,
    oniBean.address,
    WETH.address,
    wethFeed.address,
    treasury.address,
    '0', // borrow base rate
    '0', // optimal U
    '0', // rSlope1
    '0', // rSlope2
  ]);
  const oniPoolProxy = await TransparentUpgradeableProxy.connect(deployer).deploy(
    oniPoolImpl.address,
    proxyAdmin.address,
    initializeData
  );
  await oniPoolProxy.deployed();

  const oniPool = await ethers.getContractAt('OniPool', oniPoolProxy.address);

  const BorrowHelper = await ethers.getContractFactory('BorrowHelper');
  const borrowHelper = await BorrowHelper.connect(deployer).deploy(oniPool.address, BEAN.address, WETH.address);
  await borrowHelper.deployed();

  // grant permissions
  await oniBean.connect(deployer).setPoolPermission(deployer.address, true); // for testing
  await oniBean.connect(deployer).setPoolPermission(oniPool.address, true);

  // addition step, mint token and approve
  await BEAN.mint(alice.address, new BigNumber(1000000e6).toString(10));
  await BEAN.mint(bob.address, new BigNumber(1000000e6).toString(10));

  await WETH.connect(alice).deposit({
    value: new BigNumber(1000e18).toString(10),
  });
  await WETH.connect(bob).deposit({
    value: new BigNumber(1000e18).toString(10),
  });

  await BEAN.connect(alice).approve(oniBean.address, ethers.constants.MaxUint256.toString());
  await BEAN.connect(bob).approve(oniBean.address, ethers.constants.MaxUint256.toString());
  await BEAN.connect(alice).approve(oniPool.address, ethers.constants.MaxUint256.toString());
  await BEAN.connect(bob).approve(oniPool.address, ethers.constants.MaxUint256.toString());
  await WETH.connect(alice).approve(oniPool.address, ethers.constants.MaxUint256.toString());
  await WETH.connect(bob).approve(oniPool.address, ethers.constants.MaxUint256.toString());
  await WETH.connect(alice).approve(borrowHelper.address, ethers.constants.MaxUint256.toString());
  await WETH.connect(bob).approve(borrowHelper.address, ethers.constants.MaxUint256.toString());

  return {
    tokens: {
      BEAN,
      WETH,
    },
    feeds: {
      wethFeed,
      wbtcFeed,
    },
    proxyAdmin,
    oniBean,
    oniPool,
    borrowHelper,
  };
};
