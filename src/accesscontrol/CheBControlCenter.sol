// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CheBControlCenter
 * @author CheB Protocol
 * @notice This contract serves as a control center for managing administrative, verifier, and executive roles within the CheB protocol.
 *         It allows the contract owner to grant or revoke these roles and toggle the emergency pause status.
 */
contract CheBControlCenter is AccessControl, Pausable, ReentrancyGuard {
    // Custom errors
    error InvalidAddress();

    // Role constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant EXECUTIVE_ROLE = keccak256("EXECUTIVE_ROLE");

    // Events
    event RoleStatusChanged(address indexed account, bytes32 indexed role, bool isGranted);
    event EmergencyAction(bool indexed paused);

    /**
     * @notice Constructor that sets the contract deployer as the default admin.
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(VERIFIER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(EXECUTIVE_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /**
     * @notice Allows only the contract owner (DEFAULT_ADMIN_ROLE) to grant or revoke roles.
     * @param account The address of the account to grant or revoke the role from.
     * @param role The role to be granted or revoked (ADMIN_ROLE, VERIFIER_ROLE, or EXECUTIVE_ROLE).
     * @param grant A boolean indicating whether to grant (true) or revoke (false) the role.
     */
    function setRole(address account, bytes32 role, bool grant) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant 
        whenNotPaused
    {
        if (account == address(0)) revert InvalidAddress();
        if (role != ADMIN_ROLE && role != VERIFIER_ROLE && role != EXECUTIVE_ROLE) revert InvalidAddress();
        if (grant) {
            grantRole(role, account);
        } else {
            revokeRole(role, account);
        }
        emit RoleStatusChanged(account, role, grant);
    }

    /**
     * @notice Allows only the contract owner (DEFAULT_ADMIN_ROLE) to toggle the emergency pause status.
     */
    function toggleEmergencyPause() 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
        
        emit EmergencyAction(paused());
    }
}