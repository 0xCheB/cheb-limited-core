// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/accesscontrol/ICheBControlCenter.sol";

/**
 * @title CheBSKU
 * @author CheB Protocol
 * @notice Contract for managing SKUs and their sizes in the CheB protocol
 */
contract CheBSKU is ReentrancyGuard, Pausable {
    // State variables
    ICheBControlCenter public immutable controlCenter;
    
    struct Size {
        uint256 basePrice;
        uint256 totalSupply;
        uint256 mintedSupply;
        bool isActive;
    }
    
    struct SKU {
        string brand;
        string model;
        string metadataURI;
        bool active;
        address proofContract;
        mapping(string => Size) sizes;
    }

    // Custom errors
    error ZeroAddress();
    error InvalidControlCenter();
    error NotExecutive();
    error ControlCenterPaused();
    error EmptyString();
    error InvalidSKU();
    error InvalidSize();
    error SizeAlreadyExists();
    error PriceTooLow();
    error EmptyArray();
    error BatchTooLarge();
    error InvalidArrayLength();
    error NotAdmin();
    error SKUDataNotFound();
    error ProofContractAlreadySet();

    // Storage
    mapping(uint256 => SKU) public _skus;
    mapping(uint256 => mapping(string => bool)) public _skuSizes;
    mapping(uint256 => bool) public _exists;
    uint256 public _skuCounter;
    
    // Events
    event SKUCreated(uint256 indexed skuId, string brand, string model, string metadataURI);
    event SKUUpdated(uint256 indexed skuId, string brand, string model, string metadataURI);
    event SKUStatusChanged(uint256 indexed skuId, bool active);
    event SizeAdded(uint256 indexed skuId, string size, uint256 price, uint256 supply);
    event BasePriceUpdated(uint256 indexed skuId, string size, uint256 price);
    event TotalSupplyUpdated(uint256 indexed skuId, string size, uint256 supply);
    event ProofContractSet(uint256 indexed skuId, address proofContract);
    
    // Modifiers
    modifier onlyExecutive() {
        if (controlCenter.paused()) revert ControlCenterPaused();
        if (!controlCenter.hasRole(controlCenter.EXECUTIVE_ROLE(), msg.sender)) revert NotExecutive();
        _;
    }
    
    modifier onlyAdmin() {
        if (controlCenter.paused()) revert ControlCenterPaused();
        if (!controlCenter.hasRole(controlCenter.ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }
    
    modifier validSKU(uint256 skuId) {
        if (!_exists[skuId]) revert InvalidSKU();
        _;
    }
    
    /**
     * @notice Contract constructor
     * @param _controlCenter Address of the CheBControlCenter contract
     */
    constructor(address _controlCenter) {
        if (_controlCenter == address(0)) revert ZeroAddress();
        
        ICheBControlCenter center = ICheBControlCenter(_controlCenter);
        try center.EXECUTIVE_ROLE() returns (bytes32) {} catch { revert InvalidControlCenter(); }
        try center.hasRole(center.EXECUTIVE_ROLE(), msg.sender) returns (bool) {} catch { revert InvalidControlCenter(); }
        
        controlCenter = center;
    }

    /**
     * @notice Creates a new SKU
     * @param brand Brand name of the SKU
     * @param model Model name of the SKU
     * @param metadataURI URI for the SKU metadata
     * @return uint256 The ID of the created SKU
     */
    function createSKU(
        string calldata brand,
        string calldata model,
        string calldata metadataURI
    ) external onlyExecutive nonReentrant whenNotPaused returns (uint256) {
        if (bytes(brand).length == 0 || bytes(model).length == 0) revert EmptyString();
        if (bytes(metadataURI).length == 0) revert EmptyString();
        
        uint256 skuId = ++_skuCounter;
        _exists[skuId] = true;
        
        SKU storage newSku = _skus[skuId];
        newSku.brand = brand;
        newSku.model = model;
        newSku.metadataURI = metadataURI;
        newSku.active = true;

        emit SKUCreated(skuId, brand, model, metadataURI);
        return skuId;
    }

    /**
     * @notice Sets the proof contract for an SKU
     * @param skuId ID of the SKU
     * @param proofContract Address of the proof contract
     */
    function setProofContract(uint256 skuId, address proofContract) 
        external 
        onlyExecutive 
        nonReentrant 
        whenNotPaused 
        validSKU(skuId) 
    {
        if (proofContract == address(0)) revert ZeroAddress();
        if (_skus[skuId].proofContract != address(0)) revert ProofContractAlreadySet();
        
        _skus[skuId].proofContract = proofContract;
        emit ProofContractSet(skuId, proofContract);
    }

    /**
     * @notice Adds a new size to an SKU
     * @param skuId ID of the SKU
     * @param size Size identifier
     * @param price Base price for the size
     * @param supply Total supply for the size
     */
    function addSize(
        uint256 skuId,
        string calldata size,
        uint256 price,
        uint256 supply
    ) external onlyExecutive nonReentrant whenNotPaused validSKU(skuId) {
        if (bytes(size).length == 0) revert EmptyString();
        if (price == 0) revert PriceTooLow();
        if (_skuSizes[skuId][size]) revert SizeAlreadyExists();
        
        _skuSizes[skuId][size] = true;
        Size storage sizeData = _skus[skuId].sizes[size];
        sizeData.basePrice = price;
        sizeData.totalSupply = supply;
        sizeData.isActive = true;
        
        emit SizeAdded(skuId, size, price, supply);
    }
    
    /**
     * @notice Updates an existing SKU
     * @param skuId ID of the SKU to update
     * @param brand Updated brand name
     * @param model Updated model name
     * @param metadataURI Updated metadata URI
     */
    function updateSKU(
        uint256 skuId, 
        string calldata brand,
        string calldata model,
        string calldata metadataURI
    ) external onlyExecutive nonReentrant whenNotPaused validSKU(skuId) {
        if (bytes(brand).length == 0 || bytes(model).length == 0) revert EmptyString();
        if (bytes(metadataURI).length == 0) revert EmptyString();
        
        SKU storage sku = _skus[skuId];
        sku.brand = brand;
        sku.model = model;
        sku.metadataURI = metadataURI;
        
        emit SKUUpdated(skuId, brand, model, metadataURI);
    }
    
    /**
     * @notice Sets the active status of an SKU
     * @param skuId ID of the SKU
     * @param active New active status
     */
    function setSKUStatus(uint256 skuId, bool active) 
        external 
        onlyExecutive 
        nonReentrant 
        whenNotPaused 
        validSKU(skuId) 
    {
        _skus[skuId].active = active;
        emit SKUStatusChanged(skuId, active);
    }
    
    /**
     * @notice Updates the base price for a size
     * @param skuId ID of the SKU
     * @param size Size identifier
     * @param newPrice New base price
     */
    function updateBasePrice(
        uint256 skuId,
        string calldata size,
        uint256 newPrice
    ) external onlyExecutive nonReentrant whenNotPaused validSKU(skuId) {
        if (!_skuSizes[skuId][size]) revert InvalidSize();
        if (newPrice == 0) revert PriceTooLow();
        
        _skus[skuId].sizes[size].basePrice = newPrice;
        emit BasePriceUpdated(skuId, size, newPrice);
    }
    
    /**
     * @notice Updates the total supply for a size
     * @param skuId ID of the SKU
     * @param size Size identifier
     * @param newSupply New total supply
     */
    function updateTotalSupply(
        uint256 skuId,
        string calldata size,
        uint256 newSupply
    ) external onlyAdmin nonReentrant whenNotPaused validSKU(skuId) {
        if (!_skuSizes[skuId][size]) revert InvalidSize();
        Size storage sizeData = _skus[skuId].sizes[size];
        if (newSupply < sizeData.mintedSupply) revert InvalidSKU();
        
        sizeData.totalSupply = newSupply;
        emit TotalSupplyUpdated(skuId, size, newSupply);
    }
    
    /**
     * @notice Retrieves SKU information
     * @param skuId ID of the SKU
     * @return brand Brand name
     * @return model Model name
     * @return metadataURI Metadata URI
     * @return active Active status
     * @return proofContract Address of the proof contract
     */
    function getSKU(uint256 skuId) 
        external 
        view 
        validSKU(skuId) 
        returns (
            string memory brand,
            string memory model,
            string memory metadataURI,
            bool active,
            address proofContract
        ) 
    {
        SKU storage sku = _skus[skuId];
        if (bytes(sku.brand).length == 0) revert SKUDataNotFound();
        return (
            sku.brand,
            sku.model,
            sku.metadataURI,
            sku.active,
            sku.proofContract
        );
    }
    
    /**
     * @notice Retrieves size information for an SKU
     * @param skuId ID of the SKU
     * @param size Size identifier
     * @return basePrice Base price for the size
     * @return totalSupply Total supply for the size
     * @return mintedSupply Number of minted tokens for the size
     * @return isActive Active status of the size
     */
    function getSizeInfo(uint256 skuId, string calldata size) 
        external 
        view 
        validSKU(skuId) 
        returns (
            uint256 basePrice,
            uint256 totalSupply,
            uint256 mintedSupply,
            bool isActive
        ) 
    {
        if (!_skuSizes[skuId][size]) revert InvalidSize();
        Size storage sizeData = _skus[skuId].sizes[size];
        return (
            sizeData.basePrice,
            sizeData.totalSupply,
            sizeData.mintedSupply,
            sizeData.isActive
        );
    }
    
    /**
     * @notice Checks if a size exists for an SKU
     * @param skuId ID of the SKU
     * @param size Size identifier
     * @return bool True if the size exists
     */
    function isValidSize(uint256 skuId, string calldata size) 
        external 
        view 
        validSKU(skuId) 
        returns (bool) 
    {
        return _skuSizes[skuId][size];
    }

    /**
     * @notice Checks if an SKU exists
     * @param skuId ID of the SKU
     * @return bool True if the SKU exists
     */
    function skuExists(uint256 skuId) external view returns (bool) {
        return _exists[skuId];
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