// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/accesscontrol/ICheBControlCenter.sol";

/**
 * @title CheBProofOfPurchase
 * @author CheB Protocol
 * @notice ERC1155 token contract for managing proof of purchase NFTs
 */
contract CheBProofOfPurchase is ERC1155, ReentrancyGuard, Pausable {
    // State variables
    ICheBControlCenter public immutable controlCenter;
    uint256 public immutable skuId;
    string public constant VERSION = "2.0.0";

    // Custom errors
    error ZeroAddress();
    error InvalidControlCenter();
    error NotAdmin();
    error NotMinter();
    error ControlCenterPaused();
    error InvalidTokenId();
    error InvalidURI();
    error AlreadyMinted();

    struct PurchaseDetails {
        address originalSeller;
        string size;
        uint256 purchasePrice;
        uint256 purchaseTimestamp;
        uint256 purchaseId;
        bool authenticated;
    }

    // Storage
    mapping(uint256 => PurchaseDetails) private _purchaseDetails;
    mapping(uint256 => bool) private _tokenIdUsed;
    uint256 private _tokenIdCounter;

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

    // Modifiers
    modifier onlyAdmin() {
        if (controlCenter.paused()) revert ControlCenterPaused();
        if (!controlCenter.hasRole(controlCenter.ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyMinter() {
        if (controlCenter.paused()) revert ControlCenterPaused();
        if (!controlCenter.hasRole(controlCenter.VERIFIER_ROLE(), msg.sender)) revert NotMinter();
        _;
    }

    /**
     * @notice Contract constructor
     * @param _controlCenter Address of the CheBControlCenter contract
     * @param _skuId SKU identifier
     * @param _baseUri Base URI for token metadata
     */
    constructor(
        address _controlCenter,
        uint256 _skuId,
        string memory _baseUri
    ) ERC1155(_baseUri) {
        if (_controlCenter == address(0)) revert ZeroAddress();
        if (bytes(_baseUri).length == 0) revert InvalidURI();

        try ICheBControlCenter(_controlCenter).ADMIN_ROLE() returns (bytes32) {} catch { 
            revert InvalidControlCenter(); 
        }

        controlCenter = ICheBControlCenter(_controlCenter);
        skuId = _skuId;
    }

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
    ) external onlyMinter nonReentrant whenNotPaused returns (uint256) {
        if (_tokenIdUsed[purchaseId]) revert AlreadyMinted();
        
        uint256 tokenId = ++_tokenIdCounter;
        _tokenIdUsed[purchaseId] = true;

        _purchaseDetails[tokenId] = PurchaseDetails({
            originalSeller: seller,
            size: size,
            purchasePrice: purchasePrice,
            purchaseTimestamp: block.timestamp,
            purchaseId: purchaseId,
            authenticated: false
        });

        _mint(owner, tokenId, 1, "");

        emit ProofMinted(
            tokenId,
            owner,
            size,
            seller,
            purchasePrice,
            purchaseId
        );

        return tokenId;
    }

    /**
     * @notice Authenticates a token
     * @param tokenId ID of the token to authenticate
     */
    function authenticateToken(uint256 tokenId) 
        external 
        onlyAdmin 
        nonReentrant 
        whenNotPaused 
    {
        if (tokenId == 0 || tokenId > _tokenIdCounter) revert InvalidTokenId();
        
        _purchaseDetails[tokenId].authenticated = true;
        
        emit TokenAuthenticated(tokenId, msg.sender);
    }

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
        ) 
    {
        if (tokenId == 0 || tokenId > _tokenIdCounter) revert InvalidTokenId();
        
        PurchaseDetails storage details = _purchaseDetails[tokenId];
        return (
            details.originalSeller,
            details.size,
            details.purchasePrice,
            details.purchaseTimestamp,
            details.purchaseId,
            details.authenticated
        );
    }

    /**
     * @notice Checks if a purchase ID has been used to mint a token
     * @param purchaseId Purchase ID to check
     * @return bool True if the purchase ID has been used
     */
    function isTokenMinted(uint256 purchaseId) external view returns (bool) {
        return _tokenIdUsed[purchaseId];
    }

    /**
     * @notice Sets a new base URI for token metadata
     * @param newuri New base URI
     */
    function setURI(string memory newuri) external onlyAdmin {
        if (bytes(newuri).length == 0) revert InvalidURI();
        _setURI(newuri);
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

    /**
     * @notice Override of ERC1155 _update to add pause check
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual override whenNotPaused {
        super._update(from, to, ids, values);
    }
}