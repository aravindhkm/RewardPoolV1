const hre = require("hardhat");

async function pancake() {
  const Wbnb = await hre.ethers.getContractFactory("WBNB");
  const wbnb = await Wbnb.deploy();
  let wbnbInstance = await wbnb.deployed();

  const PancakeFactory = await hre.ethers.getContractFactory("PancakeFactory");
  const factory = await PancakeFactory.deploy("0x17Ca0928871b2dB9dd3B2f8b27148a436C24Baa8");
  let factoryInstance = await factory.deployed();

  const PancakeRouter = await hre.ethers.getContractFactory("PancakeRouter");
  const router = await PancakeRouter.deploy(factoryInstance.address,wbnbInstance.address);
  let routerInstance = await router.deployed();

  return (
      wbnbInstance.address,
      factoryInstance.address,
      routerInstance.address
  )

}
pancake().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

if (require.main === module) {
  pancake()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error)
      process.exit(1)
    })
}


exports.pancake = pancake