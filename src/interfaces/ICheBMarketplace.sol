// ICheBMarketplace.sol (Interface)
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ICheBProofOfPurchaseFactory.sol";
import "./ICheBSubscription.sol";
import "./ICheBControlCenter.sol";

/**
 * @title ICheBMarketplace
 * @author CheB Protocol
 * @notice Interface for the CheBMarketplace contract, defining the API for a decentralized marketplace for Proof of Purchase tokens.
 * @dev This interface outlines the external functions and data structures of the CheBMarketplace contract.
 * It provides functionalities for creating listings, placing orders, handling bids, managing order states, and processing payments using USDC.
 * Contracts interacting with the CheBMarketplace should use this interface to ensure proper function calls and data handling for marketplace operations.
 */
interface ICheBMarketplace {
    /**
     * @notice Enum defining the possible states of an order within the marketplace.
     * @dev Represents the lifecycle stages of an order, from creation to completion or cancellation.
     * - `Created`: Order has been initiated but not yet processed by the seller.
     * - `Accepted`: Seller has accepted the order and is preparing for delivery.
     * - `Delivered`: Order has been marked as delivered by the seller and awaiting buyer confirmation.
     * - `Cancelled`: Order has been cancelled by either the buyer or seller under specific conditions.
     */
    enum OrderState { Created, Accepted, Delivered, Cancelled }

    /**
     * @notice Enum defining the types of listings available on the marketplace.
     * @dev Categorizes listings based on their selling mechanism.
     * - `DirectSale`: Listings for immediate purchase at a fixed price.
     * - `Auction`: Listings where buyers can place bids, and the seller can accept a bid to finalize the sale.
     */
    enum ListingType { DirectSale, Auction }

    /**
     * @notice Struct representing a listing on the marketplace.
     * @param skuId Identifier for the SKU of the listed Proof of Purchase token.
     * @param size Size variant of the Proof of Purchase token being listed.
     * @param price Fixed price for DirectSale listings, or initial price for Auctions.
     * @param seller Address of the seller who created the listing.
     * @param timestamp Timestamp when the listing was created.
     * @param active Boolean indicating if the listing is currently active and available for purchase or bidding.
     * @param listingType Enum specifying whether the listing is a DirectSale or an Auction.
     * @param minBidPrice For Auction listings, the minimum bid price required to participate.
     */
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

    /**
     * @notice Struct representing an order placed on the marketplace.
     * @param buyer Address of the buyer who placed the order.
     * @param seller Address of the seller who owns the listing for the order.
     * @param skuId Identifier for the SKU of the Proof of Purchase token in the order.
     * @param size Size variant of the Proof of Purchase token in the order.
     * @param price Agreed price for the order.
     * @param state Current OrderState enum value representing the order's status.
     * @param timestamp Timestamp when the order was created.
     */
    struct Order {
        address buyer;
        address seller;
        uint256 skuId;
        uint256 size;
        uint256 price;
        OrderState state;
        uint256 timestamp;
    }

    /**
     * @notice Struct representing a bid placed on an Auction listing.
     * @param bidder Address of the bidder who placed the bid.
     * @param listingId Identifier of the listing on which the bid is placed.
     * @param amount Bid amount in USDC.
     * @param timestamp Timestamp when the bid was placed.
     * @param active Boolean indicating if the bid is currently active (not rejected or superseded).
     */
    struct Bid {
        address bidder;
        uint256 listingId;
        uint256 amount;
        uint256 timestamp;
        bool active;
    }

    /**
     * @dev Custom error thrown when an action is attempted by an unauthorized account.
     * @dev Implementations should revert with this error to restrict access to functions that require specific roles or permissions.
     */
    error Unauthorized();

    /**
     * @dev Custom error thrown when an operation is attempted on an invalid or non-existent listing.
     * @dev Implementations should revert with this error if a listing ID is provided that does not correspond to an active listing in the marketplace.
     */
    error InvalidListing();

    /**
     * @dev Custom error thrown when an operation is attempted on an invalid or non-existent order.
     * @dev Implementations should revert with this error if an order ID is provided that does not correspond to a valid order in the marketplace.
     */
    error InvalidOrder();

