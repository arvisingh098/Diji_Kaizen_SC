// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "../Gaming/Game/interface/ITreasury.sol";

/**
 * @title SoulSocietyNFTMasterChef
 * @dev ERC721-based staking contract with MasterChef-style reward distribution.
 * Users can stake their NFTs (from the approved ERC721 collection) and earn rewards per block.
 * Rewards are calculated individually for each staked NFT.
 */
contract SoulSocietyNFTMasterChef is Initializable, UUPSUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, ERC721HolderUpgradeable {
    IERC721 public nftToken;
    IERC20 public rewardToken;
    address public treasuryContract;
    
    // New variable to mark the end block for rewards
    uint256 public rewardEndBlock;

    // In this version, a user staking an NFT is tracked with a flag (1 = staked, 0 = not staked)
    struct UserInfo {
        mapping(uint256 => uint256) stakedAmount; // For ERC721, this will be 1 when staked, 0 when not.
        mapping(uint256 => uint256) rewardDebt;   // Reward debt per NFT token ID
    }

    // Reward pool for each NFT token id. In ERC721, each token is unique so the pool usually
    // represents the reward configuration for that particular token.
    struct PoolInfo {
        uint256 rewardRatePerBlock; // Reward per block for this NFT token ID
        uint256 lastRewardBlock;    // Last block when rewards were updated
        uint256 accRewardPerShare;  // Accumulated reward per share (scaled by 1e12)
    }

    // Pools are set per token id – note that in ERC721 each token is unique and stakable only once.
    mapping(uint256 => PoolInfo) public poolInfo;
    mapping(address => UserInfo) private userInfo;

    // Total staked NFTs per token id (will be either 0 or 1)
    mapping(uint256 => uint256) public totalStakedNFTs;

    event Staked(address indexed user, uint256 tokenId, uint256 amount);
    event Unstaked(address indexed user, uint256 tokenId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 tokenId, uint256 reward);
    event RewardRateUpdated(uint256 indexed tokenId, uint256 newRate);
    event EmergencyWithdraw(address indexed user, uint256 tokenId, uint256 amount);
    event RewardEndBlockUpdated(uint256 newRewardEndBlock);

    modifier onlyAdmin() {
        // Uncomment and adjust the following line if you integrate with a treasury/admin contract
        require(ITreasury(treasuryContract).isRoleAdmin(msg.sender), "Caller is not an admin");
        _;
    }

    /**
     * @dev Initializes the staking contract.
     * @param _nftToken Address of the ERC721 NFT contract.
     * @param _rewardToken Address of the ERC20 reward token contract.
     * @param _treasuryContract Address of the treasury contract for admin roles.
     * @param _tokenIds Array of NFT token IDs to initialize reward pools.
     * @param _rewardRates Corresponding reward rates per block for each token ID.
     */
    function initialize(
        address _nftToken,
        address _rewardToken,
        address _treasuryContract,
        uint256[] memory _tokenIds,
        uint256[] memory _rewardRates
    ) public initializer {
        require(_tokenIds.length == _rewardRates.length, "Mismatched input lengths");
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC721Holder_init();
        nftToken = IERC721(_nftToken);
        rewardToken = IERC20(_rewardToken);
        treasuryContract = _treasuryContract;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            poolInfo[_tokenIds[i]] = PoolInfo({
                rewardRatePerBlock: _rewardRates[i],
                lastRewardBlock: block.number,
                accRewardPerShare: 0
            });
        }
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    /**
     * @dev Stakes multiple ERC721 NFTs.
     * @param tokenIds Array of NFT token IDs to stake.
     *
     * Note: Each token can only be staked once; the amount is implicitly 1.
     */
    function stake(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            PoolInfo storage pool = poolInfo[tokenId];
            require(pool.rewardRatePerBlock > 0, "Pool does not exist");

            // Update reward pool for this tokenId
            updatePool(tokenId);

            UserInfo storage user = userInfo[msg.sender];
            require(user.stakedAmount[tokenId] == 0, "Token already staked");

            // Transfer the NFT from the user to the contract
            nftToken.safeTransferFrom(msg.sender, address(this), tokenId);
            user.stakedAmount[tokenId] = 1;
            user.rewardDebt[tokenId] = (1 * pool.accRewardPerShare) / 1e12;
            totalStakedNFTs[tokenId] = 1;

            emit Staked(msg.sender, tokenId, 1);
        }
    }

    /**
     * @dev Unstakes multiple ERC721 NFTs.
     * @param tokenIds Array of NFT token IDs to unstake.
     */
    function unstake(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            UserInfo storage user = userInfo[msg.sender];
            require(user.stakedAmount[tokenId] == 1, "Token not staked by caller");

            updatePool(tokenId);

            uint256 pending = ((1 * poolInfo[tokenId].accRewardPerShare) / 1e12) - user.rewardDebt[tokenId];
            if (pending > 0) {
                safeRewardTransfer(msg.sender, pending);
                emit RewardClaimed(msg.sender, tokenId, pending);
            }

            user.stakedAmount[tokenId] = 0;
            user.rewardDebt[tokenId] = 0;
            totalStakedNFTs[tokenId] = 0;

            // Transfer the NFT back to the user
            nftToken.safeTransferFrom(address(this), msg.sender, tokenId);
            emit Unstaked(msg.sender, tokenId, 1);
        }
    }

    /**
     * @dev Updates the reward calculation for a specific NFT token ID.
     * @param tokenId The NFT token ID.
     */
    function updatePool(uint256 tokenId) public {
        PoolInfo storage pool = poolInfo[tokenId];
        // Use the lower of current block and rewardEndBlock to cap rewards.
        uint256 currentBlock = (block.number > rewardEndBlock && rewardEndBlock > 0) ? rewardEndBlock : block.number;
        if (currentBlock <= pool.lastRewardBlock) {
            return;
        }

        uint256 nftSupply = totalStakedNFTs[tokenId];
        if (nftSupply == 0) {
            pool.lastRewardBlock = currentBlock;
            return;
        }

        uint256 multiplier = currentBlock - pool.lastRewardBlock;
        uint256 reward = multiplier * pool.rewardRatePerBlock;

        pool.accRewardPerShare += (reward * 1e12) / nftSupply;
        pool.lastRewardBlock = currentBlock;
    }

    /**
     * @dev Allows a user to claim pending rewards for a specific NFT token ID.
     * @param tokenId The NFT token ID to claim rewards from.
     */
    function claimReward(uint256 tokenId) external nonReentrant whenNotPaused {
        UserInfo storage user = userInfo[msg.sender];
        require(user.stakedAmount[tokenId] == 1, "Token not staked by caller");
        updatePool(tokenId);

        uint256 pending = ((1 * poolInfo[tokenId].accRewardPerShare) / 1e12) - user.rewardDebt[tokenId];
        require(pending > 0, "No reward to claim");

        safeRewardTransfer(msg.sender, pending);
        user.rewardDebt[tokenId] = (1 * poolInfo[tokenId].accRewardPerShare) / 1e12;
        emit RewardClaimed(msg.sender, tokenId, pending);
    }

    /**
     * @dev Returns the pending reward for a user on a specific NFT token ID.
     * @param _user The user's address.
     * @param tokenId The NFT token ID.
     * @return The pending reward amount.
     */
    function pendingReward(address _user, uint256 tokenId) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[tokenId];
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        // Cap the block number for reward calculation at rewardEndBlock if set.
        uint256 currentBlock = (block.number > rewardEndBlock && rewardEndBlock > 0) ? rewardEndBlock : block.number;
        uint256 nftSupply = totalStakedNFTs[tokenId];

        if (currentBlock > pool.lastRewardBlock && nftSupply != 0) {
            uint256 multiplier = currentBlock - pool.lastRewardBlock;
            uint256 reward = multiplier * pool.rewardRatePerBlock;
            accRewardPerShare += (reward * 1e12) / nftSupply;
        }
        if (user.stakedAmount[tokenId] == 1) {
            return ((1 * accRewardPerShare) / 1e12) - user.rewardDebt[tokenId];
        } else {
            return 0;
        }
    }

    /**
     * @dev Sets the block number at which rewards should stop.
     * @param _rewardEndBlock The block number when rewards end.
     */
    function setRewardEndBlock(uint256 _rewardEndBlock) external onlyAdmin {
        rewardEndBlock = _rewardEndBlock;
        emit RewardEndBlockUpdated(_rewardEndBlock);
    }

    /**
     * @dev Transfers rewards safely, ensuring the contract has enough funds.
     */
    function safeRewardTransfer(address to, uint256 amount) internal {
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (amount > rewardBalance) {
            rewardToken.transfer(to, rewardBalance);
        } else {
            rewardToken.transfer(to, amount);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}
}
