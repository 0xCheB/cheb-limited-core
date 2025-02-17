// ICheBControlCenter.sol (Interface)
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title ICheBControlCenter
 * @author CheB Protocol
 * @notice Interface for the CheBControlCenter contract, defining its external API for access control and emergency actions.
 * @dev This interface outlines the functions available on the CheBControlCenter contract, which manages roles, blacklists, and pause functionality within the CheB protocol.
 * Contracts interacting with the CheBControlCenter should use this interface to ensure compatibility and proper function calls.
 */
interface ICheBControlCenter {
    /**
     * @dev Custom error thrown when an invalid address (zero address) is provided to the implementing contract.
     * @dev This error is expected to be thrown by implementations when an address parameter is checked and found to be the zero address.
     */
    error InvalidAddress();

    /**
     * @dev Custom error thrown when an action is attempted by a blacklisted address in the implementing contract.
     * @dev Implementations should throw this error to prevent blacklisted addresses from performing certain actions.
     */
    error AddressBlacklisted();

    /**
     * @dev Custom error thrown when an invalid role is specified for an operation in the implementing contract.
     * @dev Implementations should throw this error when a provided role identifier is not recognized or supported for a particular function.
     */
    error InvalidRole();

    /**
     * @dev Custom error thrown when attempting to remove a seller from the blacklist in the implementing contract, but the seller is not currently blacklisted.
     * @dev Implementations should throw this error to prevent accidental removal of sellers who are not on the blacklist.
     */
    error SellerNotBlacklisted();

    /**
     * @notice Returns the bytes32 representation of the DEFAULT_ADMIN_ROLE.
     * @return bytes32 The bytes32 value representing the DEFAULT_ADMIN_ROLE.
     *
     * @dev This role is the highest level administrative role, capable of managing other roles and system-wide settings.
     * Implementations should define and return the keccak256 hash of "DEFAULT_ADMIN_ROLE".
     */
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32); // ADDED: Definition for DEFAULT_ADMIN_ROLE

    /**
     * @notice Returns the bytes32 representation of the ADMIN_ROLE.
     * @return bytes32 The bytes32 value representing the ADMIN_ROLE.
     *
     * @dev This role is for general administrative tasks within the protocol, with broad permissions but potentially less than DEFAULT_ADMIN_ROLE.
     * Implementations should define and return the keccak256 hash of "ADMIN_ROLE".
     */
    function ADMIN_ROLE() external view returns (bytes32);

    /**
     * @notice Returns the bytes32 representation of the VERIFIER_ROLE.
     * @return bytes32 The bytes32 value representing the VERIFIER_ROLE.
     *
     * @dev This role is for accounts responsible for verification processes within the protocol, such as KYC or data validation.
     * Implementations should define and return the keccak256 hash of "VERIFIER_ROLE".
     */
    function VERIFIER_ROLE() external view returns (bytes32);

    /**
     * @notice Returns the bytes32 representation of the EXECUTIVE_ROLE.
     * @return bytes32 The bytes32 value representing the EXECUTIVE_ROLE.
     *
     * @dev This role is for executive-level operations, potentially involving strategic decisions or protocol upgrades.
     * Implementations should define and return the keccak256 hash of "EXECUTIVE_ROLE".
     */
    function EXECUTIVE_ROLE() external view returns (bytes32);

    /**
     * @notice Returns the bytes32 representation of the SELLER_ROLE.
     * @return bytes32 The bytes32 value representing the SELLER_ROLE.
     *
     * @dev This role is assigned to registered sellers on the platform, granting them permissions related to selling and listing items.
     * Implementations should define and return the keccak256 hash of "SELLER_ROLE".
     */
    function SELLER_ROLE() external view returns (bytes32);

    /**
     * @notice Checks if an address is blacklisted.
     * @param addr The address to check for blacklist status.
     * @return bool True if the address is blacklisted, false otherwise.
     *
     * @dev Implementations should provide a view function to check if a given address is currently blacklisted.
     * Blacklisted addresses are restricted from performing certain actions within the protocol.
     */
    function blacklist(address addr) external view returns (bool);

    /**
     * @notice Grants or revokes a role for an account.
     * @param account The address of the account to modify the role for.
     * @param role The role to grant or revoke.
     * @param grant True to grant the role, false to revoke it.
     *
     * @dev Implementations should provide a function to allow authorized roles (like DEFAULT_ADMIN_ROLE) to grant or revoke roles for other accounts.
     * This function should handle different roles such as ADMIN_ROLE, VERIFIER_ROLE, EXECUTIVE_ROLE, and SELLER_ROLE.
     */
    function setRole(address account, bytes32 role, bool grant) external;

    /**
     * @notice Blacklists a seller address, preventing them from participating in the platform.
     * @param seller The address of the seller to blacklist.
     *
     * @dev Implementations should provide a function to blacklist a seller address.
     * Blacklisting should prevent the seller from performing seller-related actions and may revoke their SELLER_ROLE.
     * Only callable by accounts with appropriate roles (e.g., ADMIN_ROLE).
     */
    function blacklistSeller(address seller) external;

    /**
     * @notice Removes a seller from the blacklist, allowing them to participate again.
     * @param seller The address of the seller to remove from the blacklist.
     *
     * @dev Implementations should provide a function to remove a seller from the blacklist.
     * This function should allow previously blacklisted sellers to regain access to the platform.
     * Only callable by accounts with appropriate roles (e.g., ADMIN_ROLE).
     *
     */
    function removeFromBlacklist(address seller) external;

    /**
     * @notice Toggles the emergency pause state of the contract.
     *
     * @dev Implementations should provide a function to toggle the pause state of the contract.
     * When paused, certain functionalities may be restricted. Only callable by accounts with appropriate roles (e.g., DEFAULT_ADMIN_ROLE).
     *
     */
    function toggleEmergencyPause() external;

    /**
     * @notice Checks if the contract is currently paused.
     * @return bool True if the contract is paused, false otherwise.
     *
     * @dev Implementations should provide a view function to check the current pause state of the contract.
     * Other contracts can use this to determine if certain functionalities are currently restricted due to a pause.
     */
    function paused() external view returns (bool);

    /**
     * @notice Checks if an account has a specific role.
     * @param role The role to check for.
     * @param account The address of the account to check.
     * @return bool True if the account has the role, false otherwise.
     *
     * @dev Implementations should provide a view function to check if a given account possesses a specific role.
     * This is a standard function from AccessControl to verify role-based permissions.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @notice Checks if an address is a verified seller and not blacklisted.
     * @param account The address to check.
     * @return bool True if the address is a verified seller and not blacklisted, false otherwise.
     *
     * @dev Implementations should provide a view function to determine if an address is considered a verified and active seller.
     * This typically involves checking if the address has the SELLER_ROLE and is not blacklisted.
     */
    function isVerifiedSeller(address account) external view returns (bool);
}