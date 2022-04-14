const { expect } = require("chai");
const { ethers } = require("hardhat");
const {expectEvent,time,expectRevert,} = require("@openzeppelin/test-helpers");
const WBNB = artifacts.require("WBNB");
const PancakeRouter = artifacts.require("PancakeRouter");
const PancakeFacotry = artifacts.require("PancakeFactory");
const token = artifacts.require("ERC20Token");
const LpPair = artifacts.require("PancakePair");
const superAdmin = artifacts.require("SuperAdmin");

contract("Token Gas Reduce", (accounts) => {
  const zeroAddress = "0x0000000000000000000000000000000000000000";
  const owner = accounts[0];
  before(async function () {
      WETHinstance = await WBNB.new();
      pancakeFactoryInstance = await PancakeFacotry.new(owner);
      pancakeRouterInstance = await PancakeRouter.new( pancakeFactoryInstance.address,WETHinstance.address);
      superAdminInstance = await superAdmin.new(owner);
      console.log("address",pancakeRouterInstance.address,superAdminInstance.address)
      tokenInstance = await token.new(pancakeRouterInstance.address,superAdminInstance.address);
  });

   describe("ShiborgInuEther Token", () => {
      it("admin token transfer", async function () {
        let user1 = accounts[1];
        let amount = "10000000000";
        await tokenInstance.transfer(user1,amount, {from: owner});
      }); 

      it("user token transfer: 1", async function () {
        let user1 = accounts[1];
        let user2 = accounts[2];
        let amount = "10000000000";
        await tokenInstance.transfer(user2,amount, {from: user1});
      }); 

    //   it("exclude ten user", async function () {
    //     let amount = "10000000000";

    //     for(i=2;i<12;i++) {
    //       await tokenInstance.transfer(accounts[i],amount, {from: owner});
    //       await tokenInstance.excludeFromReward(accounts[i], {from: owner});
    //     }
    //   });

    //   it("user token transfer: 2", async function () {
    //     let user1 = accounts[2];
    //     let user2 = accounts[1];
    //     let amount = "10000000000";
    //     await tokenInstance.transfer(user2,amount, {from: user1});
    //   });  

    //   it("add liquidity", async function () {
    //     let user1 = accounts[1];
    //     let amount = "10000000000000";
    //     await tokenInstance.transfer(user1,amount, {from: owner});

    //     await tokenInstance.approve(pancakeRouterInstance.address,amount, {from: user1});

    //     await pancakeRouterInstance.addLiquidityETH(
    //           tokenInstance.address,
    //           amount,
    //           0,
    //           0,
    //           user1,
    //           user1,{
    //               from: user1,
    //               value: 10e18
    //           }
    //       )
    //   }); 

    //   it("buy", async function () {
    //     let user1 = accounts[1];
    //     let amount = "1000000000000";

    //     let getOut = await pancakeRouterInstance.getAmountsOut(amount,[WETHinstance.address,tokenInstance.address]);

    //     await pancakeRouterInstance.swapETHForExactTokens(
    //           getOut[1],
    //           [WETHinstance.address,tokenInstance.address],
    //           user1,
    //           user1,{
    //               from: user1,
    //               value: amount
    //           }
    //       )
    //   }); 

    //   it("sell", async function () {
    //     let user1 = accounts[1];
    //     let amount = "10000000000000";
    //     await tokenInstance.transfer(user1,amount, {from: owner});

    //     await tokenInstance.approve(pancakeRouterInstance.address,amount, {from: user1});
    //     let getOut = await pancakeRouterInstance.getAmountsOut(amount,[tokenInstance.address,WETHinstance.address]);


    //     await pancakeRouterInstance.swapExactTokensForETHSupportingFeeOnTransferTokens(
    //           amount,
    //           1,
    //           [tokenInstance.address,WETHinstance.address],
    //           user1,
    //           user1,{
    //               from: user1
    //           }
    //       )
   //   }); 
  })

})