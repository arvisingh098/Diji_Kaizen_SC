// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./interfaces/ITreasury.sol";
import "./Game/DijiKaizenGame.sol";

/**
 * @title DijiKaizenFactory
 * @dev Factory contract for deploying upgradable Diji Kaizen game contracts
 */
contract DijiKaizenFactory is Initializable, UUPSUpgradeable {
    // Addresses of dependent contracts
    ITreasury public treasuryContract;
    address public soulStakingContract;
    address public itemNFTContract;
    address public bakaBearNFTContract;
    address public gameImplementationContract;

    // Tracking deployed game instances
    address[] public deployedGames;

    address[] public acceptedToken;

    // Events
    event GameDeployed(address indexed gameAddress, string[] options);
    event ConfigsUpdated(
        address treasuryContract,
        address itemNFT,
        address soulStaking,
        address bakaBear,
        address gameImplementation,
        address[] acceptedToken
    );

    /// @custom:oz-upgrades-unsafe-allow constructro
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the factory with contract addresses
     * @param _treasuryContract Address of the treasuryContractAddress contract
     * @param _itemNFTContract Address of the item NFT contract
     * @param _soulStakingContract Address of the soul staking contract
     * @param _bakaBearNFTContract Address of the Baka Bear NFT contract
     * @param _gameImplementationContract Address of the Game logic contract
     * @param _acceptedToken Array of accepted token
     */
    function initialize(
        address _treasuryContract,
        address _itemNFTContract,
        address _soulStakingContract,
        address _bakaBearNFTContract,
        address _gameImplementationContract,
        address[] memory  _acceptedToken
    ) external initializer {
        treasuryContract = ITreasury(_treasury);
        itemNFTContract = _itemNFTContract;
        soulStakingContract = _soulStakingContract;
        bakaBearNFTContract = _bakaBearNFTContract;
        gameImplementationContract = _gameImplementationContract;
        acceptedToken =_acceptedToken;
        __UUPSUpgradeable_init();
    }

    /**
     * @dev Modifier to restrict function access to admins
     */
    modifier onlyAdmin() {
        require(treasuryContractAddress.isRoleAdmin(msg.sender), "Caller is not admin");
        _;
    }

    /**
     * @dev Deploys a new upgradable game contract using ERC1967 proxy
     * @param _options Voting options (string array)
     * @param _bakaBearAddress Address of Baka Bear NFT
     * @param _phase1StartTime Start of phase 1 (unix timestamp)
     * @param _phase1EndTime End of phase 1
     * @param _phase2StartTime Start of phase 2
     * @param _phase2EndTime End of phase 2
     */
    function deployGame(
        string[] memory _options,
        uint256 _phase1StartTime,
        uint256 _phase1EndTime,
        uint256 _phase2StartTime,
        uint256 _phase2EndTime,
    ) external onlyAdmin {
        bytes memory initData = abi.encodeWithSelector(
            DijiKaizenGame.initialize.selector,
            _options,
            _phase1StartTime,
            _phase1EndTime,
            _phase2StartTime,
            _phase2EndTime
        );

        ERC1967Proxy proxy = new ERC1967Proxy(gameImplementationContract, initData);
        deployedGames.push(address(proxy));
        emit GameDeployed(address(proxy),_phase1StartTime,_phase1EndTime,_phase2StartTime,_phase2EndTime, _options);
    }

    /**
     * @dev Allows admin to update dependent contract addresses
     * @param _treasury Address of the new treasuryContractAddress contract
     * @param _itemNFT Address of the new item NFT contract
     * @param _soulStaking Address of the new soul staking contract
     * @param _bakaBear Address of the new Baka Bear NFT contract
     * @param _gameImplementation Address of the new Game implementation contract
     * @param _acceptedToken Array of accepted token
     */
    function updateContractConfigs(
        address _treasury,
        address _itemNFT,
        address _soulStaking,
        address _bakaBear,
        address _gameImplementation,
        address[] _acceptedToken
    ) external onlyAdmin {
        treasuryContract = ITreasury(_treasury);
        itemNFTContract = _itemNFT;
        soulStakingContract = _soulStaking;
        bakaBearNFTContract = _bakaBear;
        gameImplementationContract = _gameImplementation;
        acceptedToken=_acceptedToken;
        emit ConfigsUpdated(_treasury, _itemNFT, _soulStaking, _bakaBear, _gameImplementation,_acceptedToken);
    }

    /**
     * @dev Returns all deployed game addresses
     */
    function getAllDeployedGames() external view returns (address[] memory) {
        return deployedGames;
    }

    /**
     * @dev Returns total number of deployed games
     */
    function getGameCount() external view returns (uint256) {
        return deployedGames.length;
    }

    /**
     * @dev Authorizes contract upgrades (UUPS)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}
}
