// ICheBProofOfPurchaseFactory.sol (Interface)
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./ICheBProofOfPurchase.sol";
import "./ICheBSubscription.sol";
import "./ICheBControlCenter.sol";

/**
 * @title ICheBProofOfPurchaseFactory
 * @author CheB Protocol
 * @notice Interface for the CheBProofOfPurchaseFactory contract, defining the API for creating and managing SKU-based ERC1155 tokens.
 * @dev This interface outlines the external functions and data structures of the CheBProofOfPurchaseFactory contract.
 * It provides functionalities for deploying new CheBProofOfPurchase contracts, managing SKU sizes and prices, and controlling subscription tier access to SKUs.
 * Contracts interacting with the CheBProofOfPurchaseFactory should use this interface to ensure proper function calls and data handling.
 */
interface ICheBProofOfPurchaseFactory {
    /**
     * @dev Custom error thrown when an operation is attempted on a non-existent SKU.
     * @dev Implementations should revert with this error if a given SKU identifier does not correspond to a deployed CheBProofOfPurchase contract.
     */
    error InvalidSKU();

    /**
     * @dev Custom error thrown during SKU creation or factory setup if essential parameters are invalid or missing.
     * @dev Implementations should revert with this error if setup configurations or required parameters for SKU creation are not correctly provided.
     */
    error InvalidSetup();

    /**
     * @dev Custom error thrown when an action is attempted by an unauthorized account, lacking executive privileges.
     * @dev Implementations should revert with this error to restrict access to administrative functions to only accounts with the EXECUTIVE_ROLE.
     */
    error Unauthorized();

    /**
     * @dev Custom error thrown when the lengths of input arrays (e.g., sizes and prices) do not match, indicating inconsistent input data.
     * @dev Implementations should revert with this error if arrays that are expected to be of the same length (like sizes and prices during SKU creation) have mismatched lengths.
     */
    error ArrayLengthMismatch();

    /**
     * @dev Custom error thrown when a subscription tier value is out of the valid range or not supported.
     * @dev Implementations should revert with this error if a provided `SubscriptionTier` enum value is not within the defined valid tiers (e.g., Basic, Plus, Premium).
     */
    error OutOfRangeSubscriptionTier();

    /**
     * @dev Custom error thrown when an invalid price (e.g., zero price) is provided for a SKU size variant.
     * @dev Implementations should revert with this error if a price is set to an invalid value, such as zero, which is typically not allowed for paid SKU sizes.
     */
    error InvalidPrice();

    /**
     * @dev Custom error thrown when an invalid size identifier is provided, typically when trying to access or modify a non-existent size variant.
     * @dev Implementations should revert with this error if a size identifier does not correspond to a valid size variant within a SKU's token contract.
     */
    error InvalidSize();

    /**
     * @notice Returns the address of the CheBControlCenter contract used for access control.
     * @return ICheBControlCenter The contract address of the CheBControlCenter.
     *
     * @dev Implementations should provide a view function to retrieve the address of the linked CheBControlCenter contract, which manages roles and permissions for the factory and its deployed contracts.
     */
    function chebControl() external view returns (ICheBControlCenter);

    /**
     * @notice Returns the address of the CheBSubscription contract, potentially used for subscription-based access control in the future.
     * @return ICheBSubscription The contract address of the CheBSubscription contract.
     *
     * @dev Implementations should provide a view function to retrieve the address of the CheBSubscription contract. While its direct use in the factory might be limited, it's included for potential future integration.
     */
    function subscription() external view returns (ICheBSubscription);

    /**
     * @notice Returns the current value of the SKU IDs counter, representing the total number of SKUs created.
     * @return uint256 The current SKU IDs counter value.
     *
     * @dev Implementations should provide a view function to get the current SKU counter. This counter is incremented each time a new SKU is created, providing a unique identifier.
     */
    function skuIds() external view returns (uint256);

    /**
     * @notice Returns the address of the CheBProofOfPurchase token contract associated with a given SKU identifier.
     * @param skuId The identifier of the SKU to look up.
     * @return address The contract address of the CheBProofOfPurchase token for the given SKU, or address(0) if no SKU exists.
     *
     * @dev Implementations should provide a view function to retrieve the token contract address for a specific SKU ID. This mapping links SKU IDs to their deployed token contracts.
     *
     *  InvalidSKU Implementations should revert with this error if `skuToToken[skuId]` is address(0), indicating no SKU exists for the given `skuId`.
     */
    function skuToToken(uint256 skuId) external view returns (address);

    /**
     * @notice Returns the subscription tier access setting for a specific SKU and subscription tier.
     * @param skuId The identifier of the SKU to check access for.
     * @param tier The SubscriptionTier enum value to check access for.
     * @return bool True if the specified subscription tier is allowed access to the SKU, false otherwise.
     *
     * @dev Implementations should provide a view function to check if a particular subscription tier is allowed to access a specific SKU. This mapping controls tier-based access to SKUs.
     */
    function skuTierAccess(uint256 skuId, ICheBSubscription.SubscriptionTier tier) external view returns (bool);

