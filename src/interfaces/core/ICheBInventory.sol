// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title ICheBInventory Interface
 * @author CheB Protocol
 * @notice Interface for the CheBInventory contract
 */
interface ICheBInventory {
    // Structs
    struct InventoryItem {
        uint256 quantity;
        uint256 verifiedQuantity;
        uint256 lastVerificationTime;
        bool isVerified;
    }

    // Custom Errors
    error ZeroAddress();
    error InvalidControlCenter();
    error InvalidListing();
    error InvalidSKU();
    error NotVerifier();
    error NotAdmin();
    error ControlCenterPaused();
    error SellerNotWhitelisted();
    error InvalidSize();
    error InvalidQuantity();
    error AlreadyVerified();
    error NotVerified();
    error InsufficientInventory();

    // Events
    event InventoryAdded(
        address indexed seller,
        uint256 indexed skuId,
        string size,
        uint256 quantity
    );
    
    event InventoryVerified(
        address indexed seller,
        uint256 indexed skuId,
        string size,
        uint256 verifiedQuantity,
        address verifier
    );
    
    event InventoryRemoved(
        address indexed seller,
        uint256 indexed skuId,
        string size,
        uint256 quantity
    );

    event InventoryReserved(
        address indexed seller,
        uint256 indexed skuId,
        string size,
        uint256 quantity
    );

    event InventoryReleased(
        address indexed seller,
        uint256 indexed skuId,
        string size,
        uint256 quantity
    );

    /**
     * @notice Returns the control center contract address
     */
    function controlCenter() external view returns (address);

    /**
     * @notice Returns the listing contract address
     */
    function listing() external view returns (address);

    /**
     * @notice Returns the SKU contract address
     */
    function sku() external view returns (address);

    /**
     * @notice Adds inventory for a seller
     * @param skuId SKU identifier
     * @param size Size of the item
     * @param quantity Quantity to add
     */
    function addInventory(
        uint256 skuId,
        string calldata size,
        uint256 quantity
    ) external;

    /**
     * @notice Verifies inventory for a seller
     * @param seller Address of the seller
     * @param skuId SKU identifier
     * @param size Size of the item
     * @param verifiedQuantity Quantity verified
     */
    function verifyInventory(
        address seller,
        uint256 skuId,
        string calldata size,
        uint256 verifiedQuantity
    ) external;

    /**
     * @notice Removes inventory for a seller
     * @param skuId SKU identifier
     * @param size Size of the item
     */
    function removeInventory(
        uint256 skuId,
        string calldata size
    ) external;

    /**
     * @notice Reserves inventory for a seller
     * @param seller Address of the seller
     * @param skuId SKU identifier
     * @param size Size of the item
     * @param quantity Quantity to reserve
     */
    function reserveInventory(
        address seller,
        uint256 skuId,
        string calldata size,
        uint256 quantity
    ) external;

    /**
     * @notice Releases previously reserved inventory
     * @param seller Address of the seller
     * @param skuId SKU identifier
     * @param size Size of the item
     * @param quantity Quantity to release
     */
    function releaseInventory(
        address seller,
        uint256 skuId,
        string calldata size,
        uint256 quantity
    ) external;

    /**
     * @notice Gets inventory details for a seller
     * @param seller Address of the seller
     * @param skuId SKU identifier
     * @param size Size of the item
     * @return quantity Total quantity
     * @return verifiedQuantity Verified quantity
     * @return lastVerificationTime Last verification timestamp
     * @return isVerified Verification status
     */
    function getInventory(
        address seller,
        uint256 skuId,
        string calldata size
    ) external view returns (
        uint256 quantity,
        uint256 verifiedQuantity,
        uint256 lastVerificationTime,
        bool isVerified
    );

    /**
     * @notice Checks if a seller has sufficient verified inventory
     * @param seller Address of the seller
     * @param skuId SKU identifier
     * @param size Size of the item
     * @param quantity Quantity to check
     * @return bool True if sufficient verified inventory exists
     */
    function hasVerifiedInventory(
        address seller,
        uint256 skuId,
        string calldata size,
        uint256 quantity
    ) external view returns (bool);

    /**
     * @notice Pauses the contract
     */
    function pause() external;

    /**
     * @notice Unpauses the contract
     */
    function unpause() external;
}