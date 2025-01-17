// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../accesscontrol/ICheBControlCenter.sol";

/**
 * @title ICheBListing Interface
 * @notice Interface for managing whitelist and blacklist functionality in the CheB Protocol
 * @dev Defines the interface for address listing management with CheBControlCenter integration
 * 
 * This interface provides functionality to:
 * - Whitelist/blacklist addresses individually or in batches
 * - Remove addresses from whitelist/blacklist
 * - Prevent blacklisted addresses from being whitelisted
 * - Query listing status of addresses
 * 
 * @custom:security-contact security@cheb.co
 */
interface ICheBListing {
    // Events
    event AddressesWhitelisted(address[] addresses);
    event AddressesRemovedFromWhitelist(address[] addresses);
    event AddressesBlacklisted(address[] addresses);
    event AddressesRemovedFromBlacklist(address[] addresses);
    
    // Custom errors
    error EmptyArray();
    error BatchTooLarge();
    error ZeroAddress();
    error AlreadyWhitelisted();
    error NotWhitelisted();
    error AlreadyBlacklisted();
    error NotBlacklisted();
    error AddressBlacklisted();
    error NotAdmin();
    error ChebCenterPaused();
    error InvalidChebCenter();

    /**
     * @notice Returns the ChebControlCenter contract instance
     * @return ICheBControlCenter The control center contract interface
     */
    function chebCenter() external view returns (ICheBControlCenter);

    /**
     * @notice Checks if an address is whitelisted
     * @param account The address to check
     * @return bool True if the address is whitelisted
     */
    function whitelist(address account) external view returns (bool);

    /**
     * @notice Checks if an address is blacklisted
     * @param account The address to check
     * @return bool True if the address is blacklisted
     */
    function blacklist(address account) external view returns (bool);

    /**
     * @notice Adds multiple addresses to the whitelist
     * @dev Batch operation to whitelist addresses
     * @param addresses Array of addresses to whitelist
     * 
     * Requirements:
     * - Caller must be an admin in ChebControlCenter
     * - Neither this contract nor ChebControlCenter must be paused
     * - Addresses array must not be empty and not exceed MAX_BATCH_SIZE
     * - Addresses must not be blacklisted
     * - Addresses must not be already whitelisted
     * 
     * Emits an {AddressesWhitelisted} event
     */
    function addToWhitelist(address[] calldata addresses) external;

    /**
     * @notice Removes multiple addresses from the whitelist
     * @dev Batch operation to remove addresses from whitelist
     * @param addresses Array of addresses to remove from whitelist
     * 
     * Requirements:
     * - Caller must be an admin in ChebControlCenter
     * - Neither this contract nor ChebControlCenter must be paused
     * - Addresses array must not be empty and not exceed MAX_BATCH_SIZE
     * - Addresses must be currently whitelisted
     * 
     * Emits an {AddressesRemovedFromWhitelist} event
     */
    function removeFromWhitelist(address[] calldata addresses) external;

    /**
     * @notice Adds multiple addresses to the blacklist
     * @dev Batch operation to blacklist addresses
     * @param addresses Array of addresses to blacklist
     * 
     * Requirements:
     * - Caller must be an admin in ChebControlCenter
     * - Neither this contract nor ChebControlCenter must be paused
     * - Addresses array must not be empty and not exceed MAX_BATCH_SIZE
     * - Addresses must not be already blacklisted
     * 
     * Side Effects:
     * - Automatically removes addresses from whitelist if they are whitelisted
     * 
     * Emits an {AddressesBlacklisted} event
     */
    function addToBlacklist(address[] calldata addresses) external;

    /**
     * @notice Removes multiple addresses from the blacklist
     * @dev Batch operation to remove addresses from blacklist
     * @param addresses Array of addresses to remove from blacklist
     * 
     * Requirements:
     * - Caller must be an admin in ChebControlCenter
     * - Neither this contract nor ChebControlCenter must be paused
     * - Addresses array must not be empty and not exceed MAX_BATCH_SIZE
     * - Addresses must be currently blacklisted
     * 
     * Emits an {AddressesRemovedFromBlacklist} event
     */
    function removeFromBlacklist(address[] calldata addresses) external;

    /**
     * @notice Checks whitelist status for multiple addresses
     * @dev Batch operation to check whitelist status
     * @param accounts Array of addresses to check
     * @return bool[] Array of boolean values indicating whitelist status
     */
    function areWhitelisted(address[] calldata accounts) external view returns (bool[] memory);

    /**
     * @notice Checks blacklist status for multiple addresses
     * @dev Batch operation to check blacklist status
     * @param accounts Array of addresses to check
     * @return bool[] Array of boolean values indicating blacklist status
     */
    function areBlacklisted(address[] calldata accounts) external view returns (bool[] memory);

    /**
     * @notice Pauses all listing operations
     * @dev Can only be called by ChebControlCenter admin when ChebControlCenter is not paused
     */
    function pause() external;

    /**
     * @notice Resumes all listing operations
     * @dev Can only be called by ChebControlCenter admin when ChebControlCenter is not paused
     */
    function unpause() external;
}