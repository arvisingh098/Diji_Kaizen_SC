require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config()

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  networks:{
    berachain:{
      url:process.env.RPC_URL,
      accounts:[process.env.DEPLOYER_PRIVATE_KEY]
    }
  },
  etherscan:{
    apiKey:process.env.API_KEY
  }
};
