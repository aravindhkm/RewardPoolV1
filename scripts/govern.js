const hre = require("hardhat");

async function main() {

  let iterableMappingContract;
  let distributorContract = "0x358c1a0d66DDF946c8C9A33Fb0933dE5F1f7411c";
  let managerContract  = "0x35874b41e45Cd2056fEA167812d3f0eC37476349";


  let poolContract;


  // const mapping = await hre.ethers.getContractFactory("MyToken");
  // const IterableMapping = await mapping.deploy();
  // await IterableMapping.deployed();
  // iterableMappingContract = IterableMapping.address;
  // console.log("IterableMapping deployed to:", IterableMapping.address); 
  //  await hre.run("verify:verify", {
  //   address: iterableMappingContract,
  //   constructorArguments: [],
  // });


  //   const mapping = await hre.ethers.getContractFactory("MyGovernor");
  // const IterableMapping = await mapping.deploy();
  // await IterableMapping.deployed();
  // iterableMappingContract = IterableMapping.address;
  // console.log("IterableMapping deployed to:", IterableMapping.address); 
  //  await hre.run("verify:verify", {
  //   address: iterableMappingContract,
  //   constructorArguments: [],
  // });



  // const distributor = await hre.ethers.getContractFactory("RewardDistributor", {
  //   libraries: {
  //     IterableMapping: iterableMappingContract
  //   }});
  // const distributorInstance = await distributor.deploy();
  // await distributorInstance.deployed();
  // distributorContract = distributorInstance.address;
  // console.log("distributorInstance deployed to:", distributorInstance.address); 
  //  await hre.run("verify:verify", {
  //   address: distributorContract,
  //   constructorArguments: [],
  //       libraries: {
  //       IterableMapping: iterableMappingContract
  //     },
  // });

  // distributor
  // await hre.run("verify:verify", {
  //   address: "0x83Da199702574826EA2880D94Be19503Bfc19D45",
  //   constructorArguments: [],
  //   libraries: {
  //       IterableMapping: "0x073E05039C7bdBF9E5A864bBd6ea33Db01A3d83F"
  //     },
  // });

 // manager 
  // const manager = await hre.ethers.getContractFactory("RewardPoolManager");
  // const managerInstance = await manager.deploy(distributorContract);
  // await managerInstance.deployed();
  // managerContract = managerInstance.address;
  // console.log("apeborg deployed to:", managerInstance.address); 
  //  await hre.run("verify:verify", {
  //   address: managerContract,
  //   constructorArguments: [distributorContract],
  // });


  // reward pool

   await hre.run("verify:verify", {
    address: "0x9B530121e0E1F6152364C5A742A029743A7A84C0",
    constructorArguments: [],
  });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
