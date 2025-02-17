// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";


/**
 * @title CheBControlCenter
 * @author CheB Protocol
 * @notice This contract serves as a central access control and emergency stop mechanism for the CheB protocol.
 * It implements role-based access control to manage different administrative privileges and a blacklist to restrict access for specific addresses.
 * The contract owner, who is initially granted the DEFAULT_ADMIN_ROLE, can manage roles and pause critical functionalities in case of emergencies.
 */
contract CheBControlCenter is AccessControl, Pausable, ReentrancyGuard {
    /**
     * @dev Custom error thrown when an invalid address (zero address) is provided.
     */
    error InvalidAddress();

    /**
     * @dev Custom error thrown when an action is attempted by a blacklisted address.
     */
    error AddressBlacklisted();

    /**
     * @dev Custom error thrown when an invalid role is specified for operations like role setting.
     */
    error InvalidRole();

    /**
     * @dev Custom error thrown when attempting to remove a seller from the blacklist who is not blacklisted.
     */
    error SellerNotBlacklisted();


    // Role constants

    /**
     * @notice Role for highly privileged administrative tasks, capable of managing other roles and system-wide settings.
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /**
     * @notice Role for entities responsible for verification processes within the protocol, such as KYC or data validation.
     */
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    /**
     * @notice Role for executive-level operations, potentially involving strategic decisions or protocol upgrades.
     */
    bytes32 public constant EXECUTIVE_ROLE = keccak256("EXECUTIVE_ROLE");
    /**
     * @notice Role assigned to registered sellers on the platform, granting them permissions to list and sell items.
     */
    bytes32 public constant SELLER_ROLE = keccak256("SELLER_ROLE");


    /**
     * @notice Mapping to track addresses that are blacklisted from interacting with the platform.
     * Blacklisted addresses are restricted from performing certain actions.
     */
    mapping(address => bool) public blacklist;

    // Events

    /**
     * @dev Emitted when a role is granted to or revoked from an account.
     * @param account The address of the account whose role was modified.
     * @param role The role that was granted or revoked.
     * @param isGranted True if the role was granted, false if revoked.
     *
     * Emitted when the role status of an account is changed.
     */
    event RoleStatusChanged(address indexed account, bytes32 indexed role, bool isGranted);

    /**
     * @dev Emitted when the emergency pause state of the contract is toggled.
     * @param paused True if the contract is now paused, false if it's unpaused.
     *
     * Emitted when the contract's pause status is changed, indicating activation or deactivation of emergency pause.
     */
    event EmergencyAction(bool indexed paused);

    /**
     * @dev Emitted when a seller address is added to the blacklist.
     * @param seller The address of the seller that has been blacklisted.
     *
     * Emitted when a seller is blacklisted, restricting their platform access.
     */
    event SellerBlacklisted(address indexed seller);

    /**
     * @dev Emitted when a seller address is removed from the blacklist.
     * @param seller The address of the seller that has been removed from the blacklist.
     *
     * Emitted when a seller is unblacklisted, restoring their platform access.
     */
    event SellerUnblacklisted(address indexed seller);

    /**
     * @notice Constructor for the CheBControlCenter contract.
     *
     * Initializes the contract by setting up the role-based access control hierarchy and granting the deployer the DEFAULT_ADMIN_ROLE.
     * The deployer, as the DEFAULT_ADMIN_ROLE, gains the authority to manage other administrative roles.
     * Role hierarchy is configured as follows:
     * - `DEFAULT_ADMIN_ROLE` can manage `ADMIN_ROLE`, `VERIFIER_ROLE`, and `EXECUTIVE_ROLE`.
     * - `ADMIN_ROLE` can manage `SELLER_ROLE`.
     *
     * @dev Sets the deployer as the initial DEFAULT_ADMIN_ROLE and establishes role administration relationships.
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(VERIFIER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(EXECUTIVE_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(SELLER_ROLE, ADMIN_ROLE);
    }

    /**
     * @notice Grants or revokes a specific role to/from an account.
     *
     * This function allows the DEFAULT_ADMIN_ROLE to manage roles for different accounts within the system.
     * It supports setting roles such as `SELLER_ROLE`, `ADMIN_ROLE`, `VERIFIER_ROLE`, and `EXECUTIVE_ROLE`.
     * The function checks for invalid addresses (zero address) and blacklisted accounts before proceeding.
     * It is protected against reentrancy and is disabled when the contract is paused for emergency situations.
     *
     * @param account The address of the account to modify the role for. Must not be the zero address and must not be blacklisted.
     * @param role The role to grant or revoke. Must be one of the defined roles: `SELLER_ROLE`, `ADMIN_ROLE`, `VERIFIER_ROLE`, or `EXECUTIVE_ROLE`.
     * @param grant Boolean value indicating whether to grant (true) or revoke (false) the role.
     *
     * @custom:security Only callable by accounts with `DEFAULT_ADMIN_ROLE`.
     * @custom:access Requires `DEFAULT_ADMIN_ROLE`.
     * @custom:event Emits {RoleStatusChanged} event upon successful role modification.
     *
     *  InvalidAddress Thrown if `account` is the zero address.
     *  AddressBlacklisted Thrown if `account` is blacklisted.
     *  InvalidRole Thrown if `role` is not one of the supported roles.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     */
    function setRole(address account, bytes32 role, bool grant)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (account == address(0)) revert InvalidAddress();
        if (blacklist[account]) revert AddressBlacklisted();

        if (role == SELLER_ROLE) {
            if (grant) {
                _grantRole(SELLER_ROLE, account);
            } else {
                _revokeRole(SELLER_ROLE, account);
            }
        } else if (role == ADMIN_ROLE || role == VERIFIER_ROLE || role == EXECUTIVE_ROLE) {
            if (grant) {
                _grantRole(role, account);
            } else {
                _revokeRole(role, account);
            }
        } else {
            revert InvalidRole();
        }

        emit RoleStatusChanged(account, role, grant);
    }


    /**
     * @notice Blacklists a seller address, preventing them from further actions on the platform.
     *
     * This function is used to restrict access for malicious or non-compliant sellers.
     * Blacklisting revokes the `SELLER_ROLE` if the address holds it and adds the address to the blacklist mapping.
     * Only callable by accounts with `ADMIN_ROLE`.
     * Reverts if the provided address is invalid (zero address) or already blacklisted.
     *
     * @param seller The address of the seller to blacklist. Must not be the zero address and must not be already blacklisted.
     *
     * @custom:security Only callable by accounts with `ADMIN_ROLE`.
     * @custom:access Requires `ADMIN_ROLE`.
     * @custom:event Emits {SellerBlacklisted} event upon successful blacklisting.
     *
     *  InvalidAddress Thrown if `seller` is the zero address.
     *  AddressBlacklisted Thrown if `seller` is already blacklisted.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     */
    function blacklistSeller(address seller)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (seller == address(0)) revert InvalidAddress();
        if (blacklist[seller]) revert AddressBlacklisted();


        if (hasRole(SELLER_ROLE, seller)) {
            _revokeRole(SELLER_ROLE, seller);
        }

        blacklist[seller] = true;
        emit SellerBlacklisted(seller);
    }

    /**
     * @notice Removes a seller address from the blacklist, restoring their platform access.
     *
     * This function allows unblocking sellers who were previously blacklisted.
     * Only callable by accounts with `ADMIN_ROLE`.
     * Reverts if the provided address is invalid (zero address) or not currently blacklisted.
     *
     * @param seller The address of the seller to remove from the blacklist. Must not be the zero address and must be currently blacklisted.
     *
     * @custom:security Only callable by accounts with `ADMIN_ROLE`.
     * @custom:access Requires `ADMIN_ROLE`.
     * @custom:event Emits {SellerUnblacklisted} event upon successful unblacklisting.
     *
     *  InvalidAddress Thrown if `seller` is the zero address.
     *  SellerNotBlacklisted Thrown if `seller` is not currently blacklisted.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     */
    function removeFromBlacklist(address seller)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (seller == address(0)) revert InvalidAddress();
        if (!blacklist[seller]) revert SellerNotBlacklisted();

        blacklist[seller] = false;
        emit SellerUnblacklisted(seller);
    }


    /**
     * @notice Toggles the emergency pause state of the contract.
     *
     * This function allows the DEFAULT_ADMIN_ROLE to pause and unpause the contract in case of emergencies.
     * When paused, certain functionalities, especially those modifying state, are restricted by the `whenNotPaused` modifier.
     * Only callable by accounts with `DEFAULT_ADMIN_ROLE`.
     *
     * @custom:security Only callable by accounts with `DEFAULT_ADMIN_ROLE`.
     * @custom:access Requires `DEFAULT_ADMIN_ROLE`.
     * @custom:event Emits {EmergencyAction} event upon toggling the pause state.
     */
    function toggleEmergencyPause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }

        emit EmergencyAction(paused());
    }

    /**
     * @notice Checks if an address is a verified seller and is not blacklisted.
     *
     * This view function is used to determine if an account is considered a verified and active seller on the platform.
     * It checks if the account holds the `SELLER_ROLE` and is not present in the blacklist.
     *
     * @param account The address to check for verified seller status.
     * @return True if the address has the `SELLER_ROLE` and is not blacklisted, false otherwise.
     */
    function isVerifiedSeller(address account) external view returns (bool) {
        return hasRole(SELLER_ROLE, account) && !blacklist[account];
    }
}