    /**
     * @dev Custom error thrown when an operation is attempted on an invalid or non-existent bid.
     * @dev Implementations should revert with this error if a bid ID is provided that does not correspond to an active bid in the marketplace.
     */
    error InvalidBid();

    /**
     * @dev Custom error thrown when a buyer attempts a purchase or bid with insufficient USDC balance.
     * @dev Implementations should revert with this error if a user's USDC balance is less than the required amount for a purchase or bid.
     */
    error InsufficientBalance();

    /**
     * @dev Custom error thrown when a buyer has not granted sufficient USDC allowance to the marketplace contract for a transaction.
     * @dev Implementations should revert with this error if the marketplace contract cannot transfer USDC from the buyer due to insufficient allowance.
     */
    error InsufficientAllowance();

    /**
     * @dev Custom error thrown when an invalid price is provided, such as setting a zero or negative price for a listing or bid.
     * @dev Implementations should revert with this error if a price is not valid for the context, ensuring all prices are positive and reasonable.
     */
    error InvalidPrice();

    /**
     * @dev Custom error thrown when an operation is attempted in an invalid order state, e.g., trying to accept an already delivered order.
     * @dev Implementations should revert with this error if an action is not permitted in the current state of an order, enforcing state-based workflows.
     */
    error InvalidState();

    /**
     * @dev Custom error thrown when a bidder is blocked from participating in bidding on a specific listing.
     * @dev Implementations should revert with this error if a user attempts to bid on a listing from which they have been blocked by the seller.
     */
    error BidderIsBlocked();

    /**
     * @dev Custom error thrown when a user attempts to purchase or access an SKU that requires a subscription.
     * @dev Implementations should revert with this error if a user tries to interact with an SKU that is restricted to subscribed users, and the user does not have an active subscription of any tier.
     */
    error SubscriptionRequiredForSKU();

    /**
     * @dev Custom error thrown when a user's subscription tier is not sufficient to access or purchase a specific SKU.
     * @dev Implementations should revert with this error if a user's subscription tier is below the minimum required tier to access or purchase a particular SKU.
     */
    error InsufficientSubscriptionTierForSKU();

    /**
     * @dev Custom error thrown when delivery fees have already been paid for an order.
     * @dev Implementations should revert with this error to prevent double payment of delivery fees for the same order.
     */
    error DeliveryFeesAlreadyPaid();

    /**
     * @dev Custom error thrown when attempting to withdraw delivery fees, but there are no fees accumulated in the contract.
     * @dev Implementations should revert with this error if a withdrawal of delivery fees is requested when the contract's accumulated fees balance is zero.
     */
    error NoFeesToWithdraw();

    /**
     * @notice Returns the address of the CheBControlCenter contract for access control.
     * @return ICheBControlCenter The contract address of the CheBControlCenter.
     *
     * @dev Implementations should provide a view function to retrieve the address of the linked CheBControlCenter contract, used for role-based access control.
     */
    function chebControl() external view returns (ICheBControlCenter);

    /**
     * @notice Returns the address of the CheBProofOfPurchaseFactory contract, used for interacting with Proof of Purchase tokens.
     * @return ICheBProofOfPurchaseFactory The contract address of the Proof of Purchase Factory.
     *
     * @dev Implementations should provide a view function to retrieve the address of the linked Proof of Purchase Factory contract, which manages the creation and deployment of PoP tokens.
     */
    function factory() external view returns (ICheBProofOfPurchaseFactory);

    /**
     * @notice Returns the address of the CheBSubscription contract, used for subscription verification.
     * @return ICheBSubscription The contract address of the CheBSubscription contract.
     *
     * @dev Implementations should provide a view function to retrieve the address of the linked CheBSubscription contract, used to verify user subscription status for SKU access.
     */
    function subscription() external view returns (ICheBSubscription);

    /**
     * @notice Returns the address of the USDC token contract, the currency used for transactions in the marketplace.
     * @return IERC20 The contract address of the USDC token (ERC20).
     *
     * @dev Implementations should provide a view function to retrieve the address of the USDC token contract, which is the payment currency for listings, orders, and bids.
     */
    function usdc() external view returns (IERC20);

