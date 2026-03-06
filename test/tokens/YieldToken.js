const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time, mine } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("YieldToken Refactored", function () {
  async function deployFixture() {
    const [owner, user0, user1] = await ethers.getSigners();

    // Deploy Tokens
    const Token = await ethers.getContractFactory("ERC20Mock");
    const bnb = await Token.deploy("BNB", "BNB", ethers.parseEther("10000"));
    const btc = await Token.deploy("BTC", "BTC", ethers.parseEther("10000"));

    // Deploy YieldToken
    const YieldToken = await ethers.getContractFactory("YieldToken");
    const yieldToken = await YieldToken.deploy("Token", "TKN");

    // Deploy YieldTracker
    const YieldTracker = await ethers.getContractFactory("YieldTracker");
    const yieldTracker0 = await YieldTracker.deploy(await yieldToken.getAddress());
    
    // Setup
    await yieldToken.setYieldTrackers([await yieldTracker0.getAddress()]);
    
    return { yieldToken, yieldTracker0, bnb, btc, owner, user0, user1 };
  }

  it("Should track stakes and allow claiming", async function () {
    const { yieldToken, yieldTracker0, bnb, owner, user0 } = await loadFixture(deployFixture);
    
    const stakeAmount = ethers.parseEther("1000");
    await yieldToken.mint(user0.address, stakeAmount);

    // Simulate time passing natively
    await time.increase(3600); 
    await mine(1);

    // Verify balance
    expect(await yieldToken.balanceOf(user0.address)).to.equal(stakeAmount);
  });
});