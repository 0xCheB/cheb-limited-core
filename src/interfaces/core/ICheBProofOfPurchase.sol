// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title ICheBProofOfPurchase
 * @author CheB Protocol
 * @notice Interface for the CheBProofOfPurchase contract
 */
interface ICheBProofOfPurchase is IERC1155 {
    // Structs
    struct PurchaseDetails {
        address originalSeller;
        string size;
        uint256 purchasePrice;
        uint256 purchaseTimestamp;
        uint256 purchaseId;
        bool authenticated;
    }

    // Custom errors
    error ZeroAddress();
    error InvalidControlCenter();
    error NotAdmin();
    error NotMinter();
    error ControlCenterPaused();
    error InvalidTokenId();
    error InvalidURI();
    error AlreadyMinted();

    // Events
    event ProofMinted(
        uint256 indexed tokenId,
        address indexed owner,
        string size,
        address originalSeller,
        uint256 purchasePrice,
        uint256 purchaseId
    );

    event TokenAuthenticated(
        uint256 indexed tokenId,
        address indexed authenticator
    );

    /**
     * @notice Returns the control center contract
     */
    function controlCenter() external view returns (address);

    /**
     * @notice Returns the SKU ID
     */
    function skuId() external view returns (uint256);

    /**
     * @notice Returns the contract version
     */
    function VERSION() external pure returns (string memory);

    /**
     * @notice Mints a new proof of purchase token
     * @param owner Address that will receive the token
     * @param seller Address of the original seller
     * @param size Size of the purchased item
     * @param purchasePrice Price of the purchase
     * @param purchaseId Unique identifier for the purchase
     * @return tokenId The ID of the minted token
     */
    function mintProof(
        address owner,
        address seller,
        string calldata size,
        uint256 purchasePrice,
        uint256 purchaseId
    ) external returns (uint256);

    /**
     * @notice Authenticates a token
     * @param tokenId ID of the token to authenticate
     */
    function authenticateToken(uint256 tokenId) external;

    /**
     * @notice Retrieves purchase details for a token
     * @param tokenId ID of the token
     * @return originalSeller Address of the original seller
     * @return size Size of the purchased item
     * @return purchasePrice Price of the purchase
     * @return purchaseTimestamp Timestamp of the purchase
     * @return purchaseId Unique identifier for the purchase
     * @return authenticated Whether the token has been authenticated
     */
    function getPurchaseDetails(uint256 tokenId)
        external
        view
        returns (
            address originalSeller,
            string memory size,
            uint256 purchasePrice,
            uint256 purchaseTimestamp,
            uint256 purchaseId,
            bool authenticated
        );

    /**
     * @notice Checks if a purchase ID has been used to mint a token
     * @param purchaseId Purchase ID to check
     * @return bool True if the purchase ID has been used
     */
    function isTokenMinted(uint256 purchaseId) external view returns (bool);

    /**
     * @notice Sets a new base URI for token metadata
     * @param newuri New base URI
     */
    function setURI(string memory newuri) external;

    /**
     * @notice Pauses the contract
     */
    function pause() external;

    /**
     * @notice Unpauses the contract
     */
    function unpause() external;
}