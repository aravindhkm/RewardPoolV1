const { expect } = require("chai");
const { ethers } = require("hardhat");
const {expectEvent,time,expectRevert,} = require("@openzeppelin/test-helpers");
const WBNB = artifacts.require("WBNB");
const PancakeRouter = artifacts.require("PancakeRouter");
const PancakeFacotry = artifacts.require("PancakeFactory");
const token = artifacts.require("MyToken1");
const neggToken = artifacts.require("MyToken");
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
      neggInstance = await neggToken.new();
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

        await neggInstance.initialize(rewardPool.address, {from: owner});
        await neggInstance.setRewardEnable(false, {from: owner});

        let tokenArr = [busdInstance,daiInstance,neggInstance];

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


        await rewardPool.initialize(neggInstance.address,pancakeRouterInstance.address, {from: owner});
        await rewardPool.excludeFromRewards(owner, {from: owner});

        await neggInstance.setRewardEnable(true, {from: owner});
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
          neggInstance.address,
          20,
          86400,
          "100000000000000000000", {from: owner}
        );

        await rewardPool.createRewardDistributor(
          daiInstance.address,
          20,
          86400,
          "100000000000000000000", {from: owner}
        );
      }); 

      it("token Transfer", async function () {
        let amount = "100000000000000000000";

        for(let i=2;i<10;i++){
          await neggInstance.transfer(accounts[i],amount, {from: owner});
        }
      });  

      it("buyback", async function () {
        let user1 = accounts[1];
        let amount = "10000000000";

        console.log(
          "getNumberOfTokenHolders",
          Number(await rewardPool.getNumberOfTokenHolders())
        );

        let pool = await rewardPool.rewardInfo(busdInstance.address);
        let distributorInstance = await distributor.at(pool[0]);

        await web3.eth.sendTransaction({from: owner, to: rewardPool.address, value: 10e18 });

        console.log("bnbBalance", Number(await rewardPool.bnbBalance()));

        console.log("getNumberOfTokenHolders2", Number(await rewardPool.getNumberOfTokenHolders()));

        console.log("before busd balance to distributorInstance", Number(await busdInstance.balanceOf(distributorInstance.address)));

        await rewardPool.generateBuyBack("10000000000000000000", {from: owner});

        console.log("after busd balance to distributorInstance ", String(await busdInstance.balanceOf(distributorInstance.address)));
      }); 
      
      it("auto distribute", async function () {
        let user1 = accounts[2];
        let amount = "10000000000";
        let pool = await rewardPool.rewardInfo(busdInstance.address);
        let dividendInstance = await distributor.at(pool[0]);


        console.log("getNumberOfTokenHolders2", Number(await rewardPool.getNumberOfTokenHolders()));

        console.log("before busd balance to contract", String(await busdInstance.balanceOf(dividendInstance.address)));

        await rewardPool.autoDistribute(busdInstance.address, {from: owner,gas: 10000000});
        await rewardPool.autoDistribute(busdInstance.address, {from: owner,gas: 10000000});
        await rewardPool.autoDistribute(busdInstance.address, {from: owner,gas: 10000000});
        await rewardPool.autoDistribute(busdInstance.address, {from: owner,gas: 10000000});

       // let result = await rewardPool.accumulativeDividendOf2(user1);

        console.log("after busd balance to contract", String(await busdInstance.balanceOf(dividendInstance.address)));

      // console.log("result", String(result));
      });

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