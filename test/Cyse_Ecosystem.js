const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("CYSE Ecosystem Tests", function () {
  async function deployFixture() {
    const [owner, minter, user, other] = await ethers.getSigners();

    // Deploy CYSE Token
    const CYSE = await ethers.getContractFactory("CYSE");
    const cyse = await CYSE.deploy();
    
    // Deploy a Mock ERC20 to be the Staking Token
    const MockERC20 = await ethers.getContractFactory("ERC20Mock"); // Assuming an OZ mock exists
    const stakingToken = await MockERC20.deploy("Staking Token", "STK", ethers.parseEther("1000000"));

    // Deploy Yield Farm (which inherits YieldToken)
    const YieldFarm = await ethers.getContractFactory("YieldFarm");
    const yieldFarm = await YieldFarm.deploy("Staked CYSE", "sCYSE", await stakingToken.getAddress());

    // Setup Roles
    const MINTER_ROLE = await cyse.MINTER_ROLE();
    await cyse.grantRole(MINTER_ROLE, minter.address);

    return { cyse, stakingToken, yieldFarm, owner, minter, user, other, MINTER_ROLE };
  }

  describe("AccessControl", function () {
    it("Should allow only MINTER_ROLE to mint", async function () {
      const { cyse, minter, user } = await loadFixture(deployFixture);
      
      await cyse.connect(minter).mint(user.address, 1000);
      expect(await cyse.balanceOf(user.address)).to.equal(1000);
      
      // Attempt unauthorized mint
      await expect(cyse.connect(user).mint(user.address, 1000))
        .to.be.reverted; // Reverts due to MissingRole
    });
  });

  describe("YieldFarm Mechanics", function () {
    it("Should correctly mint sCYSE upon staking", async function () {
      const { stakingToken, yieldFarm, user } = await loadFixture(deployFixture);
      const stakeAmount = ethers.parseEther("100");

      await stakingToken.transfer(user.address, stakeAmount);
      await stakingToken.connect(user).approve(await yieldFarm.getAddress(), stakeAmount);

      await yieldFarm.connect(user).stake(stakeAmount);

      // Verify receipt token balance
      expect(await yieldFarm.balanceOf(user.address)).to.equal(stakeAmount);
      // Verify staking token is locked in the farm
      expect(await stakingToken.balanceOf(await yieldFarm.getAddress())).to.equal(stakeAmount);
    });

    it("Should burn sCYSE and return staking token on unstake", async function () {
      const { stakingToken, yieldFarm, user } = await loadFixture(deployFixture);
      const amount = ethers.parseEther("50");

      await stakingToken.transfer(user.address, amount);
      await stakingToken.connect(user).approve(await yieldFarm.getAddress(), amount);
      await yieldFarm.connect(user).stake(amount);

      await yieldFarm.connect(user).unstake(amount);

      expect(await yieldFarm.balanceOf(user.address)).to.equal(0);
      expect(await stakingToken.balanceOf(user.address)).to.equal(amount);
    });
  });
});