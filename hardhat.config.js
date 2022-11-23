require("hardhat-gas-reporter");
require("@nomiclabs/hardhat-waffle");

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      forking: {
        url: 'https://rpc.ankr.com/eth',
        blockNumber: 16034276,
      }
    },
  },
  mocha: {
    timeout: 0
  },
  solidity: {
    compilers: [
      {
        version: "0.8.15",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  gasReporter: {
    token: 'ETH',
    gasPriceApi: 'https://api.etherscan.io/api?module=proxy&action=eth_gasPrice',
    enabled: true,
    currency: 'USD',
    gasPrice: 30000000000,
    noColors: true,
    outputFile: './GasReport.txt'
  }
};
