const hre = require("hardhat");

async function main() {

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
  // const managerInstance = await manager.deploy("0x83Da199702574826EA2880D94Be19503Bfc19D45");
  // await managerInstance.deployed();
  // console.log("apeborg deployed to:", managerInstance.address); 
  //  await hre.run("verify:verify", {
  //   address: managerInstance.address,
  //   constructorArguments: ["0x83Da199702574826EA2880D94Be19503Bfc19D45"],
  // });


  // reward pool

   await hre.run("verify:verify", {
    address: "0x268d9A62B4bAb315a91d1668A7ebA3E60deD974B",
    constructorArguments: ["0xc45968a401633d16cF03d206058905Fda012B269","0x17Ca0928871b2dB9dd3B2f8b27148a436C24Baa8"],
  });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
