// We require the Hardhat Runtime Environment explicitly here. This is optional
const hre = require("hardhat");

async function main() {

  const DLPToken = await hre.ethers.getContractFactory("DLP");
  const dlpToken = await DLPToken.deploy("Decentralized LaunchPool Token","DLP")

  // await nft.deployed();

  console.log("Contract deployed to:", dlpToken.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});