    /**
     * @notice Returns a counter for listing IDs, providing the total number of listings created.
     * @return listingIds A Counters.Counter memory object for listing IDs.
     *
     * @dev Implementations should provide a view function to access the listing ID counter, which tracks the number of listings created in the marketplace.
     */
    function listingIds() external view returns (Counters.Counter memory);

    /**
     * @notice Returns a counter for order IDs, providing the total number of orders placed.
     * @return orderIds A Counters.Counter memory object for order IDs.
     *
     * @dev Implementations should provide a view function to access the order ID counter, which tracks the number of orders placed in the marketplace.
     */
    function orderIds() external view returns (Counters.Counter memory);

    /**
     * @notice Returns a counter for bid IDs, providing the total number of bids placed.
     * @return bidIds A Counters.Counter memory object for bid IDs.
     *
     * @dev Implementations should provide a view function to access the bid ID counter, which tracks the number of bids placed in the marketplace.
     */
    function bidIds() external view returns (Counters.Counter memory);

    /**
     * @notice Returns the amount of funds owed to a seller, which are ready to be withdrawn.
     * @param seller The address of the seller to query owed funds for.
     * @return uint256 The amount of funds owed to the seller in USDC.
     *
     * @dev Implementations should provide a view function to get the balance of funds owed to a seller from completed sales, which are available for withdrawal.
     */
    function owedFunds(address seller) external view returns (uint256);

    /**
     * @notice Returns the amount of inventory locked in the contract for a specific listing, typically for active orders.
     * @param listingId The identifier of the listing to query locked inventory for.
     * @return uint256 The amount of inventory locked for the listing.
     *
     * @dev Implementations should provide a view function to check the quantity of Proof of Purchase tokens that are currently locked or reserved for a specific listing, usually due to pending orders.
     */
    function lockedInventory(uint256 listingId) external view returns (uint256);

    /**
     * @notice Checks if delivery fees have been paid for a specific order.
     * @param orderId The identifier of the order to check delivery fee payment status for.
     * @return bool True if delivery fees have been paid for the order, false otherwise.
     *
     * @dev Implementations should provide a view function to determine if delivery fees have already been paid for a given order, to prevent duplicate payments.
     */
    function orderFeesPaid(uint256 orderId) external view returns (bool);

    /**
     * @notice Returns the total amount of delivery fees accumulated in the marketplace contract.
     * @return uint256 The total accumulated delivery fees in USDC.
     *
     * @dev Implementations should provide a view function to get the total sum of delivery fees that have been paid by buyers and are held by the marketplace contract, ready to be withdrawn by the marketplace owner or operator.
     */
    function accumulatedFees() external view returns (uint256);

    /**
     * @notice Returns the details of a specific listing.
     * @param listingId The identifier of the listing to retrieve details for.
     * @return listings A Listing memory struct containing the details of the listing.
     *
     * @dev Implementations should provide a view function to retrieve all relevant information about a listing, such as SKU ID, size, price, seller, timestamps, and listing type.
     */
    function listings(uint256 listingId) external view returns (Listing memory);

    /**
     * @notice Returns the details of a specific order.
     * @param orderId The identifier of the order to retrieve details for.
     * @return orders An Order memory struct containing the details of the order.
     *
     * @dev Implementations should provide a view function to retrieve all relevant information about an order, such as buyer, seller, SKU ID, size, price, order state, and timestamps.
     */
    function orders(uint256 orderId) external view returns (Order memory);

    /**
     * @notice Returns the details of a specific bid.
     * @param bidId The identifier of the bid to retrieve details for.
     * @return bids A Bid memory struct containing the details of the bid.
     *
     * @dev Implementations should provide a view function to retrieve all relevant information about a bid, such as bidder, listing ID, bid amount, timestamp, and bid status.
     */
    function bids(uint256 bidId) external view returns (Bid memory);

