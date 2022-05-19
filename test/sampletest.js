const { expect } = require("chai");
const { ethers } = require("hardhat");
const {expectEvent,time,expectRevert,} = require("@openzeppelin/test-helpers");
const WBNB = artifacts.require("WBNB");
const PancakeRouter = artifacts.require("PancakeRouter");
const PancakeFacotry = artifacts.require("PancakeFactory");
const token = artifacts.require("MyToken");
const LpPair = artifacts.require("PancakePair");
const IterableMapping = artifacts.require("IterableMapping");
const distributor = artifacts.require("RewardDistributor");
const rewardPool = artifacts.require("RewardPool");

contract("Token Gas Reduce", (accounts) => {
  const zeroAddress = "0x0000000000000000000000000000000000000000";
  const owner = accounts[0];
  const projectAdmin = accounts[1];
  before(async function () {
      WETHinstance = await WBNB.new();
      pancakeFactoryInstance = await PancakeFacotry.new(owner);
      pancakeRouterInstance = await PancakeRouter.new( pancakeFactoryInstance.address,WETHinstance.address);
      iterableMapping = await IterableMapping.new();
      distributor.link(iterableMapping);
      distributorInstance = await distributor.new();

      busdInstance = await token.new();
      daiInstance = await token.new();
      neggInstance = await token.new();
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
      });  
  })

  describe("RewardPool Test", () => {
      it("admin token transfer", async function () {
        let user1 = accounts[2];
        let amount = "1000000000000000000000000000000";
        await neggInstance.mint(user1,amount, {from: owner});
       // console.log("Hash", await pancakeFactoryInstance.INIT_CODE_PAIR_HASH());
      }); 

      it("create Pool", async function () {
        let user1 = accounts[1];
        let amount = "10000000000";

        await managerInstance.createRewardPool(
          neggInstance.address,
          busdInstance.address,
          projectAdmin,
          20,
          "10000000000000000000000",
          false, {from: owner, value: 0.1e18}
        );

        await managerInstance.createRewardDistributor(
          neggInstance.address,
          busdInstance.address,
          20,
          "10000000000000000000000", {from: owner, value: 0.1e18}
        );

        await managerInstance.createRewardDistributor(
          neggInstance.address,
          daiInstance.address,
          50,
          "10000000000000000000000", {from: owner, value: 0.1e18}
        );
      }); 

      it("token Transfer", async function () {
        let amount = "1000000000000000000000000";

        for(let i=2;i<10;i++){
          await neggInstance.transfer(accounts[i],amount, {from: owner});
        }
      });  

      it("enroll", async function () {
        let user1 = accounts[1];
        let amount = "10000000000";
        let pool = await managerInstance.rewardPoolInfo(neggInstance.address);
        let poolInstance = await rewardPool.at(pool);
        let dividend = await poolInstance.getRewardsDistributor(busdInstance.address);
        let dividendInstance = await distributor.at(dividend);

        await poolInstance.enrollForAllReward(accounts[2], {from:accounts[2] });

        console.log("getNumberOfTokenHolders", Number(await dividendInstance.getNumberOfTokenHolders()));
        

        await poolInstance.multipleEnRollForAllReward(
          [accounts[2],accounts[3],accounts[4],accounts[5],accounts[6]]
        );

        console.log("getNumberOfTokenHolders 2", Number(await dividendInstance.getNumberOfTokenHolders()));

      }); 

      // it("buyback", async function () {
      //   let user1 = accounts[1];
      //   let amount = "10000000000";
      //   let pool = await managerInstance.rewardPoolInfo(neggInstance.address);
      //   let poolInstance = await rewardPool.at(pool);
      //   let dividend = await poolInstance.getRewardsDistributor(busdInstance.address);
      //   let dividendInstance = await distributor.at(dividend);

      //   await web3.eth.sendTransaction({from: owner, to: poolInstance.address, value: 10e18 });

      //   console.log("bnbBalance", Number(await poolInstance.bnbBalance()));

      //   console.log("getNumberOfTokenHolders2", Number(await dividendInstance.getNumberOfTokenHolders()));

      //   console.log("before busd balance", Number(await busdInstance.balanceOf(dividendInstance.address)));

      //   await poolInstance.generateBuyBack("10000000000000000000", {from: owner});

      //   console.log("after busd balance", String(await busdInstance.balanceOf(dividendInstance.address)));
      // });  

      // it("claim", async function () {
      //   let user1 = accounts[2];
      //   let amount = "10000000000";
      //   let pool = await managerInstance.rewardPoolInfo(neggInstance.address);
      //   let poolInstance = await rewardPool.at(pool);
      //   let dividend = await poolInstance.getRewardsDistributor(busdInstance.address);
      //   let dividendInstance = await distributor.at(dividend);


      //   console.log("getNumberOfTokenHolders2", Number(await dividendInstance.getNumberOfTokenHolders()));

      //   console.log("before busd balance", Number(await busdInstance.balanceOf(user1)));

      //   await poolInstance.multipleRewardClaim( {from: user1});

      //   let result = await dividendInstance.accumulativeDividendOf2(user1);

      //   console.log("after busd balance", String(await busdInstance.balanceOf(user1)));

      //   console.log("result", String(result));
      // });  
  })

})