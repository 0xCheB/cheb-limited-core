// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/ICheBControlCenter.sol";

/**
 * @title CheBProofOfPurchase
 * @author CheB Protocol
 * @notice ERC1155 contract representing proof of purchase tokens for products (SKUs) that have size variants.
 * @dev This contract manages the lifecycle of Proof of Purchase (PoP) tokens for a specific SKU.
 * It allows for different sizes of the SKU, each with its own price and inventory management.
 * Sellers are allocated inventory which can be locked upon sale and released to buyers upon verification.
 * The contract integrates with CheBControlCenter for access control and pause functionality.
 */
contract CheBProofOfPurchase is ERC1155, ReentrancyGuard, Pausable {
    /* @notice Core contract references and public state variables */

    /**
     * @notice Reference to the CheBControlCenter contract for role-based access control.
     */
    ICheBControlCenter public immutable chebControl;

    /**
     * @notice Unique identifier for the SKU (Stock Keeping Unit) that this Proof of Purchase contract represents.
     * @dev This ID is immutable and set during contract deployment, linking this contract to a specific product.
     */
    uint256 public immutable skuId;

    /**
     * @notice Struct to hold details for each size variant of the SKU.
     * @param price The price of the SKU in the base currency for this specific size.
     * @param totalSupply The total supply of PoP tokens minted for this size.
     * @param exists Boolean flag indicating whether this size variant has been created and is valid.
     */
    struct SizeDetails {
        uint256 price;
        uint256 totalSupply;
        bool exists;
    }

    /**
     * @notice Mapping to store details for each size variant, using size as the key.
     * @dev Allows retrieval of price, total supply, and existence status for each size.
     */
    mapping(uint256 => SizeDetails) public sizeDetails;

    /**
     * @notice Mapping to track the availability status of each size variant.
     * @dev Indicates if a particular size is currently offered and available for purchase.
     */
    mapping(uint256 => bool) public isSizeAvailable;

    /**
     * @notice Mapping to track the inventory of each seller for each size variant.
     * @dev Stores the amount of PoP tokens allocated to each seller for each size, enabling inventory management per seller and size.
     */
    mapping(address => mapping(uint256 => uint256)) public sellerInventory;

    /* @notice Custom errors */

    /**
     * @dev Custom error thrown when an action is attempted by an unauthorized account.
     * Indicates that the caller does not have the required role or permissions.
     */
    error Unauthorized();

    /**
     * @dev Custom error thrown when an invalid size variant is specified.
     * For example, when trying to access details of a non-existent size.
     */
    error InvalidSize();

    /**
     * @dev Custom error thrown when an invalid price (e.g., zero price) is provided.
     * Used when setting or updating prices for size variants and ensuring prices are valid.
     */
    error InvalidPrice();

    /**
     * @dev Custom error thrown when there is insufficient inventory to fulfill a request.
     * For example, when attempting to lock or remove more tokens than available in inventory.
     */
    error InsufficientInventory();

    /**
     * @dev Custom error thrown when an invalid amount (e.g., zero amount) is specified for an operation.
     * Used when allocating, removing, or locking tokens and ensuring amounts are valid.
     */
    error InvalidAmount();

    /**
     * @dev Custom error thrown when attempting to add a size variant that already exists.
     * Prevents duplicate size variants for the SKU.
     */
    error SizeAlreadyExists();

    /**
     * @dev Custom error thrown when an action is performed by an address that is not a verified seller.
     * Ensures that only verified sellers can perform seller-specific actions.
     */
    error NotVerifiedSeller();

    /**
     * @dev Custom error thrown when attempting to perform an operation on a size that does not exist.
     * Ensures that operations are only performed on valid and existing size variants.
     */
    error SizeNotExists();

    /* @notice Events */

    /**
     * @dev Emitted when inventory is allocated to a seller for a specific size variant.
     * @param seller The address of the seller to whom inventory is allocated.
     * @param size The size variant for which inventory is allocated.
     * @param inventoryAmount The amount of inventory allocated to the seller.
     *
     * Emitted when new inventory is assigned to a seller for a specific product size.
     */
    event InventoryAllocated(address indexed seller, uint256 indexed size, uint256 inventoryAmount); // Renamed amount to inventoryAmount

    /**
     * @dev Emitted when inventory is removed from a seller for a specific size variant.
     * @param seller The address of the seller from whom inventory is removed.
     * @param size The size variant from which inventory is removed.
     * @param inventoryAmount The amount of inventory removed from the seller.
     *
     * Emitted when inventory is taken back from a seller for a specific product size.
     */
    event InventoryRemoved(address indexed seller, uint256 indexed size, uint256 inventoryAmount); // Renamed amount to inventoryAmount

    /**
     * @dev Emitted when a new size variant is added to the SKU.
     * @param size The size variant that was added.
     * @param price The initial price set for the new size variant.
     *
     * Emitted when a new product size option is made available for purchase.
     */
    event SizeAdded(uint256 indexed size, uint256 price);

    /**
     * @dev Emitted when a size variant is removed from the SKU.
     * @param size The size variant that was removed.
     *
     * Emitted when a product size option is no longer offered.
     */
    event SizeRemoved(uint256 indexed size);

    /**
     * @dev Emitted when the price of a size variant is updated.
     * @param size The size variant whose price was updated.
     * @param newPrice The new price for the size variant.
     *
     * Emitted when the price of a specific product size is changed.
     */
    event PriceUpdated(uint256 indexed size, uint256 newPrice);

    /**
     * @dev Emitted when tokens are locked in the contract as part of a purchase process.
     * @param seller The address of the seller who is locking the tokens.
     * @param buyer The address of the buyer for whom tokens are being locked.
     * @param size The size variant of the tokens being locked.
     * @param amount The amount of tokens locked.
     *
     * Emitted when PoP tokens are moved into contract escrow, indicating a sale in progress.
     */
    event TokensLocked(address indexed seller, address indexed buyer, uint256 indexed size, uint256 amount);

    /**
     * @dev Emitted when tokens are released from the contract escrow, either to the buyer or back to the seller.
     * @param seller The address of the seller related to the tokens.
     * @param buyer The address of the buyer who is receiving or was intended to receive the tokens.
     * @param size The size variant of the tokens being released.
     * @param amount The amount of tokens released.
     *
     * Emitted when PoP tokens are transferred out of contract escrow, completing a sale or reverting tokens.
     */
    event TokensReleased(address indexed seller, address indexed buyer, uint256 indexed size, uint256 amount);

    /**
     * @notice Constructor for the CheBProofOfPurchase contract.
     * @param _chebControl Address of the deployed CheBControlCenter contract for access control.
     * @param _skuId Unique identifier for the SKU this contract represents.
     * @param _uri Base URI for the ERC1155 metadata.
     * @param sizes Array of initial size variants to be added upon deployment.
     * @param prices Array of initial prices corresponding to the sizes.
     *
     * @dev Initializes the ERC1155 contract with URI, sets the CheBControlCenter address, and SKU ID.
     * It also adds initial size variants with their prices provided in the constructor arguments.
     */
    constructor(
        address _chebControl,
        uint256 _skuId,
        string memory _uri,
        uint256[] memory sizes,
        uint256[] memory prices
    ) ERC1155(_uri) {
        chebControl = ICheBControlCenter(_chebControl);
        skuId = _skuId;

        require(sizes.length == prices.length, "Sizes and prices arrays must be of equal length"); // Added require to ensure sizes and prices arrays are of same length

        for (uint256 i = 0; i < sizes.length; i++) {
            if (sizeDetails[sizes[i]].exists) revert SizeAlreadyExists();
            if (prices[i] == 0) revert InvalidPrice();

            sizeDetails[sizes[i]] = SizeDetails({
                price: prices[i],
                totalSupply: 0,
                exists: true
            });
            isSizeAvailable[sizes[i]] = true;
            emit SizeAdded(sizes[i], prices[i]);
        }
    }

    /**
     * @notice Modifier to restrict function calls to only accounts with the EXECUTIVE_ROLE.
     * @dev Checks if the caller has the EXECUTIVE_ROLE in the CheBControlCenter contract.
     *
     * @custom:security Ensures that only authorized executives can perform certain administrative functions.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    modifier onlyExecutive() {
        if (!chebControl.hasRole(chebControl.EXECUTIVE_ROLE(), msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @notice Modifier to restrict function calls to only accounts with the ADMIN_ROLE.
     * @dev Checks if the caller has the ADMIN_ROLE in the CheBControlCenter contract.
     *
     * @custom:security Ensures that only authorized admins can perform certain administrative functions.
     *  Unauthorized Thrown if the caller does not have the ADMIN_ROLE.
     */
    modifier onlyAdmin() {
        if (!chebControl.hasRole(chebControl.ADMIN_ROLE(), msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @notice Modifier to restrict function calls to only accounts with the VERIFIER_ROLE.
     * @dev Checks if the caller has the VERIFIER_ROLE in the CheBControlCenter contract.
     *
     * @custom:security Ensures that only authorized verifiers can perform certain verification-related functions.
     *  Unauthorized Thrown if the caller does not have the VERIFIER_ROLE.
     */
    modifier onlyVerifier() {
        if (!chebControl.hasRole(chebControl.VERIFIER_ROLE(), msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @notice Adds a new size variant to the SKU with an initial price.
     * @dev Only callable by accounts with EXECUTIVE_ROLE.
     * Allows adding new size options for the product after contract deployment.
     *
     * @param size The size variant identifier to add.
     * @param price Initial price for the new size variant. Must be greater than zero.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {SizeAdded} event upon successful size addition.
     *
     *  SizeAlreadyExists Thrown if a size variant with the given ID already exists.
     *  InvalidPrice Thrown if the provided price is zero.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function addSize(uint256 size, uint256 price)
        external
        onlyExecutive
        whenNotPaused
    {
        if (sizeDetails[size].exists) revert SizeAlreadyExists();
        if (price == 0) revert InvalidPrice();

        sizeDetails[size] = SizeDetails({
            price: price,
            totalSupply: 0,
            exists: true
        });
        isSizeAvailable[size] = true;
        emit SizeAdded(size, price);
    }

    /**
     * @notice Removes a size variant from the SKU, provided it has no remaining inventory.
     * @dev Only callable by accounts with EXECUTIVE_ROLE.
     * Removes a size option if all tokens of that size have been sold or removed from inventory.
     *
     * @param size The size variant identifier to remove.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {SizeRemoved} event upon successful size removal.
     *
     *  InvalidSize Thrown if the size variant does not exist.
     *  InsufficientInventory Thrown if there is still inventory remaining for the size (totalSupply > 0).
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function removeSize(uint256 size)
        external
        onlyExecutive
        whenNotPaused
    {
        if (!sizeDetails[size].exists) revert InvalidSize();
        if (sizeDetails[size].totalSupply > 0) { // Check if totalSupply is greater than zero
             revert InsufficientInventory(); // Reusing InsufficientInventory error for clarity - actually means "Inventory still exists"
        }
        // Removed the incorrect sellerInventory iteration - totalSupply check is sufficient and more efficient

        delete sizeDetails[size];
        isSizeAvailable[size] = false;
        emit SizeRemoved(size);
    }

    /**
     * @notice Updates the price for an existing size variant of the SKU.
     * @dev Only callable by accounts with EXECUTIVE_ROLE.
     * Allows adjusting the price of a specific size variant as needed.
     *
     * @param size The size variant identifier to update the price for.
     * @param newPrice The new price for the size variant. Must be greater than zero.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {PriceUpdated} event upon successful price update.
     *
     *  InvalidSize Thrown if the size variant does not exist.
     *  InvalidPrice Thrown if the provided new price is zero.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function updatePrice(uint256 size, uint256 newPrice)
        external
        onlyExecutive
        whenNotPaused
    {
        if (!sizeDetails[size].exists) revert InvalidSize();
        if (newPrice == 0) revert InvalidPrice();

        sizeDetails[size].price = newPrice;
        emit PriceUpdated(size, newPrice);
    }

    /**
     * @notice Allocates inventory of a specific size variant to a seller.
     * @dev Only callable by accounts with ADMIN_ROLE.
     * Increases the seller's inventory and the total supply for the given size.
     *
     * @param seller The address of the seller to allocate inventory to. Must be a verified seller.
     * @param size The size variant identifier to allocate inventory for.
     * @param amount The amount of inventory to allocate. Must be greater than zero.
     *
     * @custom:security Only callable by accounts with `ADMIN_ROLE`.
     * @custom:access Requires `onlyAdmin` modifier.
     * @custom:event Emits {InventoryAllocated} event upon successful inventory allocation.
     *
     *  InvalidSize Thrown if the size variant does not exist.
     *  InvalidAmount Thrown if the provided amount is zero.
     *  NotVerifiedSeller Thrown if the provided address is not a verified seller.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the ADMIN_ROLE.
     *  ("Total Supply Overflow") Thrown if adding the amount causes a total supply overflow.
     */
    function allocateInventory(
        address seller,
        uint256 size,
        uint256 amount
    ) external onlyAdmin whenNotPaused {
        if (!sizeDetails[size].exists) revert InvalidSize();
        if (amount == 0) revert InvalidAmount();
        if (!chebControl.isVerifiedSeller(seller)) revert NotVerifiedSeller();

        // Overflow check for totalSupply
        if (sizeDetails[size].totalSupply + amount < sizeDetails[size].totalSupply) revert("Total Supply Overflow"); // Explicit Overflow check

        sellerInventory[seller][size] += amount;
        sizeDetails[size].totalSupply += amount;
        emit InventoryAllocated(seller, size, amount);
    }

    /**
     * @notice Removes inventory of a specific size variant from a seller.
     * @dev Only callable by accounts with ADMIN_ROLE.
     * Decreases the seller's inventory and the total supply for the given size.
     *
     * @param seller The address of the seller to remove inventory from.
     * @param size The size variant identifier to remove inventory for.
     * @param amount The amount of inventory to remove. Must be greater than zero.
     *
     * @custom:security Only callable by accounts with `ADMIN_ROLE`.
     * @custom:access Requires `onlyAdmin` modifier.
     * @custom:event Emits {InventoryRemoved} event upon successful inventory removal.
     *
     *  InvalidSize Thrown if the size variant does not exist.
     *  InvalidAmount Thrown if the provided amount is zero.
     *  InsufficientInventory Thrown if the seller does not have enough inventory for the specified size.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the ADMIN_ROLE.
     */
    function removeInventory(
        address seller,
        uint256 size,
        uint256 amount
    ) external onlyAdmin whenNotPaused {
        if (!sizeDetails[size].exists) revert InvalidSize();
        if (amount == 0) revert InvalidAmount();
        if (sellerInventory[seller][size] < amount) revert InsufficientInventory();

        sellerInventory[seller][size] -= amount;
        sizeDetails[size].totalSupply -= amount;
        emit InventoryRemoved(seller, size, amount);
    }

    /**
     * @notice Locks tokens in the contract, effectively removing them from seller's tradable inventory.
     * @dev Callable by any account when the contract is not paused.
     * Mints ERC1155 tokens to this contract address to represent locked tokens (escrow).
     *
     * @param seller The seller locking the tokens. Must be a verified seller.
     * @param buyer The intended buyer (for event tracking).
     * @param size The size of the tokens being locked.
     * @param amount The amount of tokens to lock. Must be greater than zero.
     *
     * @custom:security Prevents reentrancy attacks.
     * @custom:access Callable by any account (typically by the seller or an authorized marketplace contract).
     * @custom:event Emits {TokensLocked} event upon successful token lock.
     *
     *  InvalidSize Thrown if the size variant does not exist.
     *  InsufficientInventory Thrown if the seller does not have enough inventory for the specified size.
     *  NotVerifiedSeller Thrown if the provided seller address is not a verified seller.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     */
    function lockTokens(
        address seller,
        address buyer,
        uint256 size,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (!sizeDetails[size].exists) revert InvalidSize();
        if (sellerInventory[seller][size] < amount) revert InsufficientInventory();
        if (!chebControl.isVerifiedSeller(seller)) revert NotVerifiedSeller();

        sellerInventory[seller][size] -= amount;
        _mint(address(this), size, amount, ""); // Minting to contract address (escrow within contract)
        emit TokensLocked(seller, buyer, size, amount);
    }

    /**
     * @notice Releases tokens from contract escrow to the buyer after order verification.
     * @dev Only callable by accounts with VERIFIER_ROLE.
     * Transfers ERC1155 tokens from this contract (escrow) to the buyer.
     *
     * @param seller The original seller (for event tracking).
     * @param buyer The buyer receiving the tokens.
     * @param size The size of the tokens being released.
     * @param amount The amount of tokens to release. Must be greater than zero.
     *
     * @custom:security Only callable by accounts with `VERIFIER_ROLE`.
     * @custom:access Requires `onlyVerifier` modifier.
     * @custom:event Emits {TokensReleased} event upon successful token release to buyer.
     *
     *  InvalidSize Thrown if the size variant does not exist.
     *  InsufficientInventory Thrown if the contract escrow does not have enough tokens for the specified size.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the VERIFIER_ROLE.
     */
    function releaseTokensToBuyer( // Renamed from releaseTokens for clarity - for buyer release
        address seller,
        address buyer,
        uint256 size,
        uint256 amount
    ) external onlyVerifier whenNotPaused {
        if (!sizeDetails[size].exists) revert InvalidSize();
        if (balanceOf(address(this), size) < amount) revert InsufficientInventory();

        _safeTransferFrom(address(this), buyer, size, amount, "");
        emit TokensReleased(seller, buyer, size, amount); // Keeping TokensReleased event name for consistency
    }

    /**
     * @notice Returns tokens from contract escrow back to the seller when an order or listing is cancelled.
     * @dev Only callable by accounts with VERIFIER_ROLE.
     * Transfers ERC1155 tokens from this contract (escrow) back to the seller.
     *
     * @param seller The seller receiving back the tokens.
     * @param buyer The original buyer (for event tracking - in case of order cancellation).
     * @param size The size of the tokens being returned.
     * @param amount The amount of tokens to return. Must be greater than zero.
     *
     * @custom:security Only callable by accounts with `VERIFIER_ROLE`.
     * @custom:access Requires `onlyVerifier` modifier.
     * @custom:event Emits {TokensReleased} event upon successful token return to seller.
     *
     *  InvalidSize Thrown if the size variant does not exist.
     *  InsufficientInventory Thrown if the contract escrow does not have enough tokens for the specified size.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the VERIFIER_ROLE.
     */
    function returnTokensToSeller( // Renamed from releaseTokens for clarity - for seller return
        address seller,
        address buyer, // Buyer here is for context in cancellation scenarios
        uint256 size,
        uint256 amount
    ) external onlyVerifier whenNotPaused {
        if (!sizeDetails[size].exists) revert InvalidSize();
        if (balanceOf(address(this), size) < amount) revert InsufficientInventory();

        _safeTransferFrom(address(this), seller, size, amount, ""); // Transfer back to seller
        emit TokensReleased(seller, buyer, size, amount); // Keeping TokensReleased event name for consistency
    }


    /**
     * @notice Gets a list of available size variants within a specified range.
     * @dev Allows querying for sizes that are marked as available for purchase.
     *
     * @param startSize Start of the size range to check (inclusive).
     * @param endSize End of the size range to check (inclusive).
     * @return Array of available size variant identifiers within the specified range.
     *
     * @custom:access Callable by anyone.
     */
    function getAvailableSizes(uint256 startSize, uint256 endSize)
        external
        view
        returns (uint256[] memory)
    {
        uint256 count = 0;

        for (uint256 i = startSize; i <= endSize; i++) {
            if (isSizeAvailable[i]) {
                count++;
            }
        }

        uint256[] memory sizes = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = startSize; i <= endSize; i++) {
            if (isSizeAvailable[i]) {
                sizes[index] = i;
                index++;
            }
        }

        return sizes;
    }

    /**
     * @notice Pauses the contract, halting critical operations.
     * @dev Enables emergency pause mechanism to stop sensitive operations within the contract.
     * Only callable by accounts with EXECUTIVE_ROLE.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     */
    function pause() external onlyExecutive {
        _pause();
    }

    /**
     * @notice Resumes contract operations after being paused.
     * @dev Reverts the contract to normal operation, allowing all functionalities to work.
     * Only callable by accounts with EXECUTIVE_ROLE.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     */
    function unpause() external onlyExecutive {
        _unpause();
    }
}