const hre = require("hardhat");

async function main() {
  // const APEBORG = await hre.ethers.getContractFactory("ShiborgInuEther");
  // const apeborg = await APEBORG.deploy();

  // await apeborg.deployed();

  // console.log("apeborg deployed to:", apeborg.address);

  await hre.run("verify:verify", {
    address: "0x035568502be9a6af32d04a5c8d9fd8bcf70ae9e1",
    constructorArguments: [],
  });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
