const hre = require("hardhat");

async function main() {

  let iterableMappingContract = "0x67aEc08501DfaB2dBAE861F500a0C80C86bF90Fa";
  let rewardPool = "0x23f60FDbd138235b95f663a4163cb9260098B7D3";
  let goldTokenContract = "0x3787D16F9F2e4adf598355C4ff4800b3500d57fA";
  let tokenProxyContract  = "";
  let poolProxyContract = "";
  let callDataForToken = "0xc4d66de800000000000000000000000023f60fdbd138235b95f663a4163cb9260098b7d3";
  let callDataForPool = "0xc4d66de80000000000000000000000003787d16f9f2e4adf598355c4ff4800b3500d57fa";


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

  // const gToken = await hre.ethers.getContractFactory("MyToken");
  // const goldTOken = await gToken.deploy();
  // await goldTOken.deployed();
  // goldTokenContract = goldTOken.address;
  // console.log("goldTokenContract deployed to:", goldTokenContract); 
  //  await hre.run("verify:verify", {
  //   address: goldTokenContract,
  //   constructorArguments: [],
  // });



  // tokenproxy


  // const tProxy = await hre.ethers.getContractFactory("TokenProxy");
  // const tokenProxy = await tProxy.deploy(goldTokenContract,"0x3d079b51EA706c9a7A40bc62e9CBF836060984Cd",callDataForToken);
  // await tokenProxy.deployed();
  // tokenProxyContract = tokenProxy.address;
  // console.log("IterableMapping deployed to:", tokenProxyContract); 
   await hre.run("verify:verify", {
    address: "0xD4C3f4D589AF6877D54d620e351108C82E465fD9",
    constructorArguments: [goldTokenContract,"0x3d079b51EA706c9a7A40bc62e9CBF836060984Cd",callDataForToken],
  });

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
  //   address: "0x0AA6ec112Ea7CEd3A920833Cae66f5A7424eFabF",
  //   constructorArguments: [],
  // });

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
