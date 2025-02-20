// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Import OpenZeppelin contracts
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Treasury is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    // Define roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    // Events
    event AdminRoleGranted(address indexed account, address by);
    event TreasurerRoleGranted(address indexed account, address by);
    event FundsWithdrawn(IERC20 indexed token, address to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initialize the contract with the default admin role.
     * @param defaultAdmin The address to be set as the default admin.
     */
    function initialize(address defaultAdmin) public initializer {
        // Initialize AccessControl and UUPS
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Set the default admin role
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /**
     * @dev Grant the TREASURER_ROLE to an address. Can only be called by the DEFAULT_ADMIN_ROLE.
     * @param account The address to grant the TREASURER_ROLE.
     */
    function grantTreasurerRole(address account) external {
        grantRole(TREASURER_ROLE, account);
        emit TreasurerRoleGranted(account, msg.sender);
    }

  /**
     * @dev Grant the ADMIN_ROLE to an address. Can only be called by the DEFAULT_ADMIN_ROLE.
     * @param account The address to grant the ADMIN_ROLE.
     */
    function grantAdminRole(address account) external {
        grantRole(ADMIN_ROLE, account);
        emit AdminRoleGranted(account, msg.sender);
    }

    /**
     * @dev Withdraw funds from the contract. Can only be called by the TREASURER_ROLE.
     * @param tokenAddress The address of the ERC20 token to withdraw.
     * @param to The address to send the funds to.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawFunds(IERC20 tokenAddress, address to, uint256 amount) external onlyRole(TREASURER_ROLE) {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        require(tokenAddress.transfer(to, amount), "Transfer failed");

        emit FundsWithdrawn(tokenAddress, to, amount);
    }

   /**
     * @dev Check if an address has the ADMIN_ROLE.
     * @param account The address to check.
     * @return bool True if the address has the ADMIN_ROLE, false otherwise.
     */
    function isRoleAdmin(address account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    /**
     * @dev Check if an address has the TREASURER_ROLE.
     * @param account The address to check.
     * @return bool True if the address has the TREASURER_ROLE, false otherwise.
     */
    function isRoleTreasurer(address account) external view returns (bool) {
        return hasRole(TREASURER_ROLE, account);
    }

    /**
     * @dev Internal function to authorize upgrades. Only the DEFAULT_ADMIN_ROLE can upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}