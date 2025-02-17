// CheBMarketplace.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICheBProofOfPurchase.sol";
import "./interfaces/ICheBProofOfPurchaseFactory.sol";
import "./interfaces/ICheBSubscription.sol";
import "./interfaces/ICheBControlCenter.sol"; // Import for error visibility

/**
 * @title CheBMarketplace
 * @notice Manages listings, bids, and purchases for CheBProofOfPurchase tokens.
 *  This contract provides a platform for verified sellers to list and sell their
 *  CheBProofOfPurchase (POP) tokens, either through direct sales or auctions,
 *  using USDC as the payment currency. It handles listing creation, order management,
 *  escrow, subscription verification, and delivery fee processing.
 */
contract CheBMarketplace is ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    /* @notice Core contract references - Set at deployment and immutable */
    ICheBControlCenter public immutable chebControl;
    ICheBProofOfPurchaseFactory public immutable factory;
    ICheBSubscription public immutable subscription;
    IERC20 public immutable usdc;

    /* @notice State variables */
    Counters.Counter public listingIds;
    Counters.Counter public orderIds;
    Counters.Counter public bidIds;

    /* @notice Escrow management */
    mapping(address => uint256) public owedFunds;
    mapping(uint256 => uint256) public lockedInventory;
    mapping(uint256 => bool) public orderFeesPaid;
    uint256 public accumulatedFees; // Accumulated delivery fees

    /* @notice Enums */
    enum OrderState { Created, Accepted, Delivered, Cancelled }
    enum ListingType { DirectSale, Auction }

    /* @notice Structs */
    struct Listing {
        uint256 skuId;
        uint256 size;
        uint256 price;
        address seller;
        uint256 timestamp;
        bool active;
        ListingType listingType;
        uint256 minBidPrice;
    }

    struct Order {
        address buyer;
        address seller;
        uint256 skuId;
        uint256 size;
        uint256 price;
        OrderState state;
        uint256 timestamp;
    }

    struct Bid {
        address bidder;
        uint256 listingId;
        uint256 amount;
        uint256 timestamp;
        bool active;
    }

    /* @notice Mappings */
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => Bid) public bids;
    mapping(uint256 => uint256) public orderEscrow;
    mapping(uint256 => mapping(address => bool)) public blockedBidders;

    /* @notice Custom errors */
    error Unauthorized();
    error InvalidListing();
    error InvalidOrder();
    error InvalidBid();
    error InsufficientBalance();
    error InsufficientAllowance();
    error InvalidPrice();
    error InvalidState();
    error BidderIsBlocked();
    error SubscriptionRequiredForSKU(); // More specific error for subscription issues
    error InsufficientSubscriptionTierForSKU(); // More specific error for subscription issues
    error DeliveryFeesAlreadyPaid();
    error NoFeesToWithdraw();

    /* @notice Events */
    event ListingCreated(
        uint256 indexed listingId,
        uint256 indexed skuId,
        uint256 size,
        uint256 price,
        address seller,
        ListingType listingType
    );
    event ListingUpdated(uint256 indexed listingId, uint256 newPrice);
    event ListingCancelled(uint256 indexed listingId);
    event OrderCreated(
        uint256 indexed orderId,
        uint256 indexed listingId,
        address buyer,
        address seller,
        uint256 price
    );
    event OrderStateChanged(uint256 indexed orderId, OrderState state);
    event BidPlaced(
        uint256 indexed bidId,
        uint256 indexed listingId,
        address bidder,
        uint256 amount
    );
    event BidAccepted(uint256 indexed bidId, uint256 indexed listingId);
    event BidRejected(uint256 indexed bidId, uint256 indexed listingId);
    event BidderBlocked(uint256 indexed listingId, address indexed bidder);
    event BidderUnblocked(uint256 indexed listingId, address indexed bidder);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    event InventoryLocked(uint256 indexed listingId, uint256 amount);
    event InventoryReleased(uint256 indexed listingId, uint256 amount);
    event DeliveryFeePaid(uint256 indexed orderId, uint256 amount);
    event DeliveryFeesWithdrawn(address indexed admin, uint256 amount);

    /**
     * @param _chebControl Address of the CheBControlCenter contract.
     * @param _factory Address of the CheBProofOfPurchaseFactory contract.
     * @param _subscription Address of the CheBSubscription contract.
     * @param _usdc Address of the USDC ERC20 token contract.
     */
    constructor(
        address _chebControl,
        address _factory,
        address _subscription,
        address _usdc
    ) {
        chebControl = ICheBControlCenter(_chebControl);
        factory = ICheBProofOfPurchaseFactory(_factory);
        subscription = ICheBSubscription(_subscription);
        usdc = IERC20(_usdc);
    }

    /**
     * @dev Modifier to restrict access to only verified sellers.
     *  Verifies if the sender is a verified seller using CheBControlCenter.
     */
    modifier onlyVerifiedSeller() {
        if (!chebControl.isVerifiedSeller(msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @dev Modifier to restrict access to only verifiers.
     *  Verifies if the sender has the VERIFIER_ROLE using CheBControlCenter.
     */
    modifier onlyVerifier() {
        if (!chebControl.hasRole(chebControl.VERIFIER_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Creates a new listing for a CheBProofOfPurchase token.
     * @param skuId The Stock Keeping Unit ID of the CheBProofOfPurchase token.
     * @param size The size of the CheBProofOfPurchase token being listed.
     * @param price The listing price in USDC.
     * @param listingType The type of listing (DirectSale or Auction).
     * @param minBidPrice The minimum bid price for auction listings. Set to 0 for DirectSale.
     * @return newListingId The ID of the newly created listing.
     * @dev Only verified sellers can create listings.
     *  It validates the SKU, size availability, and seller inventory.
     *  Locks the listed token in escrow within this contract.
     *  @dev Modifier: onlyVerifiedSeller, whenNotPaused
     *  @dev Emits: {InventoryLocked}, {ListingCreated}
     *  @dev Throws: {InvalidListing}, {Unauthorized}
     */
    function createListing(
        uint256 skuId,
        uint256 size,
        uint256 price,
        ListingType listingType,
        uint256 minBidPrice
    ) external onlyVerifiedSeller whenNotPaused returns (uint256) {
        address tokenAddress = factory.skuToToken(skuId);
        if (tokenAddress == address(0)) revert InvalidListing();

        ICheBProofOfPurchase token = ICheBProofOfPurchase(tokenAddress);
        if (!token.isSizeAvailable(size)) revert InvalidListing();
        uint256 sellerBalance = token.sellerInventory(msg.sender, size);
        if (sellerBalance == 0) revert InvalidListing();

        // Lock inventory in marketplace escrow
        token.lockTokens(msg.sender, address(this), size, 1);

        listingIds.increment();
        uint256 newListingId = listingIds.current();
        lockedInventory[newListingId] = 1;

        listings[newListingId] = Listing({
            skuId: skuId,
            size: size,
            price: price,
            seller: msg.sender,
            timestamp: block.timestamp,
            active: true,
            listingType: listingType,
            minBidPrice: minBidPrice
        });

        emit InventoryLocked(newListingId, 1);
        emit ListingCreated(
            newListingId,
            skuId,
            size,
            price,
            msg.sender,
            listingType
        );

        return newListingId;
    }

    /**
     * @notice Updates the price of an existing listing.
     * @param listingId The ID of the listing to update.
     * @param newPrice The new price for the listing in USDC.
     * @dev Only the seller of the listing can update its price.
     * @dev Modifier: whenNotPaused
     * @dev Throws: {Unauthorized}, {InvalidListing}
     * @dev Emits: {ListingUpdated}
     */
    function updateListing(uint256 listingId, uint256 newPrice)
        external
        whenNotPaused
    {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert Unauthorized();
        if (!listing.active) revert InvalidListing();

        listing.price = newPrice;
        emit ListingUpdated(listingId, newPrice);
    }

    /**
     * @notice Cancels an active listing.
     * @param listingId The ID of the listing to cancel.
     * @dev Only the seller of the listing can cancel it.
     *  Returns the locked inventory back to the seller.
     * @dev Modifier: whenNotPaused
     * @dev Throws: {Unauthorized}, {InvalidListing}
     * @dev Emits: {InventoryReleased}, {ListingCancelled}
     */
    function cancelListing(uint256 listingId) external whenNotPaused {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert Unauthorized();
        if (!listing.active) revert InvalidListing();

        // Return locked inventory to seller
        ICheBProofOfPurchase token = ICheBProofOfPurchase(
            factory.skuToToken(listing.skuId)
        );
        token.returnTokensToSeller(listing.seller, address(0), listing.size, lockedInventory[listingId]); // Using returnTokensToSeller - removed listing.buyer
        // token.releaseTokens(address(this), listing.seller, listing.size, lockedInventory[listingId]); // Old - replaced with returnTokensToSeller

        listing.active = false;
        emit InventoryReleased(listingId, lockedInventory[listingId]);
        delete lockedInventory[listingId];
        emit ListingCancelled(listingId);
    }

    /**
     * @notice Purchases a direct sale listing.
     * @param listingId The ID of the listing to purchase.
     * @dev Allows a buyer to purchase a listing of type DirectSale.
     *  Validates subscription and transfers USDC from buyer to the contract.
     *  Creates a new order and deactivates the listing.
     * @dev Modifier: nonReentrant, whenNotPaused
     * @dev Throws: {InvalidListing}, {SubscriptionRequiredForSKU}, {InsufficientSubscriptionTierForSKU}, {InsufficientBalance}, {InsufficientAllowance}
     * @dev Emits: {OrderCreated}
     */
    function purchase(uint256 listingId)
        external
        nonReentrant
        whenNotPaused
    {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert InvalidListing();
        if (listing.listingType != ListingType.DirectSale) revert InvalidListing();

        // Validate subscription tier
        (ICheBSubscription.SubscriptionTier tier, , bool isActive, ) =
            subscription.getSubscription(msg.sender);
        if (!isActive) revert SubscriptionRequiredForSKU(); // More specific error
        if (!factory.skuTierAccess(listing.skuId, tier)) {
            revert InsufficientSubscriptionTierForSKU(); // More specific error
        }

        // Handle USDC transfer
        if (usdc.balanceOf(msg.sender) < listing.price) revert InsufficientBalance();
        if (usdc.allowance(msg.sender, address(this)) < listing.price) {
            revert InsufficientAllowance();
        }

        usdc.safeTransferFrom(msg.sender, address(this), listing.price);

        // Create order
        orderIds.increment();
        uint256 newOrderId = orderIds.current();

        orders[newOrderId] = Order({
            buyer: msg.sender,
            seller: listing.seller,
            skuId: listing.skuId,
            size: listing.size,
            price: listing.price,
            state: OrderState.Created,
            timestamp: block.timestamp
        });

        orderEscrow[newOrderId] = listing.price;
        listing.active = false;

        emit OrderCreated(
            newOrderId,
            listingId,
            msg.sender,
            listing.seller,
            listing.price
        );
    }

    /**
     * @notice Places a bid on an auction listing.
     * @param listingId The ID of the listing to bid on.
     * @param amount The bid amount in USDC.
     * @dev Allows a bidder to place a bid on a listing of type Auction.
     *  Validates listing activity, listing type, bid amount, bidder block status and subscription tier.
     * @dev Modifier: nonReentrant, whenNotPaused
     * @dev Throws: {InvalidListing}, {InvalidBid}, {BidderIsBlocked}, {SubscriptionRequiredForSKU}, {InsufficientSubscriptionTierForSKU}
     * @dev Emits: {BidPlaced}
     */
    function placeBid(uint256 listingId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert InvalidListing();
        if (listing.listingType != ListingType.Auction) revert InvalidListing();
        if (amount < listing.minBidPrice) revert InvalidBid();
        if (blockedBidders[listingId][msg.sender]) revert BidderIsBlocked();

        // Validate subscription tier
        (ICheBSubscription.SubscriptionTier tier, , bool isActive, ) =
            subscription.getSubscription(msg.sender);
        if (!isActive) revert SubscriptionRequiredForSKU(); // More specific error
        if (!factory.skuTierAccess(listing.skuId, tier)) {
            revert InsufficientSubscriptionTierForSKU(); // More specific error
        }

        bidIds.increment();
        uint256 newBidId = bidIds.current();

        bids[newBidId] = Bid({
            bidder: msg.sender,
            listingId: listingId,
            amount: amount,
            timestamp: block.timestamp,
            active: true
        });

        emit BidPlaced(newBidId, listingId, msg.sender, amount);
    }

    /**
     * @notice Accepts a bid on an auction listing.
     * @param bidId The ID of the bid to accept.
     * @dev Allows the seller to accept a bid, creating an order and transferring USDC.
     *  Validates seller authorization, listing/bid activity and available balance/allowance of bidder.
     *  Creates a new order, escrows funds and deactivates listing and bid.
     * @dev Modifier: nonReentrant, whenNotPaused
     * @dev Throws: {Unauthorized}, {InvalidState}, {InvalidListing}, {InsufficientBalance}, {InsufficientAllowance}
     * @dev Emits: {BidAccepted}, {OrderCreated}
     */
    function acceptBid(uint256 bidId)
        external
        nonReentrant
        whenNotPaused
    {
        Bid storage bid = bids[bidId];
        Listing storage listing = listings[bid.listingId];

        if (listing.seller != msg.sender) revert Unauthorized();
        if (!listing.active || !bid.active) revert InvalidState();

        // Re-verify listing active status to prevent race condition
        if (!listing.active) revert InvalidListing(); // Re-verify listing active status

        // Handle USDC transfer
        if (usdc.balanceOf(bid.bidder) < bid.amount) revert InsufficientBalance();
        if (usdc.allowance(bid.bidder, address(this)) < bid.amount) {
            revert InsufficientAllowance();
        }

        usdc.safeTransferFrom(bid.bidder, address(this), bid.amount);

        // Create order
        orderIds.increment();
        uint256 newOrderId = orderIds.current();

        orders[newOrderId] = Order({
            buyer: bid.bidder,
            seller: listing.seller,
            skuId: listing.skuId,
            size: listing.size,
            price: bid.amount,
            state: OrderState.Created,
            timestamp: block.timestamp
        });

        orderEscrow[newOrderId] = bid.amount;
        listing.active = false;
        bid.active = false;

        emit BidAccepted(bidId, bid.listingId);
        emit OrderCreated(
            newOrderId,
            bid.listingId,
            bid.bidder,
            listing.seller,
            bid.amount
        );
    }

    /**
     * @notice Rejects a bid on an auction listing.
     * @param bidId The ID of the bid to reject.
     * @dev Allows the seller to reject a bid, deactivating the bid.
     *  Validates seller authorization and bid activity.
     * @dev Modifier: whenNotPaused
     * @dev Throws: {Unauthorized}, {InvalidState}
     * @dev Emits: {BidRejected}
     */
    function rejectBid(uint256 bidId) external whenNotPaused {
        Bid storage bid = bids[bidId];
        Listing storage listing = listings[bid.listingId];

        if (listing.seller != msg.sender) revert Unauthorized();
        if (!bid.active) revert InvalidState();

        bid.active = false;
        emit BidRejected(bidId, bid.listingId);
    }

    /**
     * @notice Blocks a bidder from placing bids on a specific listing.
     * @param listingId The ID of the listing.
     * @param bidder The address of the bidder to block.
     * @dev Allows the seller to block a bidder from participating in an auction listing.
     *  Validates seller authorization.
     * @dev Modifier: whenNotPaused
     * @dev Throws: {Unauthorized}
     * @dev Emits: {BidderBlocked}
     */
    function blockBidder(uint256 listingId, address bidder)
        external
        whenNotPaused
    {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert Unauthorized();

        blockedBidders[listingId][bidder] = true;
        emit BidderBlocked(listingId, bidder);
    }

    /**
     * @notice Unblocks a bidder, allowing them to bid on a specific listing again.
     * @param listingId The ID of the listing.
     * @param bidder The address of the bidder to unblock.
     * @dev Allows the seller to unblock a previously blocked bidder for an auction listing.
     *  Validates seller authorization.
     * @dev Modifier: whenNotPaused
     * @dev Throws: {Unauthorized}
     * @dev Emits: {BidderUnblocked}
     */
    function unblockBidder(uint256 listingId, address bidder)
        external
        whenNotPaused
    {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert Unauthorized();

        blockedBidders[listingId][bidder] = false;
        emit BidderUnblocked(listingId, bidder);
    }

    /**
     * @notice Confirms delivery of an order by a verifier.
     * @param orderId The ID of the order to confirm delivery for.
     * @dev Allows a verifier to confirm order delivery, releasing tokens to the buyer and funds to the seller.
     *  Validates verifier authorization and order state.
     *  Releases tokens to buyer, transfers funds to seller's owedFunds and updates order state to Delivered.
     * @dev Modifier: onlyVerifier, whenNotPaused
     * @dev Throws: {Unauthorized}, {InvalidState}
     * @dev Emits: {OrderStateChanged}
     */
    function confirmDelivery(uint256 orderId)
        external
        onlyVerifier
        whenNotPaused
    {
        Order storage order = orders[orderId];
        if (order.state != OrderState.Created) revert InvalidState();

        // Release tokens to buyer
        ICheBProofOfPurchase token = ICheBProofOfPurchase(
            factory.skuToToken(order.skuId)
        );
        token.releaseTokensToBuyer(order.seller, order.buyer, order.size, 1); // Using releaseTokensToBuyer

        // Track owed funds
        uint256 amount = orderEscrow[orderId];
        owedFunds[order.seller] += amount;
        delete orderEscrow[orderId];

        order.state = OrderState.Delivered;
        emit OrderStateChanged(orderId, OrderState.Delivered);
    }

    /**
     * @notice Cancels an order by a verifier.
     * @param orderId The ID of the order to cancel.
     * @dev Allows a verifier to cancel an order, returning inventory to seller and refunding the buyer.
     *  Validates verifier authorization and order state.
     *  Returns inventory to seller, refunds buyer by adding funds to buyer's owedFunds and updates order state to Cancelled.
     * @dev Modifier: onlyVerifier, whenNotPaused
     * @dev Throws: {Unauthorized}, {InvalidState}
     * @dev Emits: {OrderStateChanged}
     */
    function cancelOrder(uint256 orderId)
        external
        onlyVerifier
        whenNotPaused
    {
        Order storage order = orders[orderId];
        if (order.state != OrderState.Created) revert InvalidState();

        // Return inventory to seller
        ICheBProofOfPurchase token = ICheBProofOfPurchase(
            factory.skuToToken(order.skuId)
        );
        token.returnTokensToSeller(order.seller, order.buyer, order.size, 1); // Using returnTokensToSeller

        // Track refunds
        uint256 amount = orderEscrow[orderId];
        owedFunds[order.buyer] += amount;
        delete orderEscrow[orderId];

        order.state = OrderState.Cancelled;
        emit OrderStateChanged(orderId, OrderState.Cancelled);
    }

    /**
    * @notice Allows buyers to pay delivery fees for their orders.
    * @param orderId The ID of the order to pay fees for.
    * @param amount The fee amount in USDC.
    * @dev Allows buyers to pay delivery fees, accumulating them for admin withdrawal.
    *  Validates buyer authorization, order state and fee payment status.
    *  Transfers USDC from buyer to contract and updates orderFeesPaid and accumulatedFees.
    * @dev Modifier: nonReentrant, whenNotPaused
    * @dev Throws: {Unauthorized}, {InvalidState}, {DeliveryFeesAlreadyPaid}, {InsufficientBalance}, {InsufficientAllowance}
    * @dev Emits: {DeliveryFeePaid}
    */
    function payDeliveryFees(uint256 orderId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        Order storage order = orders[orderId];
        if (order.buyer != msg.sender) revert Unauthorized();
        if (order.state != OrderState.Created) revert InvalidState();
        if (orderFeesPaid[orderId]) revert DeliveryFeesAlreadyPaid();

        // Validate USDC balance and allowance
        if (usdc.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (usdc.allowance(msg.sender, address(this)) < amount) {
            revert InsufficientAllowance();
        }

        // Transfer USDC to contract
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Update state
        orderFeesPaid[orderId] = true;
        accumulatedFees += amount;

        emit DeliveryFeePaid(orderId, amount);
    }

    /**
    * @notice Allows DEFAULT_ADMIN_ROLE to withdraw accumulated delivery fees.
    * @dev Allows admin to withdraw accumulated delivery fees to their address.
    *  Validates admin authorization.
    *  Transfers accumulated delivery fees to admin address and resets accumulatedFees to 0.
    * @dev Modifier: nonReentrant, whenNotPaused
    * @dev Throws: {Unauthorized}, {NoFeesToWithdraw}
    * @dev Emits: {DeliveryFeesWithdrawn}
    */
    function withdrawDeliveryFees()
        external
        nonReentrant
        whenNotPaused
    {
        if (!chebControl.hasRole(chebControl.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }

        uint256 amount = accumulatedFees;
        if (amount == 0) revert NoFeesToWithdraw();

        // Reset accumulated fees before transfer
        accumulatedFees = 0;

        // Transfer USDC to admin
        usdc.safeTransfer(msg.sender, amount);
        emit DeliveryFeesWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Allows users to withdraw their owed funds (for sales or refunds).
     * @dev Allows sellers to withdraw funds after successful sales and buyers to withdraw refunds.
     *  Transfers owed funds to the caller's address and resets owedFunds balance for the caller.
     * @dev Modifier: nonReentrant, whenNotPaused
     * @dev Throws: {InsufficientBalance}
     * @dev Emits: {FundsWithdrawn}
     */
    function withdrawFunds() external nonReentrant whenNotPaused {
        uint256 amount = owedFunds[msg.sender];
        if (amount == 0) revert InsufficientBalance();

        owedFunds[msg.sender] = 0;
        usdc.safeTransfer(msg.sender, amount);
        emit FundsWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Pauses the contract, preventing most state-changing operations.
     * @dev Only verifiers can pause the contract.
     * @dev Modifier: onlyVerifier
     */
    function pause() external onlyVerifier {
        _pause();
    }

    /**
     * @notice Unpauses the contract, restoring normal operations.
     * @dev Only verifiers can unpause the contract.
     * @dev Modifier: onlyVerifier
     */
    function unpause() external onlyVerifier {
        _unpause();
    }
}