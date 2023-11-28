import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, network } from "hardhat";

describe("StakingPool", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployStakingPool() {

    // Contracts are deployed using the first signer/account by default]

    const usdcToken = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    const ausdcToken = "0xBcca60bB61934080951369a648Fb03DF4F96263C";
    const aaveLendingPool = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9";
    const [owner] = await ethers.getSigners();

    //usdc token holders
    const account1 = "0xDa9CE944a37d218c3302F6B82a094844C6ECEb17";
    const account2 = "0x51eDF02152EBfb338e03E30d65C15fBf06cc9ECC";
    const account3 = "0xc9E6E51C7dA9FF1198fdC5b3369EfeDA9b19C34c";

    //fork the mainnet
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [account1]
    });

    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [account2]
    });

    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [account3]
    });

    const holder1 = await ethers.getSigner(account1);
    const holder2 = await ethers.getSigner(account2);
    const holder3 = await ethers.getSigner(account3);

    const accounts = await ethers.getSigners();

    await accounts[0].sendTransaction({
      to: holder1.address,
      value: ethers.parseEther("20.0")
    });

    await accounts[0].sendTransaction({
      to: holder2.address,
      value: ethers.parseEther("20.0")
    });

    await accounts[0].sendTransaction({
      to: holder3.address,
      value: ethers.parseEther("20.0")
    });

    const MockToken = await ethers.getContractFactory("MockToken");
    const mockToken = await MockToken.connect(owner).deploy();

    const StakingPool = await ethers.getContractFactory("StakingPool");
    const stakingPool = await StakingPool.connect(owner).deploy(usdcToken, ausdcToken, aaveLendingPool, await mockToken.getAddress(), 1e10);

    return { mockToken, stakingPool, ausdcToken, usdcToken, aaveLendingPool, owner, holder1, holder2, holder3 };
  }

  describe("Deployment", function () {
    it("Should set the right public states", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      expect(await stakingPool.usdcToken()).to.equal(usdcToken);
      expect(await stakingPool.ausdcToken()).to.equal(ausdcToken);
      expect(await stakingPool.aaveLendingPool()).to.equal(aaveLendingPool);
      expect(await stakingPool.rewardTokensPerBlock()).to.equal(1e10);
      expect(await stakingPool.mockToken()).to.equal(await mockToken.getAddress());
    });
  });

  describe("depositWIthUSDC", function () {
    it("Should be fail with the right error if amount is less than 0.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      await expect(stakingPool.depositWithUSDC(0)).to.revertedWith("amount should be more than 0");
    });

    it("Should not be fail with the right error if all conditions are ok", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      const usdcTokenContract = await ethers.getContractAt("IERC20", usdcToken);

      //approve the stakingPool contract and deposit
      await usdcTokenContract.connect(holder1).approve(stakingPool.getAddress(), 10);
      await expect(stakingPool.connect(holder1).depositWithUSDC(10)).not.be.reverted;
    });
  });

  describe("depositWIthAUSDC", function () {
    it("Should be fail with the right error if amount is less than 0.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      await expect(stakingPool.depositWithAUSDC(0)).to.revertedWith("amount should be more than 0");
    });

    it("Should not be fail if all conditions are ok.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2, holder3 } = await loadFixture(deployStakingPool);

      const ausdcTokenContract = await ethers.getContractAt("IAToken", ausdcToken);
      const usdcTokenContract = await ethers.getContractAt("IERC20", usdcToken);

      const block_0 = await stakingPool.lastRewardedBlock();

      //approve the stakingPool contract for holder1 and holder3
      await usdcTokenContract.connect(holder1).approve(stakingPool.getAddress(), ethers.parseUnits("20", 6));
      await ausdcTokenContract.connect(holder3).approve(stakingPool.getAddress(), ethers.parseUnits("10", 6));

      //holder1 deposit the USDC token
      await stakingPool.connect(holder1).depositWithUSDC(ethers.parseUnits("9.5", 6));
      const holder1Amount_0 = (await stakingPool.stakers(holder1.address)).scaledAmount;
      const block_1 = await stakingPool.lastRewardedBlock();

      //holder3 deposit the aUSDC token
      await expect(stakingPool.connect(holder3).depositWithAUSDC(ethers.parseUnits("10", 6))).not.be.reverted;
      const holder3Amount_0 = (await stakingPool.stakers(holder3.address)).scaledAmount;
      const block_2 = await stakingPool.lastRewardedBlock();

      //holder1 deposit the USDC token again
      await stakingPool.connect(holder1).depositWithUSDC(ethers.parseUnits("10", 6));
      const holder1Amount_1 = (await stakingPool.stakers(holder1.address)).scaledAmount - holder1Amount_0;
      const block_3 = await stakingPool.lastRewardedBlock();

      //compare with holder1's mock balance and expectation
      console.log(block_0, holder1Amount_0, block_1, holder3Amount_0, block_2, holder1Amount_1, block_3, await mockToken.balanceOf(holder1.address));
      const expect_holder1Balance = BigInt(1e10) * (block_2 - block_1) + BigInt(1e10) * (block_3 - block_2) * holder1Amount_0 / (holder1Amount_0 + holder3Amount_0);
      expect(await mockToken.balanceOf(holder1.address)).to.equal(expect_holder1Balance);
    });
  });

  describe("withdrawInUSDC", function () {
    it("Should be fail with the right error if amount is less than 0.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      await expect(stakingPool.withdrawInUSDC(0)).to.revertedWith("amount should be more than 0");
    });

    it("Should be fail with the right error if amount is more than staked amount.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      const usdcTokenContract = await ethers.getContractAt("IERC20", usdcToken);

      await usdcTokenContract.connect(holder1).approve(stakingPool.getAddress(), ethers.parseUnits("20", 6));
      await stakingPool.connect(holder1).depositWithUSDC(ethers.parseUnits("9.5", 6));

      await expect(stakingPool.withdrawInUSDC(ethers.parseUnits("20", 6))).to.revertedWith("amount should be less than staker's staked amount");
    });

    it("Should not be fail if all conditions are ok.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      const usdcTokenContract = await ethers.getContractAt("IERC20", usdcToken);

      await usdcTokenContract.connect(holder1).approve(stakingPool.getAddress(), ethers.parseUnits("20", 6));

      await stakingPool.connect(holder1).depositWithUSDC(ethers.parseUnits("9.5", 6));

      const oldBalance = await usdcTokenContract.balanceOf(holder1.address); //old balance before withdraw

      await expect(stakingPool.connect(holder1).withdrawInUSDC(ethers.parseUnits("5", 6))).not.be.reverted;

      const currentBalance = await usdcTokenContract.balanceOf(holder1.address); //current balance after withdraw

      //compare with withdraw amount and expectation
      expect(currentBalance - oldBalance).to.equal(ethers.parseUnits("5", 6));
    });
  });

  describe("withdrawInAUSDC", function () {
    it("Should be fail with the right error if amount is less than 0.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      await expect(stakingPool.withdrawInAUSDC(0)).to.revertedWith("amount should be more than 0");
    });

    it("Should be fail with the right error if amount is more than staked amount.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2, holder3 } = await loadFixture(deployStakingPool);

      const ausdcTokenContract = await ethers.getContractAt("IAToken", ausdcToken);

      await ausdcTokenContract.connect(holder3).approve(stakingPool.getAddress(), ethers.parseUnits("20", 6));
      await stakingPool.connect(holder3).depositWithAUSDC(ethers.parseUnits("9.5", 6));

      await expect(stakingPool.connect(holder3).withdrawInAUSDC(ethers.parseUnits("20", 6))).to.revertedWith("amount should be less than staker's staked amount");
    });

    it("Should not be fail if all conditions are ok.", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2, holder3 } = await loadFixture(deployStakingPool);

      const ausdcTokenContract = await ethers.getContractAt("IAToken", ausdcToken);
      const LendingPool = await ethers.getContractAt("ILendingPool", aaveLendingPool);
      const Ray = BigInt(1e27);
      const halfRay = BigInt(5e26);

      await ausdcTokenContract.connect(holder3).approve(stakingPool.getAddress(), ethers.parseUnits("20", 6));
      await stakingPool.connect(holder3).depositWithAUSDC(ethers.parseUnits("9.5", 6));

      const oldBalance = await ausdcTokenContract.scaledBalanceOf(holder3.address); //old balance before withdraw
      await expect(stakingPool.connect(holder3).withdrawInAUSDC(ethers.parseUnits("5", 6))).not.be.reverted;
      const currentBalance = await ausdcTokenContract.scaledBalanceOf(holder3.address); //current balance after withdraw

      const liquidityIndex = (await LendingPool.getReserveData(usdcToken)).liquidityIndex;
      //compare with the withdraw amount and expectation
      expect(((currentBalance - oldBalance) * liquidityIndex + halfRay) / Ray).to.equal(ethers.parseUnits("5", 6));
    });
  });

  describe("pendingRewards", function () {
    it("Should be return 0 if total Amount is 0", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      const pendingReward = await stakingPool.connect(holder1).pendingRewards();
      console.log(pendingReward)
      expect(pendingReward).to.equal(0);
    });

    it("Should be return pendingRewards if total Amount is not 0", async function () {
      const { mockToken, stakingPool, usdcToken, ausdcToken, aaveLendingPool, owner, holder1, holder2 } = await loadFixture(deployStakingPool);

      const usdcTokenContract = await ethers.getContractAt("IERC20", usdcToken);

      //approve the stakingPool contract for holder1 and deposit
      await usdcTokenContract.connect(holder1).approve(stakingPool.getAddress(), ethers.parseUnits("20", 6));
      await stakingPool.connect(holder1).depositWithUSDC(ethers.parseUnits("9.5", 6));
      const block_0 = await stakingPool.lastRewardedBlock();

      //holder1 call the pendingReward
      const pendingReward = await stakingPool.connect(holder1).pendingRewards();

      //compare with the pending Rewards and expectation.
      const block_1 = await time.latestBlock();
      expect(pendingReward).to.equal(BigInt(1e10) * (BigInt(block_1) - block_0))
    });
  });
});
