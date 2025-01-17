// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/accesscontrol/ICheBControlCenter.sol";

/**
 * @title CheBListing Contract
 * @notice Manages whitelist and blacklist functionality for the CheB Protocol
 * @dev Implements address listing management with CheBControlCenter integration for admin access
 * 
 * The CheBListing contract provides functionality to:
 * - Whitelist/blacklist addresses individually or in batches
 * - Remove addresses from whitelist/blacklist
 * - Prevent blacklisted addresses from being whitelisted
 * - Query listing status of addresses
 * 
 * Security Features:
 * - Integration with CheBControlCenter for admin verification
 * - Reentrancy protection on state-modifying functions
 * - Pausable functionality for emergency situations
 * - Batch operation limits to prevent gas issues
 * - Custom error messages for efficient gas usage
 * 
 * @custom:security-contact security@cheb.co
 */
contract CheBListing is ReentrancyGuard, Pausable {
    // Constants
    uint256 private constant MAX_BATCH_SIZE = 50;

    // State variables
    ICheBControlCenter public immutable chebCenter;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public blacklist;
    
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
     * @notice Modifier to check if caller has ADMIN_ROLE in ChebControlCenter
     * Also checks if ChebControlCenter is not paused
     */
    modifier onlyAdmin() {
        try chebCenter.paused() returns (bool isPaused) {
            if (isPaused) revert ChebCenterPaused();
        } catch {
            revert InvalidChebCenter();
        }
        
        if (!_hasRole(chebCenter.ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }
    
    /**
     * @notice Helper function to check if an address has a specific role
     * @dev Uses try-catch to handle potential revert cases
     * @param role The role to check
     * @param account The address to check
     * @return bool True if the address has the role
     */
    function _hasRole(bytes32 role, address account) internal view returns (bool) {
        try AccessControl(address(chebCenter)).hasRole(role, account) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Initializes the CheBListing contract
     * @dev Sets up the CheBControlCenter reference and validates interface
     * @param _chebCenter Address of the CheBControlCenter contract
     */
    constructor(address _chebCenter) {
        if (_chebCenter == address(0)) revert ZeroAddress();
        
        // Validate interface implementation
        ICheBControlCenter center = ICheBControlCenter(_chebCenter);
        try AccessControl(address(center)).hasRole(center.ADMIN_ROLE(), msg.sender) returns (bool) {} catch { 
            revert InvalidChebCenter(); 
        }
        
        chebCenter = center;
    }
    
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
    function addToWhitelist(address[] calldata addresses)
        external
        onlyAdmin
        nonReentrant
        whenNotPaused
    {
        if (addresses.length == 0) revert EmptyArray();
        if (addresses.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < addresses.length;) {
            address account = addresses[i];
            if (account == address(0)) revert ZeroAddress();
            if (blacklist[account]) revert AddressBlacklisted();
            if (whitelist[account]) revert AlreadyWhitelisted();

            whitelist[account] = true;

            unchecked { ++i; }
        }

        emit AddressesWhitelisted(addresses);
    }
    
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
    function removeFromWhitelist(address[] calldata addresses)
        external
        onlyAdmin
        nonReentrant
        whenNotPaused
    {
        if (addresses.length == 0) revert EmptyArray();
        if (addresses.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < addresses.length;) {
            address account = addresses[i];
            if (!whitelist[account]) revert NotWhitelisted();

            whitelist[account] = false;

            unchecked { ++i; }
        }

        emit AddressesRemovedFromWhitelist(addresses);
    }
    
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
    function addToBlacklist(address[] calldata addresses)
        external
        onlyAdmin
        nonReentrant
        whenNotPaused
    {
        if (addresses.length == 0) revert EmptyArray();
        if (addresses.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < addresses.length;) {
            address account = addresses[i];
            if (account == address(0)) revert ZeroAddress();
            if (blacklist[account]) revert AlreadyBlacklisted();

            // Remove from whitelist if present
            if (whitelist[account]) {
                whitelist[account] = false;
            }

            blacklist[account] = true;

            unchecked { ++i; }
        }

        emit AddressesBlacklisted(addresses);
    }
    
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
    function removeFromBlacklist(address[] calldata addresses)
        external
        onlyAdmin
        nonReentrant
        whenNotPaused
    {
        if (addresses.length == 0) revert EmptyArray();
        if (addresses.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < addresses.length;) {
            address account = addresses[i];
            if (!blacklist[account]) revert NotBlacklisted();

            blacklist[account] = false;

            unchecked { ++i; }
        }

        emit AddressesRemovedFromBlacklist(addresses);
    }
    
    /**
     * @notice Checks whitelist status for multiple addresses
     * @dev Batch operation to check whitelist status
     * @param accounts Array of addresses to check
     * @return bool[] Array of boolean values indicating whitelist status
     */
    function areWhitelisted(address[] calldata accounts) 
        external 
        view 
        returns (bool[] memory) 
    {
        if (accounts.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        
        bool[] memory results = new bool[](accounts.length);
        for (uint256 i = 0; i < accounts.length;) {
            results[i] = whitelist[accounts[i]];
            unchecked { ++i; }
        }
        return results;
    }
    
    /**
     * @notice Checks blacklist status for multiple addresses
     * @dev Batch operation to check blacklist status
     * @param accounts Array of addresses to check
     * @return bool[] Array of boolean values indicating blacklist status
     */
    function areBlacklisted(address[] calldata accounts) 
        external 
        view 
        returns (bool[] memory) 
    {
        if (accounts.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        
        bool[] memory results = new bool[](accounts.length);
        for (uint256 i = 0; i < accounts.length;) {
            results[i] = blacklist[accounts[i]];
            unchecked { ++i; }
        }
        return results;
    }

    /**
     * @notice Pauses all listing operations
     * @dev Can only be called by ChebControlCenter admin when ChebControlCenter is not paused
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @notice Resumes all listing operations
     * @dev Can only be called by ChebControlCenter admin when ChebControlCenter is not paused
     */
    function unpause() external onlyAdmin {
        _unpause();
    }
}