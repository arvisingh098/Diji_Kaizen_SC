// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/ITreasury.sol";

/**
 * @title DijiKaizenGame
 * @dev Main game contract for Phase 1 voting and bribing
 */
contract DijiKaizenGame is Initializable, UUPSUpgradeable, ERC721HolderUpgradeable {
    enum BribeType { Corruption, VoteDirection }

    struct BribeOffer {
        address briber;
        BribeType bribeType;
        address token;
        uint256 amount;
        address target;
        uint256[] tokenIds;
        uint256[] forcedOptions;
        bool accepted;
        bool claimed;
    }

    struct BribeDirection {
        bool isLocked;
        uint256 voteOption;
    }

    address public factoryContract;
    string[] public options;
    uint256 public phase1Start;
    uint256 public phase1End;
    uint256 public phase2Start;
    uint256 public phase2End;

    bool public isPhase1ResultPublished;
    uint256 public winningOptionIndex;

    mapping(uint256 => address) public tokenController;
    mapping(uint256 => address) public tokenOriginalOwner;
    mapping(uint256 => uint256) public tokenVotedOption;
    mapping(uint256 => BribeDirection) public bribeLock;

    uint256[] public allStakedTokens;

    address[] public acceptedBribeTokens;
    mapping(BribeType => mapping(address => uint256)) public minimumBribePrice;
    BribeOffer[] public bribeOffers;

    event StakedAndVoted(address indexed user, uint256[] tokenIds, uint256[] choices);
    event BribeOffered(uint256 indexed bribeId, address indexed briber, BribeType bribeType);
    event BribeAccepted(uint256 indexed bribeId);
    event BribeClaimed(uint256 indexed bribeId);
    event CorruptionBribeExecuted(uint256[] tokenIds, address newController);
    event VoteDirectionBribeExecuted(uint256[] tokenIds, uint256[] voteOptions);
    event Phase1ResultPublished(uint256 winningOption);

    modifier onlyAdmin() {
        address treasury = IFactory(factoryContract).treasuryContract();
        require(ITreasury(treasury).isRoleAdmin(msg.sender), "Not authorized");
        _;
    }

    modifier phase1Active() {
        require(block.timestamp >= phase1Start && block.timestamp <= phase1End, "Phase 1 inactive");
        _;
    }

    /**
     * @dev Initializes the contract
     * @param _options Voting options
     * @param _phase1Start Phase 1 start time
     * @param _phase1End Phase 1 end time
     * @param _phase2Start Phase 2 start time
     * @param _phase2End Phase 2 end time
     */
    function initialize(
        string[] memory _options,
        uint256 _phase1Start,
        uint256 _phase1End,
        uint256 _phase2Start,
        uint256 _phase2End
    ) external initializer {
        require(_options.length >= 2 && _options.length <= 3, "Invalid option count");
        require(_phase1Start < _phase1End && _phase2Start < _phase2End, "Invalid phase timing");

        options = _options;
        factoryContract = msg.sender;
        phase1Start = _phase1Start;
        phase1End = _phase1End;
        phase2Start = _phase2Start;
        phase2End = _phase2End;

        __UUPSUpgradeable_init();
        __ERC721Holder_init();
    }

    /**
     * @dev Stakes NFTs and casts votes
     * @param tokenIds Token IDs to stake
     * @param optionIndices Voting option index for each token
     */
    function stakeAndVote(uint256[] calldata tokenIds, uint256[] calldata optionIndices) external phase1Active {
        require(tokenIds.length == optionIndices.length, "Mismatched lengths");

        IERC721 bakaBearNFT = IERC721(IFactory(factoryContract).bakaBearNFTContract());

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 optionIndex = optionIndices[i];
            require(optionIndex < options.length, "Invalid option");

            bakaBearNFT.transferFrom(msg.sender, address(this), tokenId);
            tokenOriginalOwner[tokenId] = msg.sender;
            tokenController[tokenId] = msg.sender;
            tokenVotedOption[tokenId] = optionIndex;
            allStakedTokens.push(tokenId);
        }
        emit StakedAndVoted(msg.sender, tokenIds, optionIndices);
    }

    /**
     * @dev Offers a bribe
     */
    function offerBribe(
        BribeType bribeType,
        address token,
        uint256 amount,
        address target,
        uint256[] calldata tokenIds,
        uint256[] calldata forcedOptions
    ) external {
        require(_isValidBribe(token, amount, bribeType), "Invalid bribe");
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        bribeOffers.push(BribeOffer({
            briber: msg.sender,
            bribeType: bribeType,
            token: token,
            amount: amount,
            target: target,
            tokenIds: tokenIds,
            forcedOptions: forcedOptions,
            accepted: false,
            claimed: false
        }));

        emit BribeOffered(bribeOffers.length - 1, msg.sender, bribeType);
    }

    /**
     * @dev Accepts a bribe and applies the effect
     * @param bribeId ID of the bribe offer
     */
    function acceptBribe(uint256 bribeId) external {
        BribeOffer storage offer = bribeOffers[bribeId];
        require(!offer.accepted, "Already accepted");
        require(offer.target == msg.sender, "Not target");

        offer.accepted = true;

        if (offer.bribeType == BribeType.Corruption) {
            for (uint256 i = 0; i < offer.tokenIds.length; i++) {
                tokenController[offer.tokenIds[i]] = offer.briber;
            }
            emit CorruptionBribeExecuted(offer.tokenIds, offer.briber);
        } else {
            for (uint256 i = 0; i < offer.tokenIds.length; i++) {
                bribeLock[offer.tokenIds[i]] = BribeDirection({
                    isLocked: true,
                    voteOption: offer.forcedOptions[i]
                });
                tokenVotedOption[offer.tokenIds[i]] = offer.forcedOptions[i];
            }
            emit VoteDirectionBribeExecuted(offer.tokenIds, offer.forcedOptions);
        }

        emit BribeAccepted(bribeId);
    }

    /**
     * @dev Claims back unaccepted bribes after Phase 1
     * @param bribeId ID of the bribe offer
     */
    function claimUnacceptedBribe(uint256 bribeId) external {
        BribeOffer storage offer = bribeOffers[bribeId];
        require(!offer.accepted && !offer.claimed, "Not claimable");
        require(block.timestamp > phase1End, "Phase 1 not over");
        require(offer.briber == msg.sender, "Not briber");

        offer.claimed = true;
        IERC20(offer.token).transfer(offer.briber, offer.amount);
        emit BribeClaimed(bribeId);
    }

    /**
     * @dev Publishes the Phase 1 result
     * @param _winningOptionIndex Index of winning option
     */
    function publishPhase1Result(uint256 _winningOptionIndex) external onlyAdmin {
        require(!isPhase1ResultPublished, "Already published");
        require(block.timestamp > phase1End, "Phase 1 not ended");
        require(_winningOptionIndex < options.length, "Invalid option");

        winningOptionIndex = _winningOptionIndex;
        isPhase1ResultPublished = true;

        emit Phase1ResultPublished(_winningOptionIndex);
    }

    /**
     * @dev Internal validation function for bribes
     */
    function _isValidBribe(address token, uint256 amount, BribeType bribeType) internal view returns (bool) {
        address[] memory acceptedToken = IFactory(factoryContract).acceptedToken();
        uint256 minimumBribe;
        if(bribeType == BribeType.Corruption){
            minimumBribe = IFactory(factoryContract).minimumCorruptionBribe();
        }
        else{
             minimumBribe = IFactory(factoryContract).minimumVotingDirectionBribe();
        }
        for (uint256 i = 0; i < acceptedToken.length; i++) {
            if (acceptedToken[i] == token) {
                return amount >= minimumBribe;
            }
        }
        return false;
    }

    /** @dev Authorization for UUPS upgrade */
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}

    /** @dev Returns game voting options */
    function getOptions() external view returns (string[] memory) {
        return options;
    }
}
