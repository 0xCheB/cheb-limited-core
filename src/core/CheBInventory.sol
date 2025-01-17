// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/accesscontrol/ICheBControlCenter.sol";
import "../interfaces/core/ICheBListing.sol";
import "../interfaces/core/ICheBSKU.sol";

/**
 * @title CheBInventory Contract
 * @author CheB Protocol
 * @notice Manages seller inventory for SKUs in the CheB Protocol
 * @dev Implements inventory management with role-based access control
 */
contract CheBInventory is ReentrancyGuard, Pausable {
    // State Variables
    ICheBControlCenter public immutable controlCenter;
    ICheBListing public immutable listing;
    ICheBSKU public immutable sku;

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

    struct InventoryItem {
        uint256 quantity;
        uint256 verifiedQuantity;
        uint256 lastVerificationTime;
        bool isVerified;
    }

    // Storage
    mapping(address => mapping(uint256 => mapping(string => InventoryItem))) private _inventory;
    
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

    // Modifiers
    modifier onlyVerifier() {
        if (controlCenter.paused()) revert ControlCenterPaused();
        if (!controlCenter.hasRole(controlCenter.VERIFIER_ROLE(), msg.sender)) revert NotVerifier();
        _;
    }

    modifier onlyAdmin() {
        if (controlCenter.paused()) revert ControlCenterPaused();
        if (!controlCenter.hasRole(controlCenter.ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyWhitelisted(address seller) {
        if (!listing.whitelist(seller)) revert SellerNotWhitelisted();
        _;
    }

    /**
     * @notice Contract constructor
     * @param _controlCenter Address of the CheBControlCenter contract
     * @param _listing Address of the CheBListing contract
     * @param _sku Address of the CheBSKU contract
     */
    constructor(
        address _controlCenter,
        address _listing,
        address _sku
    ) {
        if (_controlCenter == address(0) || _listing == address(0) || _sku == address(0)) revert ZeroAddress();

        // Validate CheBControlCenter
        ICheBControlCenter center = ICheBControlCenter(_controlCenter);
        try center.VERIFIER_ROLE() returns (bytes32) {} catch { revert InvalidControlCenter(); }

        // Validate CheBListing
        ICheBListing listingContract = ICheBListing(_listing);
        try listingContract.whitelist(address(0)) returns (bool) {} catch { revert InvalidListing(); }

        // Validate CheBSKU
        ICheBSKU skuContract = ICheBSKU(_sku);
        try skuContract.skuExists(0) returns (bool) {} catch { revert InvalidSKU(); }

        controlCenter = center;
        listing = listingContract;
        sku = skuContract;
    }

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
    ) external whenNotPaused nonReentrant onlyWhitelisted(msg.sender) {
        if (!sku.skuExists(skuId)) revert InvalidSKU();
        if (!sku.isValidSize(skuId, size)) revert InvalidSize();
        if (quantity == 0) revert InvalidQuantity();

        InventoryItem storage item = _inventory[msg.sender][skuId][size];
        item.quantity = quantity;
        item.isVerified = false;
        
        emit InventoryAdded(msg.sender, skuId, size, quantity);
    }

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
    ) external whenNotPaused nonReentrant onlyVerifier onlyWhitelisted(seller) {
        InventoryItem storage item = _inventory[seller][skuId][size];
        if (item.quantity == 0) revert InvalidQuantity();
        if (verifiedQuantity > item.quantity) revert InvalidQuantity();
        
        item.verifiedQuantity = verifiedQuantity;
        item.lastVerificationTime = block.timestamp;
        item.isVerified = true;
        
        emit InventoryVerified(seller, skuId, size, verifiedQuantity, msg.sender);
    }

    /**
     * @notice Removes inventory for a seller
     * @param skuId SKU identifier
     * @param size Size of the item
     */
    function removeInventory(
        uint256 skuId,
        string calldata size
    ) external whenNotPaused nonReentrant onlyWhitelisted(msg.sender) {
        InventoryItem storage item = _inventory[msg.sender][skuId][size];
        if (item.quantity == 0) revert InvalidQuantity();
        
        uint256 quantity = item.quantity;
        delete _inventory[msg.sender][skuId][size];
        
        emit InventoryRemoved(msg.sender, skuId, size, quantity);
    }

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
    ) external whenNotPaused nonReentrant onlyAdmin {
        InventoryItem storage item = _inventory[seller][skuId][size];
        if (!item.isVerified) revert NotVerified();
        if (item.verifiedQuantity < quantity) revert InsufficientInventory();
        
        item.verifiedQuantity -= quantity;
        emit InventoryReserved(seller, skuId, size, quantity);
    }

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
    ) external whenNotPaused nonReentrant onlyAdmin {
        InventoryItem storage item = _inventory[seller][skuId][size];
        if (!item.isVerified) revert NotVerified();
        
        item.verifiedQuantity += quantity;
        if (item.verifiedQuantity > item.quantity) {
            item.verifiedQuantity = item.quantity;
        }
        
        emit InventoryReleased(seller, skuId, size, quantity);
    }

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
    ) {
        InventoryItem storage item = _inventory[seller][skuId][size];
        return (
            item.quantity,
            item.verifiedQuantity,
            item.lastVerificationTime,
            item.isVerified
        );
    }

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
    ) external view returns (bool) {
        InventoryItem storage item = _inventory[seller][skuId][size];
        return item.isVerified && item.verifiedQuantity >= quantity;
    }

    /**
     * @notice Pauses the contract
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyAdmin {
        _unpause();
    }
}