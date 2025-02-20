// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Import OpenZeppelin contracts
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Import the ITreasury interface
import "../interface/ITreasury.sol";

contract GameContract is Initializable, UUPSUpgradeable {
    // State variable to store the treasury contract address
    ITreasury private _treasury;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Modifier to check if the caller is an admin.
     */
    modifier isAdmin() {
        require(_treasury.isRoleAdmin(msg.sender), "GameFactory: Caller is not an admin");
        _;
    }
    
    /**
     * @dev Initialize the game contract.
     * @param treasuryAddress The address of the treasury contract implementing ITreasury.
     */
    function initialize(address treasuryAddress) public initializer {
        __UUPSUpgradeable_init();
        _treasury = ITreasury(treasuryAddress); // Set the treasury contract address
    }

    /**
     * @dev Get the treasury contract address.
     * @return The address of the treasury contract.
     */
    function getTreasuryAddress() external view returns (address) {
        return address(_treasury);
    }

       /**
     * @dev Internal function to authorize upgrades. Only an admin can upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override isAdmin {}
}