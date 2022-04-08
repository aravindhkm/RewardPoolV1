const hre = require("hardhat");

async function main() {
  let marketWallet = "0x98396fF397f78350BD40Ee70972B47A929E5CFE7";
  let tresuryWallet = "0x8077Dcdd2388F46725b7BE3259dAFc936558300e";
  const CreedDao = await hre.ethers.getContractFactory("CreedDao");
  const creedDao = await CreedDao.deploy(marketWallet,tresuryWallet);

  await creedDao.deployed();

  console.log("creedDao deployed to:", creedDao.address);

  await hre.run("verify:verify", {
    address: creedDao.address,
    constructorArguments: [marketWallet,tresuryWallet],
  });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
