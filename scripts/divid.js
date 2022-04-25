const hre = require("hardhat");

async function main() {

  // distributor
  // await hre.run("verify:verify", {
  //   address: "0xA2Ccfdc844E6dA4721597c63e3b6Bff78922c8fd",
  //   constructorArguments: [],
  //   libraries: {
  //       IterableMapping: "0x4668635559d12e0e18aeF9F564Ff4DF726c03774"
  //     },
  // });

 // manager 
  // const manager = await hre.ethers.getContractFactory("RewardPoolManager");
  // const managerInstance = await manager.deploy("0xA2Ccfdc844E6dA4721597c63e3b6Bff78922c8fd");
  // await managerInstance.deployed();
  // console.log("apeborg deployed to:", managerInstance.address); 
  //  await hre.run("verify:verify", {
  //   address: managerInstance.address,
  //   constructorArguments: ["0xA2Ccfdc844E6dA4721597c63e3b6Bff78922c8fd"],
  // });


  // reward pool

   await hre.run("verify:verify", {
    address: "0xbFA7B694A61e9E610FC8Dad38a9957f3e73e6ff7",
    constructorArguments: ["0x6F240078CD4B64B328a8828b4A6Fbba837Bbd506","0xdCecd5D2DB01C1d22a1238F57D62d7F86Faa1CA6"],
  });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
