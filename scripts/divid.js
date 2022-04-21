const hre = require("hardhat");

async function main() {
  // const APEBORG = await hre.ethers.getContractFactory("TOKENDividendTracker");
  // const apeborg = await APEBORG.deploy();

  // await apeborg.deployed();

  // console.log("apeborg deployed to:", apeborg.address);

  await hre.run("verify:verify", {
    address: "0x14C9C3148b55daC74d31e682405e3265daf02089",
    constructorArguments: ["0x273FCf8957467b8B6B058a15f1c46bE91a3d342D"],
  });

  // await hre.run("verify:verify", {
  //   address: "0x273FCf8957467b8B6B058a15f1c46bE91a3d342D",
  //   constructorArguments: [],
  //   libraries: {
  //       IterableMapping: "0xf46427d1F4C28258e559f1C1Af716457f0A94777"
  //     },
  // });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
