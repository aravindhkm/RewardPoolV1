const hre = require("hardhat");

async function main() {
  // const APEBORG = await hre.ethers.getContractFactory("ShiborgInuEther");
  // const apeborg = await APEBORG.deploy();

  // await apeborg.deployed();

  // console.log("apeborg deployed to:", apeborg.address);

  await hre.run("verify:verify", {
    address: "0xEF1E51D1A4800B4E5e0ecE10A74376598b2642c7",
    constructorArguments: [],
  });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
