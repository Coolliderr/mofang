require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const PRIVATE_KEY = process.env.PRIVATE_KEY.trim(); // ✅ 去掉多余空格或换行

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    }
  },
  networks: {
    polygon: {
      url: process.env.POLYGON_RPC,
      accounts: [`0x${PRIVATE_KEY}`], // ✅ 手动加0x
      chainId: 137
    }
  },
  etherscan: {
    apiKey: {
      polygon: process.env.POLYGONSCAN_API_KEY
    }
  }
};