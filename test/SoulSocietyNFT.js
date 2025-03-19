const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SoulSocietyNFTMasterChef", function () {
  let nftToken, rewardToken, chef;
  let admin, user, other;
  // Use two token IDs for testing
  const tokenIds = [1, 2];
  const rewardRates = [10, 20]; // reward per block per token id

  beforeEach(async function () {
    [admin, user, other] = await ethers.getSigners();

    // Deploy a mock ERC721 token (assumes a mint function is available)
    const MockERC721 = await ethers.getContractFactory("MockBakaBearNFT");
    nftToken = await MockERC721.deploy(admin.address);
    await nftToken.deployed();

    // Deploy a mock ERC20 token for rewards
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    rewardToken = await MockERC20.deploy(admin.address);
    await rewardToken.deployed();

    // Deploy the SoulSocietyNFTMasterChef contract 
    const SoulSocietyNFTMasterChef = await ethers.getContractFactory("SoulSocietyNFTMasterChef");
    chef = await SoulSocietyNFTMasterChef.deploy();
    await chef.deployed();

    // Initialize the chef contract with the mock addresses and pool data
    await chef.initialize(nftToken.address, rewardToken.address, admin.address, tokenIds, rewardRates);

    // Mint NFTs for the user for both token IDs (ERC721: each tokenId minted once)
    await nftToken.safeMint(user.address, 1);
    await nftToken.safeMint(user.address, 2);

    // Transfer reward tokens to the chef contract so it can pay rewards
    await rewardToken.transfer(chef.address, ethers.utils.parseEther("1000"));
  });

  describe("Initialization", function () {
    it("should initialize pool info correctly", async function () {
      for (let i = 0; i < tokenIds.length; i++) {
        const pool = await chef.poolInfo(tokenIds[i]);
        expect(pool.rewardRatePerBlock).to.equal(rewardRates[i]);
      }
    });
  });

  describe("Staking", function () {
    beforeEach(async function () {
      // User must approve the chef contract to transfer their NFTs
      await nftToken.connect(user).setApprovalForAll(chef.address, true);
    });

    it("should allow staking of valid NFTs (positive case)", async function () {
      await expect(chef.connect(user).stake([1]))
        .to.emit(chef, "Staked")
        .withArgs(user.address, 1, 1);

      // Check pending reward (should be 0 if no blocks have passed)
      const pending = await chef.pendingReward(user.address, 1);
      expect(pending).to.equal(0);
    });

    it("should allow staking multiple tokenIds in one call", async function () {
      await expect(chef.connect(user).stake([1, 2]))
        .to.emit(chef, "Staked")
        .withArgs(user.address, 1, 1)
        .and.to.emit(chef, "Staked")
        .withArgs(user.address, 2, 1);
    });

    it("should revert staking when pool does not exist (negative case)", async function () {
      // tokenId 3 was not initialized so rewardRatePerBlock is 0 by default
      await expect(chef.connect(user).stake([3])).to.be.revertedWith("Pool does not exist");
    });

    it("should not allow staking when contract is paused", async function () {
      // Pause contract using admin
      await chef.connect(admin).pause();
      await expect(chef.connect(user).stake([1])).to.be.reverted;
      // Unpause for further tests
      await chef.connect(admin).unpause();
    });
  });

  describe("Unstaking", function () {
    beforeEach(async function () {
      // Stake tokens for both token IDs before unstaking tests
      await nftToken.connect(user).setApprovalForAll(chef.address, true);
      await chef.connect(user).stake([1, 2]);
    });

    it("should allow unstaking of valid NFTs (positive case)", async function () {
      await expect(chef.connect(user).unstake([1]))
        .to.emit(chef, "Unstaked")
        .withArgs(user.address, 1, 1);

      // Verify that the NFT is returned to user’s wallet
      expect(await nftToken.ownerOf(1)).to.equal(user.address);
    });

    it("should revert unstaking a token not staked by the user (negative case)", async function () {
      // Trying to unstake token id 3 which was never staked
      await expect(chef.connect(user).unstake([3])).to.be.revertedWith("Token not staked by caller");
    });

    it("should not allow unstaking when contract is paused", async function () {
      await chef.connect(admin).pause();
      await expect(chef.connect(user).unstake([1])).to.be.reverted;
      await chef.connect(admin).unpause();
    });

    it("should automatically claim pending rewards on unstake", async function () {
      // Increase block number so that rewards accumulate.
      // Mine 2 blocks.
      await ethers.provider.send("evm_mine", []);
      await ethers.provider.send("evm_mine", []);

      // For tokenId 1: reward = 2 blocks * 10 rewardRate = 20
      await expect(chef.connect(user).unstake([1]))
        .to.emit(chef, "RewardClaimed")
        .withArgs(user.address, 1, 20);
    });
  });

  describe("Claim Reward", function () {
    beforeEach(async function () {
      await nftToken.connect(user).setApprovalForAll(chef.address, true);
      // Stake token so that rewards can accumulate.
      await chef.connect(user).stake([1]);
    });

    it("should allow claiming reward when available (positive case)", async function () {
      // Mine a few blocks to accumulate reward.
      await ethers.provider.send("evm_mine", []);
      await ethers.provider.send("evm_mine", []);

      const initialBalance = await rewardToken.balanceOf(user.address);
      // For tokenId 1: reward = 2 blocks * 10 rewardRate = 20
      await expect(chef.connect(user).claimReward(1))
        .to.emit(chef, "RewardClaimed")
        .withArgs(user.address, 1, 20);
      const finalBalance = await rewardToken.balanceOf(user.address);
      expect(finalBalance.sub(initialBalance)).to.equal(20);
    });
  });

  describe("Pending Reward", function () {
    beforeEach(async function () {
      await nftToken.connect(user).setApprovalForAll(chef.address, true);
      await chef.connect(user).stake([1]);
    });

    it("should return 0 pending reward initially", async function () {
      const pending = await chef.pendingReward(user.address, 1);
      expect(pending).to.equal(0);
    });

    it("should return an increased pending reward after blocks are mined", async function () {
      await ethers.provider.send("evm_mine", []);
      await ethers.provider.send("evm_mine", []);
      const pending = await chef.pendingReward(user.address, 1);
      expect(pending).to.equal(20);
    });
  });

  describe("Reward End Block", function () {
    beforeEach(async function () {
      await nftToken.connect(user).setApprovalForAll(chef.address, true);
      await chef.connect(user).stake([1]);
    });

    it("should cap reward accumulation after rewardEndBlock (positive case)", async function () {
      // Set rewardEndBlock to current block + 2
      const currentBlock = await ethers.provider.getBlockNumber();
      await expect(chef.connect(admin).setRewardEndBlock(currentBlock + 2))
        .to.emit(chef, "RewardEndBlockUpdated")
        .withArgs(currentBlock + 2);

      // Mine 5 blocks; rewards should only accumulate for 2 blocks
      for (let i = 0; i < 5; i++) {
        await ethers.provider.send("evm_mine", []);
      }

      const pending = await chef.pendingReward(user.address, 1);
      // For tokenId 1, reward = 2 blocks * 10 rewardRate = 20
      expect(pending).to.equal(20);
    });
  });
});
