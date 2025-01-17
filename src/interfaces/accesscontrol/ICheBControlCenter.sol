// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title ICheBControlCenter
 * @author CheB Protocol
 * @notice Interface for the CheBControlCenter contract which manages administrative, verifier, 
 *         and executive roles within the CheB protocol.
 */
interface ICheBControlCenter {
    // Custom errors
    error InvalidAddress();

    // Role constants that need to be exposed
    function ADMIN_ROLE() external view returns (bytes32);
    function VERIFIER_ROLE() external view returns (bytes32);
    function EXECUTIVE_ROLE() external view returns (bytes32);

    /**
     * @notice Checks if an account has a specific role
     * @param role The role to check
     * @param account The account to check the role for
     * @return bool True if the account has the role
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @notice Allows only the contract owner (DEFAULT_ADMIN_ROLE) to grant or revoke roles.
     * @param account The address of the account to grant or revoke the role from.
     * @param role The role to be granted or revoked (ADMIN_ROLE, VERIFIER_ROLE, or EXECUTIVE_ROLE).
     * @param grant A boolean indicating whether to grant (true) or revoke (false) the role.
     */
    function setRole(address account, bytes32 role, bool grant) external;

    /**
     * @notice Allows only the contract owner (DEFAULT_ADMIN_ROLE) to toggle the emergency pause status.
     */
    function toggleEmergencyPause() external;

    /**
     * @notice Returns true if the contract is paused, and false otherwise.
     */
    function paused() external view returns (bool);
}