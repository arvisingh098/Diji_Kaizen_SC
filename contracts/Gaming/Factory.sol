// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Import OpenZeppelin contracts
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./Game/Game.sol";

// Import the ITreasury interface
import "./interface/ITreasury.sol";

contract GameFactory is Initializable, UUPSUpgradeable {
    // State variables
    uint256 public contractCounter; // Ticker for contract IDs
    mapping(uint256 => address) private _deployedContracts; // Stores deployed contract addresses by ID
    ITreasury private _treasury; // Treasury contract to validate admin role

    // Events
    event GameContractDeployed(uint256 indexed id, address indexed contractAddress);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initialize the factory contract.
     * @param treasuryAddress The address of the treasury contract implementing ITreasury.
     */
    function initialize(address treasuryAddress) public initializer {
        __UUPSUpgradeable_init();
        _treasury = ITreasury(treasuryAddress); // Set the treasury contract address
    }

    /**
     * @dev Modifier to check if the caller is an admin.
     */
    modifier isAdmin() {
        require(_treasury.isRoleAdmin(msg.sender), "GameFactory: Caller is not an admin");
        _;
    }

    /**
     * @dev Deploy a new game contract. Only callable by an admin.
     */
    function deployGameContract() external isAdmin {
        // Increment the contract counter
        contractCounter++;

        // Deploy a new game contract
        GameContract newContract = new GameContract();
        address newContractAddress = address(newContract);

        // Initialize the game contract with the treasury address
        GameContract(newContractAddress).initialize(address(_treasury));

        // Store the deployed contract address
        _deployedContracts[contractCounter] = newContractAddress;

        // Emit an event
        emit GameContractDeployed(contractCounter, newContractAddress);
    }

    /**
     * @dev Get the address of a deployed contract by ID.
     * @param id The ID of the deployed contract.
     * @return The address of the deployed contract.
     */
    function getDeployedContract(uint256 id) external view returns (address) {
        require(_deployedContracts[id] != address(0), "GameFactory: Invalid contract ID");
        return _deployedContracts[id];
    }

    /**
     * @dev Internal function to authorize upgrades. Only an admin can upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override isAdmin {}
}