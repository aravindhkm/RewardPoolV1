const { expect } = require("chai");
const { ethers } = require("hardhat");
const {expectEvent,time,expectRevert,} = require("@openzeppelin/test-helpers");
const WBNB = artifacts.require("WBNB");
const PancakeRouter = artifacts.require("PancakeRouter");
const PancakeFacotry = artifacts.require("PancakeFactory");
const token = artifacts.require("MyToken1");
const gold = artifacts.require("GoldenDuckToken");
const LpPair = artifacts.require("PancakePair");
const IterableMapping = artifacts.require("IterableMapping");
const distributor = artifacts.require("RewardDistributor");
const rewardPoolAbi = artifacts.require("RewardPool");

contract("Token Gas Reduce", (accounts) => {
  const zeroAddress = "0x0000000000000000000000000000000000000000";
  const owner = accounts[0];
  const projectAdmin = accounts[1];
  before(async function () {
      WETHinstance = await WBNB.new();
      pancakeFactoryInstance = await PancakeFacotry.new(owner);
      pancakeRouterInstance = await PancakeRouter.new( pancakeFactoryInstance.address,WETHinstance.address);
      iterableMapping = await IterableMapping.new();
      rewardPoolAbi.link(iterableMapping);
      rewardPool = await rewardPoolAbi.new();

      busdInstance = await token.new();
      daiInstance = await token.new();
      goldInstance = await gold.new();
  });

  describe("Token Set", () => {
      it("admin token transfer", async function () {
        let user1 = accounts[1];
        let amount = "10000000000";
        await busdInstance.transfer(user1,amount, {from: owner});
       // console.log("Hash", await pancakeFactoryInstance.INIT_CODE_PAIR_HASH());
      });  

      it("add liquidity", async function () {
        let user1 = accounts[1];
        let amount = "10000000000000000000000";

        await goldInstance.initialize(rewardPool.address, {from: owner});        
        await rewardPool.initialize(goldInstance.address,pancakeRouterInstance.address, {from: owner});

        let tokenArr = [busdInstance,daiInstance,goldInstance];

        for(let i=0;i<3;i++){
          await tokenArr[i].transfer(user1,amount, {from: owner});

          await tokenArr[i].approve(pancakeRouterInstance.address,amount, {from: user1});

          await pancakeRouterInstance.addLiquidityETH(
                tokenArr[i].address,
                amount,
                0,
                0,
                user1,
                user1,{
                    from: user1,
                    value: 10e18
                }
            )
        }


        await rewardPool.excludeFromRewards(owner, {from: owner});
      });  
  })

  describe("RewardPool Test", () => {

      it("create Pool", async function () {
        let user1 = accounts[1];
        let amount = "10000000000";

        await rewardPool.createRewardDistributor(
          busdInstance.address,
          20,
          86400,
          "100000000000000000000", {from: owner}
        );

        await rewardPool.createRewardDistributor(
          goldInstance.address,
          20,
          86400,
          "300000000000000000000", {from: owner}
        );

        await rewardPool.createRewardDistributor(
          daiInstance.address,
          20,
          86400,
          "500000000000000000000", {from: owner}
        );
      }); 

      it("token Transfer", async function () {
        await goldInstance.transfer(accounts[2],"100000000000000000000", {from: owner});
        await goldInstance.transfer(accounts[3],"100000000000000000000", {from: owner});
        await goldInstance.transfer(accounts[4],"300000000000000000000", {from: owner});
        await goldInstance.transfer(accounts[5],"400000000000000000000", {from: owner});
        await goldInstance.transfer(accounts[6],"600000000000000000000", {from: owner});
        await goldInstance.transfer(accounts[7],"600000000000000000000", {from: owner});
      });  

      it("buyback", async function () {
        let user1 = accounts[1];
        let amount = "10000000000";

        console.log(
          "getNumberOfTokenHolders",
          Number(await rewardPool.getNumberOfTokenHolders(daiInstance.address))
        );

        let pool = await rewardPool.getRewardsDistributor(daiInstance.address);
        let distributorInstance = await distributor.at(pool);

        await web3.eth.sendTransaction({from: owner, to: rewardPool.address, value: 10e18 });

        console.log("bnbBalance", Number(await rewardPool.bnbBalance()));

        console.log("Dai Address", daiInstance.address);

        console.log("before dai balance to distributorInstance", Number(await daiInstance.balanceOf(distributorInstance.address)));

        await rewardPool.generateBuyBack("10000000000000000000", {from: owner});

        console.log("after dai balance to distributorInstance ", String(await daiInstance.balanceOf(distributorInstance.address)));
      }); 


      it("token Transfer", async function () {

          let userBalance1 = await rewardPool.rewardOf(daiInstance.address,accounts[6]);
          let userBalance2 = await rewardPool.rewardOf(daiInstance.address,accounts[7]);

          console.log("Account 6 dai reward", Number(userBalance1/1e18));
          console.log("Account 7 dai reward", Number(userBalance2/1e18));

          console.log(
            "User Balance For Dai Reward", 
            Number(await rewardPool.rewardOf(daiInstance.address,accounts[4]) / 1e18)
          );
          console.log(
            "User Balance For Dai Reward", 
            Number(await rewardPool.rewardOf(daiInstance.address,accounts[5]) / 1e18)
          );
          console.log(
            "User Balance For Dai Reward", 
            Number(await rewardPool.rewardOf(daiInstance.address,accounts[3]) / 1e18)
          );
          console.log(
            "User Balance For Dai Reward", 
            Number(await rewardPool.rewardOf(daiInstance.address,accounts[2]) / 1e18)
          )

          console.log(
            "totalHolderSupply",
            Number(await rewardPool.totalHolderSupply(daiInstance.address)/ 1e18)
          )
      }); 
      
      // it("auto distribute", async function () {
      //   let user1 = accounts[2];
      //   let amount = "10000000000";
      //   let pool = await rewardPool.rewardInfo(busdInstance.address);
      //   let dividendInstance = await distributor.at(pool[0]);


      //   console.log("getNumberOfTokenHolders2", Number(await rewardPool.getNumberOfTokenHolders(busdInstance.address)));

      //   console.log("before busd balance to contract", String(await busdInstance.balanceOf(dividendInstance.address)));

      //   await rewardPool.autoDistribute(busdInstance.address, {from: owner,gas: 10000000});
      //   await rewardPool.autoDistribute(busdInstance.address, {from: owner,gas: 10000000});
      //   await rewardPool.autoDistribute(busdInstance.address, {from: owner,gas: 10000000});
      //   await rewardPool.autoDistribute(busdInstance.address, {from: owner,gas: 10000000});

      //  // let result = await rewardPool.accumulativeDividendOf2(user1);

      //   console.log("after busd balance to contract", String(await busdInstance.balanceOf(dividendInstance.address)));

      // // console.log("result", String(result));
      // });

      // it("claim", async function () {
      //   let user1 = accounts[2];
      //   let amount = "10000000000";
      //   let pool = await rewardPool.rewardInfo(busdInstance.address);
      //   let dividendInstance = await distributor.at(pool[0]);


      //   console.log("getNumberOfTokenHolders2", Number(await rewardPool.getNumberOfTokenHolders()));

      //   console.log("before busd balance to user", Number(await busdInstance.balanceOf(user1)));

      //   await rewardPool.multipleRewardClaimByUser( {from: user1});
      //   await rewardPool.multipleRewardClaimByUser( {from: user1});

      //  // let result = await rewardPool.accumulativeDividendOf2(user1);

      //   console.log("after busd balance to user", String(await busdInstance.balanceOf(user1)));

      // // console.log("result", String(result));
      // });  
  })

})