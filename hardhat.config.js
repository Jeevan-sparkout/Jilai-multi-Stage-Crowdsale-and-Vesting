require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config();

const { RPC, PRIVATE_KEY, ETHERSCAN_API } = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.30",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
        viaIR: true ,
    },
  },
  networks: {
    sepolia: {
      url: RPC,
      accounts: [PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_API,
    },
  },
  sourcify: {
    enabled: true,
  },
};