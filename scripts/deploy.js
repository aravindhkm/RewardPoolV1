const hre = require("hardhat");

async function main() {
  // const APEBORG = await hre.ethers.getContractFactory("EnrollContract");
  // const apeborg = await APEBORG.deploy();

  // await apeborg.deployed();

  // console.log("apeborg deployed to:", apeborg.address);

  await hre.run("verify:verify", {
    address: "0xfC49c2862CFe8421B983e680732584a01a34CbBb",
    constructorArguments: [],
  });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