    /**
     * @notice Returns the amount of USDC escrowed for a specific order.
     * @param orderId The identifier of the order to query escrow for.
     * @return uint256 The amount of USDC in escrow for the order.
     */
    function orderEscrow(uint256 orderId) external view returns (uint256);

    /**
     * @notice Checks if a bidder is blocked from bidding on a specific listing.
     * @param listingId The identifier of the listing to check bidder block status for.
     * @param bidder The address of the bidder to check.
     * @return bool True if the bidder is blocked for the listing, false otherwise.
     */
    function blockedBidders(uint256 listingId, address bidder) external view returns (bool);

    /**
     * @notice Creates a new listing on the marketplace.
     * @param skuId Identifier for the SKU of the Proof of Purchase token to be listed.
     * @param size Size variant of the Proof of Purchase token to be listed.
     * @param price Price for the listing in USDC.
     * @param listingType Type of listing (DirectSale or Auction).
     * @param minBidPrice For Auction listings, the minimum bid price. Set to 0 for DirectSale.
     * @return uint256 The ID of the newly created listing.
     *
     * @dev Implementations should provide a function for sellers to create new listings for their Proof of Purchase tokens. This function should handle both DirectSale and Auction listing types.
     *
     */
    function createListing(
        uint256 skuId,
        uint256 size,
        uint256 price,
        ListingType listingType,
        uint256 minBidPrice
    ) external returns (uint256);

    /**
     * @notice Updates the price of an existing listing.
     * @param listingId The identifier of the listing to update.
     * @param newPrice The new price for the listing in USDC.
     *
     * @dev Implementations should provide a function for sellers to update the price of their active listings.
     */
    function updateListing(uint256 listingId, uint256 newPrice) external;

    /**
     * @notice Cancels an active listing, removing it from the marketplace.
     * @param listingId The identifier of the listing to cancel.
     *
     * @dev Implementations should provide a function for sellers to cancel their active listings, making them unavailable for purchase or bidding.
     *
     */
    function cancelListing(uint256 listingId) external;

    /**
     * @notice Initiates a purchase of a DirectSale listing.
     * @param listingId The identifier of the DirectSale listing to purchase.
     *
     * @dev Implementations should provide a function for buyers to purchase DirectSale listings. This function should handle USDC payment, token transfer, and order creation.
     *
     */
    function purchase(uint256 listingId) external;

    /**
     * @notice Places a bid on an Auction listing.
     * @param listingId The identifier of the Auction listing to bid on.
     * @param amount The bid amount in USDC.
     *
     * @dev Implementations should provide a function for buyers to place bids on Auction listings. This function should handle USDC escrow and bid tracking.
     *
     */
    function placeBid(uint256 listingId, uint256 amount) external;

    /**
     * @notice Accepts a specific bid on an Auction listing, finalizing the sale to the bidder.
     * @param bidId The identifier of the bid to accept.
     *
     * @dev Implementations should provide a function for sellers to accept bids on their Auction listings. This function should handle USDC transfer, token transfer, order state update, and bid invalidation.
     */
    function acceptBid(uint256 bidId) external;

    /**
     * @notice Rejects a specific bid on an Auction listing, making it inactive.
     * @param bidId The identifier of the bid to reject.
     *
     * @dev Implementations should provide a function for sellers to reject bids on their Auction listings. This function should invalidate the bid and return the bid amount to the bidder.
     *
     */
    function rejectBid(uint256 bidId) external;

    /**
     * @notice Blocks a bidder from placing further bids on a specific listing.
     * @param listingId The identifier of the listing to block the bidder from.
     * @param bidder The address of the bidder to block.
     *
     * @dev Implementations should provide a function for sellers to block specific bidders from participating in bidding on their listings.
     */
    function blockBidder(uint256 listingId, address bidder) external;

