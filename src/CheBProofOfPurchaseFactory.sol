// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./CheBProofOfPurchase.sol";
import "./interfaces/ICheBControlCenter.sol";
import "./interfaces/ICheBSubscription.sol";

/**
 * @title CheBProofOfPurchaseFactory
 * @author CheB Protocol
 * @notice Factory contract for deploying and managing CheBProofOfPurchase contracts, which are ERC1155 tokens representing proof of purchase for SKUs.
 * @dev This factory simplifies the creation of new CheBProofOfPurchase contracts for different SKUs.
 * It manages SKU identifiers, maps SKUs to their token contracts, and controls subscription tier access to each SKU.
 * Executives can use this factory to create, manage, and configure Proof of Purchase tokens within the CheB ecosystem.
 */
contract CheBProofOfPurchaseFactory is ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;

    /* @notice Core contract references and public state variables */

    /**
     * @notice Reference to the CheBControlCenter contract for centralized access control and role management.
     * @dev Used to verify executive roles for administrative functions within this factory.
     */
    ICheBControlCenter public immutable chebControl;

    /**
     * @notice Reference to the CheBSubscription contract for managing subscription tiers and access control based on user subscriptions.
     * @dev Although currently not directly used in factory logic, it is included for potential future subscription-based SKU access control within the factory itself (if needed).
     */
    ICheBSubscription public immutable subscription;

    /**
     * @notice Counter for generating unique SKU identifiers.
     * @dev Incremented each time a new SKU is created, ensuring unique IDs for all SKUs.
     */
    Counters.Counter public skuIds;

    /**
     * @notice Mapping from SKU identifier to the address of its deployed CheBProofOfPurchase contract.
     * @dev Allows retrieval of the token contract address for a given SKU ID, enabling interaction with specific SKU tokens.
     */
    mapping(uint256 => address) public skuToToken;

    /**
     * @notice Mapping to control subscription tier access for each SKU.
     * @dev Defines which subscription tiers are allowed to access and potentially purchase Proof of Purchase tokens for a specific SKU.
     * The nested mapping structure is `skuId => (SubscriptionTier => bool)`.
     */
    mapping(uint256 => mapping(ICheBSubscription.SubscriptionTier => bool)) public skuTierAccess;

    /* @notice Custom errors */

    /**
     * @dev Custom error thrown when an invalid SKU identifier is provided, and no corresponding token contract exists.
     * Indicates that the requested SKU is not registered or deployed through this factory.
     */
    error InvalidSKU();

    /**
     * @dev Custom error thrown during contract initialization if critical setup parameters (like control center or subscription addresses) are invalid (zero address).
     * Ensures that the factory is initialized with valid contract addresses for its dependencies.
     */
    error InvalidSetup();

    /**
     * @dev Custom error thrown when an action is attempted by an unauthorized account, lacking executive privileges.
     * Restricts administrative functions to authorized executives as defined in CheBControlCenter.
     */
    error Unauthorized();

    /**
     * @dev Custom error thrown when the length of provided arrays (e.g., sizes and prices) do not match during SKU creation.
     * Ensures that input arrays for SKU setup are consistent and correctly paired.
     */
    error ArrayLengthMismatch();

    /**
     * @dev Custom error thrown when a subscription tier value is out of the valid range (e.g., not within defined SubscriptionTier enum).
     * Validates subscription tier inputs to ensure they are within the defined enum values.
     */
    error OutOfRangeSubscriptionTier(); // Renamed from InvalidTier for clarity

    /**
     * @dev Custom error thrown when an invalid price (e.g., zero price) is provided for a size variant.
     * Ensures that prices set for SKU sizes are valid and greater than zero.
     */
    error InvalidPrice();

    /**
     * @dev Custom error thrown when an invalid size identifier is provided, typically when trying to operate on a non-existent size.
     * Validates size identifiers to ensure they correspond to existing size variants within an SKU.
     */
    error InvalidSize();

    /* @notice Events */

    /**
     * @dev Emitted when a new SKU and its corresponding CheBProofOfPurchase contract are successfully created.
     * @param skuId The unique identifier assigned to the newly created SKU.
     * @param tokenAddress The address of the deployed CheBProofOfPurchase contract for the SKU.
     * @param uri The base URI for the ERC1155 metadata associated with the SKU.
     * @param sizes Array of initial size variants added to the SKU token contract.
     * @param prices Array of initial prices corresponding to the sizes.
     *
     * Emitted upon successful creation of a new SKU and its PoP token contract.
     */
    event SKUCreated(uint256 indexed skuId, address indexed tokenAddress, string uri, uint256[] sizes, uint256[] prices); // Renamed tokenContract to tokenAddress

    /**
     * @dev Emitted when the subscription tier access setting is updated for a specific SKU.
     * @param skuId The identifier of the SKU for which tier access is updated.
     * @param tier The SubscriptionTier enum value for which access is being updated.
     * @param allowed Boolean indicating whether the tier is allowed (true) or disallowed (false) to access the SKU.
     *
     * Emitted when the access control for a subscription tier to a specific SKU is modified.
     */
    event TierAccessUpdated(uint256 indexed skuId, ICheBSubscription.SubscriptionTier tier, bool allowed);

    /**
     * @dev Emitted when a new size variant is added to an existing SKU token contract through the factory.
     * @param skuId The identifier of the SKU to which the size is added.
     * @param size The identifier of the newly added size variant.
     * @param price The initial price set for the new size variant.
     *
     * Emitted when a new product size option is added to an existing SKU.
     */
    event SizeAdded(uint256 indexed skuId, uint256 size, uint256 price);

    /**
     * @dev Emitted when a size variant is removed from an existing SKU token contract through the factory.
     * @param skuId The identifier of the SKU from which the size is removed.
     * @param size The identifier of the removed size variant.
     *
     * Emitted when a product size option is removed from an existing SKU.
     */
    event SizeRemoved(uint256 indexed skuId, uint256 size);

    /**
     * @dev Emitted when the price of a size variant is updated for an existing SKU token contract through the factory.
     * @param skuId The identifier of the SKU for which the price is updated.
     * @param size The identifier of the size variant whose price is updated.
     * @param newPrice The new price set for the size variant.
     *
     * Emitted when the price of a specific product size is changed for an existing SKU.
     */
    event PriceUpdated(uint256 indexed skuId, uint256 size, uint256 newPrice);

    /**
     * @notice Constructor for the CheBProofOfPurchaseFactory contract.
     * @param _chebControl Address of the deployed CheBControlCenter contract.
     * @param _subscription Address of the deployed CheBSubscription contract.
     *
     * @dev Initializes the factory with references to the CheBControlCenter and CheBSubscription contracts.
     * Reverts if either of the provided addresses is the zero address, ensuring valid contract dependencies.
     */
    constructor(address _chebControl, address _subscription) {
        if (_chebControl == address(0) || _subscription == address(0)) revert InvalidSetup();
        chebControl = ICheBControlCenter(_chebControl);
        subscription = ICheBSubscription(_subscription);
    }

    /**
     * @notice Modifier to restrict function calls to only accounts with the EXECUTIVE_ROLE.
     * @dev Checks if the caller has the EXECUTIVE_ROLE in the CheBControlCenter contract.
     *
     * @custom:security Ensures that only authorized executives can perform administrative functions in this factory.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    modifier onlyExecutive() {
        if (!chebControl.hasRole(chebControl.EXECUTIVE_ROLE(), msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @notice Creates a new SKU and deploys a CheBProofOfPurchase token contract for it.
     * @dev Callable only by accounts with EXECUTIVE_ROLE.
     * Deploys a new ERC1155 contract, registers the SKU ID and token address, and sets initial size variants and prices.
     * Configures subscription tier access for the new SKU based on `allowedTiers` parameter.
     *
     * @param uri Base URI for the ERC1155 metadata for the new SKU.
     * @param sizes Array of initial size variant identifiers for the SKU.
     * @param prices Array of initial prices corresponding to the `sizes` array. Must be same length as `sizes`.
     * @param allowedTiers Array of SubscriptionTier enum values that are allowed to access this SKU.
     * @return address The address of the newly deployed CheBProofOfPurchase token contract.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {SKUCreated} event upon successful SKU creation.
     *
     *  ArrayLengthMismatch Thrown if `sizes` and `prices` arrays have different lengths.
     *  InvalidSetup Thrown if `sizes` or `allowedTiers` arrays are empty.
     *  OutOfRangeSubscriptionTier Thrown if any tier in `allowedTiers` is out of valid range.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function createSKU(
        string memory uri,
        uint256[] memory sizes,
        uint256[] memory prices,
        ICheBSubscription.SubscriptionTier[] memory allowedTiers
    ) external onlyExecutive nonReentrant whenNotPaused returns (address) {
        if (sizes.length != prices.length) revert ArrayLengthMismatch();
        if (sizes.length == 0 || allowedTiers.length == 0) revert InvalidSetup();

        skuIds.increment();
        uint256 newSkuId = skuIds.current();

        CheBProofOfPurchase token = new CheBProofOfPurchase(
            address(chebControl),
            newSkuId,
            uri,
            sizes,
            prices
        );

        for (uint256 i = 0; i < allowedTiers.length; i++) {
            if (uint256(allowedTiers[i]) > uint256(ICheBSubscription.SubscriptionTier.Premium)) {
                revert OutOfRangeSubscriptionTier(); // Using renamed error
            }
            skuTierAccess[newSkuId][allowedTiers[i]] = true;
        }

        skuToToken[newSkuId] = address(token);
        emit SKUCreated(newSkuId, address(token), uri, sizes, prices);
        return address(token);
    }

    /**
     * @notice Adds a new size variant to an existing SKU's CheBProofOfPurchase token contract.
     * @dev Callable only by accounts with EXECUTIVE_ROLE.
     * Delegates the size addition to the specific CheBProofOfPurchase contract associated with the SKU.
     *
     * @param skuId The identifier of the SKU to which the size is being added.
     * @param size The identifier of the new size variant to add.
     * @param price Initial price for the new size variant. Must be greater than zero.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {SizeAdded} event upon successful size addition.
     *
     *  InvalidSKU Thrown if the provided `skuId` does not correspond to an existing SKU.
     *  InvalidPrice Thrown if the provided `price` is zero.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function addSKUSize(uint256 skuId, uint256 size, uint256 price)
        external
        onlyExecutive
        nonReentrant
        whenNotPaused
    {
        if (skuToToken[skuId] == address(0)) revert InvalidSKU();
        if (price == 0) revert InvalidPrice();

        CheBProofOfPurchase token = CheBProofOfPurchase(skuToToken[skuId]);
        token.addSize(size, price);
        emit SizeAdded(skuId, size, price);
    }

    /**
     * @notice Removes a size variant from an existing SKU's CheBProofOfPurchase token contract.
     * @dev Callable only by accounts with EXECUTIVE_ROLE.
     * Delegates the size removal to the specific CheBProofOfPurchase contract associated with the SKU.
     *
     * @param skuId The identifier of the SKU from which the size is being removed.
     * @param size The identifier of the size variant to remove.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {SizeRemoved} event upon successful size removal.
     *
     *  InvalidSKU Thrown if the provided `skuId` does not correspond to an existing SKU.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function removeSKUSize(uint256 skuId, uint256 size)
        external
        onlyExecutive
        nonReentrant
        whenNotPaused
    {
        if (skuToToken[skuId] == address(0)) revert InvalidSKU();

        CheBProofOfPurchase token = CheBProofOfPurchase(skuToToken[skuId]);
        token.removeSize(size);
        emit SizeRemoved(skuId, size);
    }

    /**
     * @notice Updates the price for a size variant in an existing SKU's CheBProofOfPurchase token contract.
     * @dev Callable only by accounts with EXECUTIVE_ROLE.
     * Delegates the price update to the specific CheBProofOfPurchase contract associated with the SKU.
     *
     * @param skuId The identifier of the SKU for which the price is being updated.
     * @param size The identifier of the size variant to update the price for.
     * @param newPrice The new price for the size variant. Must be greater than zero.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {PriceUpdated} event upon successful price update.
     *
     *  InvalidSKU Thrown if the provided `skuId` does not correspond to an existing SKU.
     *  InvalidPrice Thrown if the provided `newPrice` is zero.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function updateSKUPrice(uint256 skuId, uint256 size, uint256 newPrice)
        external
        onlyExecutive
        nonReentrant
        whenNotPaused
    {
        if (skuToToken[skuId] == address(0)) revert InvalidSKU();
        if (newPrice == 0) revert InvalidPrice(); // Added price validation here

        CheBProofOfPurchase token = CheBProofOfPurchase(skuToToken[skuId]);
        token.updatePrice(size, newPrice);
        emit PriceUpdated(skuId, size, newPrice);
    }

    /**
     * @notice Updates the subscription tier access control setting for a specific SKU.
     * @dev Callable only by accounts with EXECUTIVE_ROLE.
     * Modifies the `skuTierAccess` mapping to allow or disallow a specific subscription tier from accessing the SKU.
     *
     * @param skuId The identifier of the SKU for which tier access is being updated.
     * @param tier The SubscriptionTier enum value to update access for.
     * @param allowed Boolean indicating whether to allow (true) or disallow (false) access for the specified tier.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {TierAccessUpdated} event upon successful tier access update.
     *
     *  InvalidSKU Thrown if the provided `skuId` does not correspond to an existing SKU.
     *  OutOfRangeSubscriptionTier Thrown if the provided `tier` is out of the valid SubscriptionTier range.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function updateSkuTierAccess(
        uint256 skuId,
        ICheBSubscription.SubscriptionTier tier,
        bool allowed
    ) external onlyExecutive whenNotPaused {
        if (skuToToken[skuId] == address(0)) revert InvalidSKU();
        if (uint256(tier) > uint256(ICheBSubscription.SubscriptionTier.Premium)) revert OutOfRangeSubscriptionTier(); // Using renamed error

        skuTierAccess[skuId][tier] = allowed;
        emit TierAccessUpdated(skuId, tier, allowed);
    }

    /**
     * @notice Retrieves the address of the CheBProofOfPurchase token contract for a given SKU identifier.
     * @dev Callable by anyone to get the token contract address for an SKU.
     *
     * @param skuId The identifier of the SKU to query.
     * @return address The address of the CheBProofOfPurchase token contract associated with the `skuId`.
     *
     * @custom:access Callable by anyone.
     *
     *  InvalidSKU Thrown if the provided `skuId` does not correspond to an existing SKU.
     */
    function getTokenAddress(uint256 skuId) external view returns (address) {
        if (skuToToken[skuId] == address(0)) revert InvalidSKU();
        return skuToToken[skuId];
    }

    /**
     * @notice Pauses the contract, halting critical operations within the factory.
     * @dev Callable only by accounts with EXECUTIVE_ROLE.
     * Enables emergency pause mechanism to stop SKU creation and management operations.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     */
    function pause() external onlyExecutive {
        _pause();
    }

    /**
     * @notice Resumes contract operations after being paused.
     * @dev Callable only by accounts with EXECUTIVE_ROLE.
     * Reverts the contract to normal operation, allowing SKU creation and management functionalities.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     */
    function unpause() external onlyExecutive {
        _unpause();
    }
}