    /**
     * @notice Creates a new SKU and deploys a CheBProofOfPurchase token contract for it.
     * @param uri Base URI for the ERC1155 metadata of the new SKU.
     * @param sizes Array of initial size variants for the SKU.
     * @param prices Array of initial prices corresponding to the `sizes` array.
     * @param allowedTiers Array of SubscriptionTier enum values that are allowed to access this SKU.
     * @return address The address of the newly deployed CheBProofOfPurchase token contract.
     *
     * @dev Implementations should provide a function to create a new SKU. This function should deploy a new CheBProofOfPurchase contract, assign a unique SKU ID, and configure initial sizes, prices, and subscription tier access.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     *  ArrayLengthMismatch Implementations should revert with this error if `sizes` and `prices` arrays have different lengths.
     *  InvalidSetup Implementations should revert with this error if `sizes` or `allowedTiers` arrays are empty.
     *  OutOfRangeSubscriptionTier Implementations should revert with this error if any tier in `allowedTiers` is out of valid range.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function createSKU(
        string memory uri,
        uint256[] memory sizes,
        uint256[] memory prices,
        ICheBSubscription.SubscriptionTier[] memory allowedTiers
    ) external returns (address);

    /**
     * @notice Adds a new size variant to an existing SKU's CheBProofOfPurchase token contract.
     * @param skuId The identifier of the SKU to add the size to.
     * @param size The identifier of the new size variant to add.
     * @param price Initial price for the new size variant.
     *
     * @dev Implementations should provide a function to add a new size variant to an existing SKU. This function should delegate the size addition to the corresponding CheBProofOfPurchase contract.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     *  InvalidSKU Implementations should revert with this error if the provided `skuId` does not correspond to an existing SKU.
     *  InvalidPrice Implementations should revert with this error if the provided `price` is zero.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function addSKUSize(uint256 skuId, uint256 size, uint256 price) external;

    /**
     * @notice Removes a size variant from an existing SKU's CheBProofOfPurchase token contract.
     * @param skuId The identifier of the SKU to remove the size from.
     * @param size The identifier of the size variant to remove.
     *
     * @dev Implementations should provide a function to remove a size variant from an existing SKU. This function should delegate the size removal to the corresponding CheBProofOfPurchase contract.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     *  InvalidSKU Implementations should revert with this error if the provided `skuId` does not correspond to an existing SKU.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function removeSKUSize(uint256 skuId, uint256 size) external;

    /**
     * @notice Updates the price for a size variant in an existing SKU's CheBProofOfPurchase token contract.
     * @param skuId The identifier of the SKU to update the price for.
     * @param size The identifier of the size variant to update the price for.
     * @param newPrice The new price for the size variant.
     *
     * @dev Implementations should provide a function to update the price of a size variant for an existing SKU. This function should delegate the price update to the corresponding CheBProofOfPurchase contract.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     *  InvalidSKU Implementations should revert with this error if the provided `skuId` does not correspond to an existing SKU.
     *  InvalidPrice Implementations should revert with this error if the provided `newPrice` is zero.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function updateSKUPrice(uint256 skuId, uint256 size, uint256 newPrice) external;

    /**
     * @notice Updates the subscription tier access control setting for a specific SKU.
     * @param skuId The identifier of the SKU to update tier access for.
     * @param tier The SubscriptionTier enum value to update access for.
     * @param allowed Boolean indicating whether to allow (true) or disallow (false) access for the specified tier.
     *
     * @dev Implementations should provide a function to update the subscription tier access for a specific SKU. This function should modify the `skuTierAccess` mapping accordingly.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     *  InvalidSKU Implementations should revert with this error if the provided `skuId` does not correspond to an existing SKU.
     *  OutOfRangeSubscriptionTier Implementations should revert with this error if the provided `tier` is out of valid range.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     */
    function updateSkuTierAccess(
        uint256 skuId,
        ICheBSubscription.SubscriptionTier tier,
        bool allowed
    ) external;

    /**
     * @notice Retrieves the address of the CheBProofOfPurchase token contract for a given SKU identifier.
     * @param skuId The identifier of the SKU to query.
     * @return address The address of the CheBProofOfPurchase token contract associated with the `skuId`.
     *
     * @dev Implementations should provide a view function to get the token contract address for a given SKU ID. This is a read-only function to query the mapping of SKUs to their token contracts.
     *
     *  InvalidSKU Implementations should revert with this error if `skuToToken[skuId]` is address(0), indicating no SKU exists for the given `skuId`.
     */
    function getTokenAddress(uint256 skuId) external view returns (address);

    /**
     * @notice Pauses the factory contract, halting critical operations such as SKU creation and management.
     *
     * @dev Implementations should provide a function for executives to pause the factory contract. When paused, operations like creating new SKUs or modifying existing ones may be restricted.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     */
    function pause() external;

    /**
     * @notice Resumes factory contract operations after being paused, allowing SKU creation and management to proceed.
     *
     * @dev Implementations should provide a function for executives to unpause the factory contract, restoring normal operations.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     */
    function unpause() external;

    /**
     * @notice Checks if the factory contract is currently paused.
     * @return bool True if the contract is paused, false otherwise.
     *
     * @dev Implementations should provide a view function to check the current pause state of the factory contract, allowing external contracts and users to determine if factory operations are currently active.
     */
    function paused() external view returns (bool);
}