    /**
     * @notice Unblocks a previously blocked bidder, allowing them to bid on a specific listing again.
     * @param listingId The identifier of the listing to unblock the bidder for.
     * @param bidder The address of the bidder to unblock.
     *
     * @dev Implementations should provide a function for sellers to unblock bidders, reversing a previous block and allowing them to bid again.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not the seller of the listing.
     *  InvalidListing Implementations should revert with this error if `listingId` does not correspond to an active listing.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function unblockBidder(uint256 listingId, address bidder) external;

    /**
     * @notice Confirms delivery of an order by the buyer, completing the order process.
     * @param orderId The identifier of the order to confirm delivery for.
     *
     * @dev Implementations should provide a function for buyers to confirm delivery of their orders. This function should update the order state to Delivered and release funds to the seller.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not the buyer of the order.
     *  InvalidOrder Implementations should revert with this error if `orderId` does not correspond to a valid order.
     *  InvalidState Implementations should revert with this error if the order is not in a state that allows delivery confirmation (e.g., already delivered or cancelled).
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function confirmDelivery(uint256 orderId) external;

    /**
     * @notice Cancels an order before delivery confirmation, reverting the transaction.
     * @param orderId The identifier of the order to cancel.
     *
     * @dev Implementations should provide a function for buyers or sellers to cancel orders under certain conditions before delivery confirmation. This function should update the order state to Cancelled and return funds to the buyer and tokens to the seller.
     *
     *  Unauthorized Implementations should revert with this error if the caller is neither the buyer nor the seller of the order (or authorized marketplace admin).
     *  InvalidOrder Implementations should revert with this error if `orderId` does not correspond to a valid order.
     *  InvalidState Implementations should revert with this error if the order is already delivered or cancelled.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function cancelOrder(uint256 orderId) external;

    /**
     * @notice Pays delivery fees for an order.
     * @param orderId The identifier of the order to pay delivery fees for.
     * @param amount The amount of USDC to pay as delivery fees.
     *
     * @dev Implementations should provide a function for buyers to pay delivery fees associated with their orders. This function should transfer USDC from the buyer to the marketplace contract as delivery fees.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not the buyer of the order.
     *  InvalidOrder Implementations should revert with this error if `orderId` does not correspond to a valid order.
     *  InvalidState Implementations should revert with this error if the order is already delivered or cancelled, or if delivery fees are already paid.
     *  InsufficientBalance Implementations should revert with this error if the buyer does not have sufficient USDC balance.
     *  InsufficientAllowance Implementations should revert with this error if the buyer has not granted sufficient USDC allowance to the marketplace.
     *  DeliveryFeesAlreadyPaid Implementations should revert with this error if delivery fees have already been paid for this order.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function payDeliveryFees(uint256 orderId, uint256 amount) external;

    /**
     * @notice Allows the marketplace operator to withdraw accumulated delivery fees from the contract.
     *
     * @dev Implementations should provide a function for authorized marketplace operators to withdraw the delivery fees that have been paid by buyers and accumulated in the contract.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an authorized marketplace operator (e.g., executive role).
     *  NoFeesToWithdraw Implementations should revert with this error if there are no accumulated delivery fees to withdraw.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function withdrawDeliveryFees() external;

    /**
     * @notice Allows sellers to withdraw funds from completed sales that are owed to them.
     *
     * @dev Implementations should provide a function for sellers to withdraw the USDC funds they have earned from completed sales, which are stored as owed funds in the contract.
     *
     *  NoFeesToWithdraw Implementations should revert with this error if the seller has no funds to withdraw.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function withdrawFunds() external;

    /**
     * @notice Pauses the marketplace contract, halting critical operations.
     *
     * @dev Implementations should provide a function for authorized roles (e.g., executive role) to pause the marketplace contract in case of emergencies or for maintenance.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not authorized to pause the contract.
     */
    function pause() external;

    /**
     * @notice Resumes marketplace contract operations after being paused, allowing normal marketplace activities to proceed.
     *
     * @dev Implementations should provide a function for authorized roles (e.g., executive role) to unpause the marketplace contract, restoring normal operations.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not authorized to unpause the contract.
     */
    function unpause() external;

    /**
     * @notice Checks if the marketplace contract is currently paused.
     * @return bool True if the contract is paused, false otherwise.
     *
     * @dev Implementations should provide a view function to check the current pause state of the marketplace contract, allowing external contracts and users to determine if marketplace operations are currently active.
     */
    function paused() external view returns (bool);
}