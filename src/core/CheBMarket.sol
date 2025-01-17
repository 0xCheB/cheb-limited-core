// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/accesscontrol/ICheBControlCenter.sol";
import "../interfaces/core/ICheBListing.sol";
import "../interfaces/core/ICheBSKU.sol";
import "../interfaces/core/ICheBInventory.sol";
import "../interfaces/core/ICheBProofOfPurchase.sol";
import "../interfaces/core/ICheBSubscription.sol";

/**
 * @title CheBMarket Contract
 * @author CheB Protocol
 * @notice Manages marketplace functionality for buying and selling items with subscription-based access
 * @dev Implements market operations with subscription checks and role-based access control
 */
contract CheBMarket is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // State Variables
    ICheBControlCenter public immutable controlCenter;
    ICheBListing public immutable listingContract;
    ICheBSKU public immutable sku;
    ICheBInventory public immutable inventory;
    ICheBProofOfPurchase public immutable proofOfPurchase;
    ICheBSubscription public immutable subscription;
    IERC20 public immutable usdc;

    // Constants
    uint256 private constant PRECISION = 10000;
    uint256 private constant MIN_PRICE = 1e6;
    uint256 private immutable platformFee;
    uint256 private _purchaseCounter;

    // Custom Errors
    error ZeroAddress();
    error InvalidControlCenter();
    error InvalidListing();
    error InvalidSKU();
    error InvalidInventory();
    error InvalidProofOfPurchase();
    error InvalidUSDC();
    error InvalidSubscription();
    error NotAdmin();
    error NotExecutive();
    error ControlCenterPaused();
    error SellerNotWhitelisted();
    error InsufficientSubscription();
    error InvalidSize();
    error InvalidPrice();
    error InvalidQuantity();
    error InsufficientBalance();
    error InsufficientAllowance();
    error NoInventory();
    error NotVerified();
    error ListingNotFound();
    error BidNotFound();
    error BidTooLow();
    error AlreadyListed();
    error UnauthorizedSeller();
    error UnauthorizedBuyer();
    error InvalidState();
    error InsufficientFunds();
    error TransferFailed();

    struct Listing {
        address seller;
        uint256 skuId;
        string size;
        uint256 askingPrice;
        bool isActive;
    }

    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
        bool isActive;
    }

    // Storage
    mapping(bytes32 => Listing) private _listings;
    mapping(bytes32 => mapping(address => Bid)) private _bids;
    mapping(address => uint256) private _sellerListingCount;
    mapping(address => uint256) private _escrowBalances;

    // Events
    event ListingCreated(bytes32 indexed listingId, address indexed seller, uint256 indexed skuId, string size, uint256 askingPrice);
    event ListingUpdated(bytes32 indexed listingId, uint256 newAskingPrice);
    event ListingCancelled(bytes32 indexed listingId);
    event BidPlaced(bytes32 indexed listingId, address indexed bidder, uint256 amount);
    event BidAccepted(bytes32 indexed listingId, address indexed bidder, uint256 amount);
    event BidCancelled(bytes32 indexed listingId, address indexed bidder);
    event DirectPurchase(bytes32 indexed listingId, address indexed buyer, uint256 amount);
    event EscrowDeposited(address indexed account, uint256 amount);
    event EscrowReleased(address indexed account, uint256 amount);

    // Modifiers
    modifier onlyAdmin() {
        if (controlCenter.paused()) revert ControlCenterPaused();
        if (!controlCenter.hasRole(controlCenter.ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        _;
    }

    modifier onlyExecutive() {
        if (controlCenter.paused()) revert ControlCenterPaused();
        if (!controlCenter.hasRole(controlCenter.EXECUTIVE_ROLE(), msg.sender)) revert NotExecutive();
        _;
    }

    modifier validListing(bytes32 listingId) {
        if (!_listings[listingId].isActive) revert ListingNotFound();
        _;
    }

    modifier canBid() {
        (ICheBSubscription.SubscriptionTier tier, , bool isActive,) = subscription.getSubscription(msg.sender);
        if (!isActive || tier == ICheBSubscription.SubscriptionTier.Basic) revert InsufficientSubscription();
        _;
    }

    /**
     * @notice Contract constructor
     * @param _controlCenter Address of the CheBControlCenter contract
     * @param _listing Address of the CheBListing contract
     * @param _sku Address of the CheBSKU contract
     * @param _inventory Address of the CheBInventory contract
     * @param _proofOfPurchase Address of the CheBProofOfPurchase contract
     * @param _subscription Address of the CheBSubscription contract
     * @param _usdc Address of the USDC token contract
     * @param _platformFee Platform fee in basis points (100 = 1%)
     */
    constructor(
        address _controlCenter,
        address _listing,
        address _sku,
        address _inventory,
        address _proofOfPurchase,
        address _subscription,
        address _usdc,
        uint256 _platformFee
    ) {
        if (_controlCenter == address(0) || _listing == address(0) || 
            _sku == address(0) || _inventory == address(0) || 
            _proofOfPurchase == address(0) || _subscription == address(0) ||
            _usdc == address(0)) revert ZeroAddress();
        if (_platformFee > PRECISION) revert InvalidPrice();

        // Validate all contract interfaces
        _validateInterfaces(
            _controlCenter, _listing, _sku, _inventory, 
            _proofOfPurchase, _subscription, _usdc
        );

        controlCenter = ICheBControlCenter(_controlCenter);
        listingContract = ICheBListing(_listing);
        sku = ICheBSKU(_sku);
        inventory = ICheBInventory(_inventory);
        proofOfPurchase = ICheBProofOfPurchase(_proofOfPurchase);
        subscription = ICheBSubscription(_subscription);
        usdc = IERC20(_usdc);
        platformFee = _platformFee;
    }

    /**
     * @notice Validates all contract interfaces during construction
     */
    function _validateInterfaces(
        address _controlCenter,
        address _listing,
        address _sku,
        address _inventory,
        address _proofOfPurchase,
        address _subscription,
        address _usdc
    ) private view {
        try ICheBControlCenter(_controlCenter).ADMIN_ROLE() returns (bytes32) {} catch { 
            revert InvalidControlCenter(); 
        }
        try ICheBListing(_listing).whitelist(address(0)) returns (bool) {} catch { 
            revert InvalidListing(); 
        }
        try ICheBSKU(_sku).skuExists(0) returns (bool) {} catch { 
            revert InvalidSKU(); 
        }
        try ICheBInventory(_inventory).hasVerifiedInventory(address(0), 0, "", 0) returns (bool) {} catch { 
            revert InvalidInventory(); 
        }
        try ICheBProofOfPurchase(_proofOfPurchase).VERSION() returns (string memory) {} catch { 
            revert InvalidProofOfPurchase(); 
        }
        try ICheBSubscription(_subscription).getSubscription(address(0)) returns (
            ICheBSubscription.SubscriptionTier, uint256, bool, uint256
        ) {} catch { 
            revert InvalidSubscription(); 
        }
        try IERC20(_usdc).totalSupply() returns (uint256) {} catch { 
            revert InvalidUSDC(); 
        }
    }

    /**
     * @notice Creates a new listing
     * @param skuId SKU identifier
     * @param size Size of the item
     * @param askingPrice Price in USDC
     * @return bytes32 Unique listing identifier
     */
    function createListing(
        uint256 skuId, 
        string calldata size, 
        uint256 askingPrice
    ) external whenNotPaused nonReentrant returns (bytes32) {
        if (!listingContract.whitelist(msg.sender)) revert SellerNotWhitelisted();
        if (!sku.skuExists(skuId)) revert InvalidSKU();
        if (!sku.isValidSize(skuId, size)) revert InvalidSize();
        if (askingPrice < MIN_PRICE) revert InvalidPrice();
        if (!inventory.hasVerifiedInventory(msg.sender, skuId, size, 1)) revert NoInventory();

        bytes32 listingId = keccak256(
            abi.encodePacked(msg.sender, skuId, size, _sellerListingCount[msg.sender]++)
        );
        
        _listings[listingId] = Listing(msg.sender, skuId, size, askingPrice, true);

        emit ListingCreated(listingId, msg.sender, skuId, size, askingPrice);
        return listingId;
    }

    /**
     * @notice Updates the asking price of a listing
     * @param listingId Listing identifier
     * @param newAskingPrice New price in USDC
     */
    function updateListing(bytes32 listingId, uint256 newAskingPrice) 
        external 
        whenNotPaused 
        nonReentrant 
        validListing(listingId) 
    {
        Listing storage currentListing = _listings[listingId];
        if (currentListing.seller != msg.sender) revert UnauthorizedSeller();
        if (newAskingPrice < MIN_PRICE) revert InvalidPrice();

        currentListing.askingPrice = newAskingPrice;
        emit ListingUpdated(listingId, newAskingPrice);
    }

    /**
     * @notice Cancels an active listing
     * @param listingId Listing identifier
     */
    function cancelListing(bytes32 listingId) 
        external 
        whenNotPaused 
        nonReentrant 
        validListing(listingId) 
    {
        Listing storage currentListing = _listings[listingId];
        if (currentListing.seller != msg.sender && !controlCenter.hasRole(controlCenter.ADMIN_ROLE(), msg.sender)) 
            revert UnauthorizedSeller();

        currentListing.isActive = false;
        emit ListingCancelled(listingId);
    }

    /**
     * @notice Places a bid on a listing
     * @param listingId Listing identifier
     * @param bidAmount Bid amount in USDC
     */
    function placeBid(bytes32 listingId, uint256 bidAmount) 
        external 
        whenNotPaused 
        nonReentrant 
        validListing(listingId)
        canBid
    {
        if (bidAmount < MIN_PRICE) revert InvalidPrice();
        
        Listing storage currentListing = _listings[listingId];
        (, uint256 basePrice, ,) = sku.getSizeInfo(currentListing.skuId, currentListing.size);
        if (bidAmount < basePrice) revert BidTooLow();

        uint256 totalAmount = bidAmount + calculateFee(bidAmount);
        if (usdc.balanceOf(msg.sender) < totalAmount) revert InsufficientBalance();
        if (usdc.allowance(msg.sender, address(this)) < totalAmount) revert InsufficientAllowance();

        _bids[listingId][msg.sender] = Bid(msg.sender, bidAmount, block.timestamp, true);

        usdc.safeTransferFrom(msg.sender, address(this), totalAmount);
        _escrowBalances[msg.sender] += totalAmount;

        emit BidPlaced(listingId, msg.sender, bidAmount);
        emit EscrowDeposited(msg.sender, totalAmount);
    }

    /**
     * @notice Accepts a bid on a listing
     * @param listingId Listing identifier
     * @param bidder Address of the bidder
     */
    function acceptBid(bytes32 listingId, address bidder) 
        external 
        whenNotPaused 
        nonReentrant 
        validListing(listingId) 
    {
        Listing storage currentListing = _listings[listingId];
        if (currentListing.seller != msg.sender) revert UnauthorizedSeller();
        
        Bid storage bid = _bids[listingId][bidder];
        if (!bid.isActive) revert BidNotFound();

        inventory.reserveInventory(msg.sender, currentListing.skuId, currentListing.size, 1);

        uint256 fee = calculateFee(bid.amount);
        _releaseFunds(msg.sender, bid.amount);
        _releaseFunds(address(this), fee);

        _mintProofOfPurchase(
            bidder, 
            currentListing.seller, 
            currentListing.size, 
            bid.amount
        );

        currentListing.isActive = false;
        bid.isActive = false;

        emit BidAccepted(listingId, bidder, bid.amount);
    }

    /**
     * @notice Cancels a placed bid
     * @param listingId Listing identifier
     */
    function cancelBid(bytes32 listingId) external whenNotPaused nonReentrant {
        Bid storage bid = _bids[listingId][msg.sender];
        if (!bid.isActive) revert BidNotFound();

        uint256 totalAmount = bid.amount + calculateFee(bid.amount);
        _releaseFunds(msg.sender, totalAmount);

        bid.isActive = false;
        emit BidCancelled(listingId, msg.sender);
    }

    /**
     * @notice Purchases a listing directly at asking price
     * @param listingId Listing identifier
     */
    function purchaseDirectly(bytes32 listingId) 
        external 
        whenNotPaused 
        nonReentrant 
        validListing(listingId) 
    {
        Listing storage currentListing = _listings[listingId];
        uint256 totalAmount = currentListing.askingPrice + calculateFee(currentListing.askingPrice);

        if (usdc.balanceOf(msg.sender) < totalAmount) revert InsufficientBalance();
        if (usdc.allowance(msg.sender, address(this)) < totalAmount) revert InsufficientAllowance();

        usdc.safeTransferFrom(msg.sender, address(this), totalAmount);

        inventory.reserveInventory(currentListing.seller, currentListing.skuId, currentListing.size, 1);

        uint256 fee = calculateFee(currentListing.askingPrice);
        _processPayment(currentListing.seller, currentListing.askingPrice, fee);

        _mintProofOfPurchase(
            msg.sender, 
            currentListing.seller, 
            currentListing.size, 
            currentListing.askingPrice
        );

        currentListing.isActive = false;

        emit DirectPurchase(listingId, msg.sender, currentListing.askingPrice);
    }

    /**
     * @notice Gets details of a listing
     * @param listingId Listing identifier
     * @return seller Address of the seller
     * @return skuId SKU identifier
     * @return size Size of the item
     * @return askingPrice Price in USDC
     * @return isActive Whether the listing is active
     */
    function getListing(bytes32 listingId) 
        external 
        view 
        returns (
            address seller,
            uint256 skuId,
            string memory size,
            uint256 askingPrice,
            bool isActive
        ) 
    {
        Listing storage currentListing = _listings[listingId];
        return (
            currentListing.seller,
            currentListing.skuId,
            currentListing.size,
            currentListing.askingPrice,
            currentListing.isActive
        );
    }

    /**
     * @notice Gets details of a bid
     * @param listingId Listing identifier
     * @param bidder Address of the bidder
     * @return amount Bid amount in USDC
     * @return timestamp Timestamp of the bid
     * @return isActive Whether the bid is active
     */
    function getBid(bytes32 listingId, address bidder) 
        external 
        view 
        returns (
            uint256 amount,
            uint256 timestamp,
            bool isActive
        ) 
    {
        Bid storage bid = _bids[listingId][bidder];
        return (bid.amount, bid.timestamp, bid.isActive);
    }

    /**
     * @notice Calculates platform fee for a given amount
     * @param amount Amount to calculate fee for
     * @return uint256 Fee amount
     */
    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * platformFee) / PRECISION;
    }

    /**
     * @notice Gets escrow balance for an account
     * @param account Address to check
     * @return uint256 Escrow balance in USDC
     */
    function getEscrowBalance(address account) external view returns (uint256) {
        return _escrowBalances[account];
    }

    /**
     * @notice Processes payment to seller and platform
     * @param seller Address of the seller
     * @param amount Payment amount
     * @param fee Platform fee amount
     */
    function _processPayment(
        address seller,
        uint256 amount,
        uint256 fee
    ) private {
        if (usdc.balanceOf(address(this)) < amount + fee) revert InsufficientFunds();
        
        usdc.safeTransfer(seller, amount);
        
        if (fee > 0) {
            usdc.safeTransfer(address(this), fee);
        }
    }

    /**
     * @notice Releases funds from escrow
     * @param to Address to release funds to
     * @param amount Amount to release
     */
    function _releaseFunds(address to, uint256 amount) private {
        if (usdc.balanceOf(address(this)) < amount) revert InsufficientFunds();
        
        _escrowBalances[to] -= amount;
        usdc.safeTransfer(to, amount);
        emit EscrowReleased(to, amount);
    }

    /**
     * @notice Mints proof of purchase NFT
     * @param buyer Address of the buyer
     * @param seller Address of the seller
     * @param size Size of the item
     * @param price Purchase price
     * @return uint256 Token ID of the minted NFT
     */
    function _mintProofOfPurchase(
        address buyer,
        address seller,
        string memory size,
        uint256 price
    ) private returns (uint256) {
        uint256 purchaseId = ++_purchaseCounter;
        return proofOfPurchase.mintProof(buyer, seller, size, price, purchaseId);
    }

    /**
     * @notice Withdraws accumulated platform fees
     * @param to Address to withdraw to
     * @param amount Amount to withdraw
     */
    function withdrawFees(address to, uint256 amount) external onlyAdmin {
        if (usdc.balanceOf(address(this)) < amount) revert InsufficientFunds();
        usdc.safeTransfer(to, amount);
    }

    /**
     * @notice Pauses all contract operations
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @notice Unpauses all contract operations
     */
    function unpause() external onlyAdmin {
        _unpause();
    }
}