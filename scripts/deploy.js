const hre = require("hardhat");

async function main() {

  let iterableMappingContract = "0x7Be391A30e708494622b39880FF7a239Fe320949";
  let rewardPool = "";
  let goldTokenContract = "";
  let tokenProxyContract  = "";
  let poolProxyContract = "";
  let callDataForToken = "";
  let callDataForPool = "";


  let poolContract;


  // const mapping = await hre.ethers.getContractFactory("IterableMapping");
  // const IterableMapping = await mapping.deploy();
  // await IterableMapping.deployed();
  // iterableMappingContract = IterableMapping.address;
 // console.log("IterableMapping deployed to:", IterableMapping.address); 
  //  await hre.run("verify:verify", {
  //   address: iterableMappingContract,
  //   constructorArguments: [],
  // });

  // const pool = await hre.ethers.getContractFactory("RewardPool", {
  //   libraries: {
  //     IterableMapping: iterableMappingContract
  //   }});
  // const poolInstance = await pool.deploy();
  // await poolInstance.deployed();
  // rewardPool = poolInstance.address;
  // console.log("poolInstance deployed to:", poolInstance.address); 
  //  await hre.run("verify:verify", {
  //   address: rewardPool,
  //   constructorArguments: [],
  //       libraries: {
  //       IterableMapping: iterableMappingContract
  //     },
  // });

  const gToken = await hre.ethers.getContractFactory("GoldenDuckToken");
  const goldTOken = await gToken.deploy();
  await goldTOken.deployed();
  goldTokenContract = goldTOken.address;
  console.log("goldTokenContract deployed to:", goldTokenContract); 
   await hre.run("verify:verify", {
    address: goldTokenContract,
    constructorArguments: [],
  });



  // tokenproxy


  // const tProxy = await hre.ethers.getContractFactory("TokenProxy");
  // const tokenProxy = await tProxy.deploy(goldTokenContract,"0x3d079b51EA706c9a7A40bc62e9CBF836060984Cd",callDataForToken);
  // await tokenProxy.deployed();
  // tokenProxyContract = tokenProxy.address;
  // console.log("IterableMapping deployed to:", tokenProxyContract); 
  //  await hre.run("verify:verify", {
  //   address: "0xD4C3f4D589AF6877D54d620e351108C82E465fD9",
  //   constructorArguments: [goldTokenContract,"0x3d079b51EA706c9a7A40bc62e9CBF836060984Cd",callDataForToken],
  // });

  // pool Proxy

  // const pProxy = await hre.ethers.getContractFactory("RewardPoolProxy");
  // const poolProxy = await pProxy.deploy(rewardPool,"0x3d079b51EA706c9a7A40bc62e9CBF836060984Cd",callDataForPool);
  // await poolProxy.deployed();
  // poolProxyContract = poolProxy.address;
  // console.log("IterableMapping deployed to:", poolProxyContract); 
  //  await hre.run("verify:verify", {
  //   address: poolProxyContract,
  //   constructorArguments: [rewardPool,"0x3d079b51EA706c9a7A40bc62e9CBF836060984Cd",callDataForPool],
  // });


  // reward pool

  //  await hre.run("verify:verify", {
  //   address: "0x76f9412a657FF8459B127e556264f4dB3C5975F2",
  //   constructorArguments: ["0xf6d0285D1c52083d9C4d39fa10D7E6696d244B81"],
  // });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
