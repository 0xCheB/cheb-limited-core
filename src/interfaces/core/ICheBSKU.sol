// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title ICheBSKU Interface
 * @author CheB Protocol
 * @notice Interface for the CheBSKU contract
 */
interface ICheBSKU {
    // Structs
    struct Size {
        uint256 basePrice;
        uint256 totalSupply;
        uint256 mintedSupply;
        bool isActive;
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

    // Events
    event SKUCreated(uint256 indexed skuId, string brand, string model, string metadataURI);
    event SKUUpdated(uint256 indexed skuId, string brand, string model, string metadataURI);
    event SKUStatusChanged(uint256 indexed skuId, bool active);
    event SizeAdded(uint256 indexed skuId, string size, uint256 price, uint256 supply);
    event BasePriceUpdated(uint256 indexed skuId, string size, uint256 price);
    event TotalSupplyUpdated(uint256 indexed skuId, string size, uint256 supply);
    event ProofContractSet(uint256 indexed skuId, address proofContract);

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
    ) external returns (uint256);

    /**
     * @notice Sets the proof contract for an SKU
     * @param skuId ID of the SKU
     * @param proofContract Address of the proof contract
     */
    function setProofContract(uint256 skuId, address proofContract) external;

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
    ) external;

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
    ) external;

    /**
     * @notice Sets the active status of an SKU
     * @param skuId ID of the SKU
     * @param active New active status
     */
    function setSKUStatus(uint256 skuId, bool active) external;

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
    ) external;

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
    ) external;

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
        returns (
            string memory brand,
            string memory model,
            string memory metadataURI,
            bool active,
            address proofContract
        );

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
        returns (
            uint256 basePrice,
            uint256 totalSupply,
            uint256 mintedSupply,
            bool isActive
        );

    /**
     * @notice Checks if a size exists for an SKU
     * @param skuId ID of the SKU
     * @param size Size identifier
     * @return bool True if the size exists
     */
    function isValidSize(uint256 skuId, string calldata size)
        external
        view
        returns (bool);

    /**
     * @notice Checks if an SKU exists
     * @param skuId ID of the SKU
     * @return bool True if the SKU exists
     */
    function skuExists(uint256 skuId) external view returns (bool);

    /**
     * @notice Pauses the contract
     */
    function pause() external;

    /**
     * @notice Unpauses the contract
     */
    function unpause() external;

    /**
     * @notice Returns the control center contract address
     */
    function controlCenter() external view returns (address);

    /**
     * @notice Returns the current SKU counter
     */
    function _skuCounter() external view returns (uint256);
}