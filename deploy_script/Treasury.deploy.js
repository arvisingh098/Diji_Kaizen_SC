const { ethers, upgrades } = require("hardhat");
require('dotenv').config();

async function main() {
  // Get the contract factory
  const TreasuryContract = await ethers.getContractFactory("Treasury");

  // Deploy the proxy contract
  console.log("Deploying TreasuryContract...");
  const contract = await upgrades.deployProxy(TreasuryContract, [process.env.SUPER_ADMIN_ADDRESS], {});

  console.log("TreasuryContract deployed to:", contract.target);
}

// Run the deployment script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });