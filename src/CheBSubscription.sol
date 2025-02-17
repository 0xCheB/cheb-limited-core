// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICheBControlCenter.sol";

/**
 * @title CheBSubscription
 * @author CheB Protocol
 * @notice Manages subscription tiers, pricing, and USDC payments for users of the CheB Protocol.
 * @dev This contract provides a flexible subscription system with different tiers, upgrade mechanisms, and executive-controlled pricing.
 * Users can subscribe to different tiers to access premium features within the CheB ecosystem, paying in USDC.
 * The contract integrates with the CheBControlCenter for access control and relies on USDC as the payment currency.
 */
contract CheBSubscription is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* @notice Reference to the CheBControlCenter contract for role-based access control. */
    ICheBControlCenter public immutable chebControl;

    /* @notice Reference to the USDC token contract used for subscription payments. */
    IERC20 public immutable usdc;

    /**
     * @notice Enum defining the available subscription tiers.
     * @dev Basic tier is free, while Plus and Premium tiers require USDC payments.
     */
    enum SubscriptionTier {
        Basic,      // Free tier providing basic access
        Plus,       // Paid tier offering enhanced features - priced at $10 USDC/month
        Premium     // Highest paid tier with full access and premium benefits - priced at $25 USDC/month
    }

    /**
     * @notice Struct to hold the details of a user's subscription.
     * @param tier The current subscription tier of the user.
     * @param expiresAt Timestamp representing the subscription expiry date.
     * @param lastPayment Timestamp of the last successful subscription payment.
     * @param priceAtSubscription Price of the subscription tier at the time of subscription, used for prorated upgrades.
     */
    struct Subscription {
        SubscriptionTier tier;
        uint256 expiresAt;
        uint256 lastPayment;
        uint256 priceAtSubscription;  // Price locked at subscription time
    }

    /**
     * @notice Mapping to store the USDC price for each subscription tier. Prices are in USDC with 6 decimals.
     * @dev Prices are configurable by executives and determine the cost of each subscription tier.
     */
    mapping(SubscriptionTier => uint256) public tierPrices;

    /**
     * @notice Mapping to store subscription details for each user address.
     * @dev Allows retrieval of subscription information for any user.
     */
    mapping(address => Subscription) public subscriptions;

    /* @notice Constant defining the duration of a subscription period in seconds (30 days). */
    uint256 private constant SUBSCRIPTION_PERIOD = 30 days;
    /* @notice Constant defining the number of decimals for USDC token, used for price calculations. */
    uint256 private constant PRICE_DECIMALS = 6; // USDC decimals - represents the decimals for USDC token

    // Events

    /**
     * @dev Emitted when the price of a subscription tier is updated.
     * @param tier The subscription tier whose price was updated.
     * @param oldPrice The previous price of the tier.
     * @param newPrice The new price of the tier.
     *
     * Emitted when an executive updates the price of a subscription tier.
     */
    event TierPriceUpdated(SubscriptionTier indexed tier, uint256 oldPrice, uint256 newPrice);

    /**
     * @dev Emitted when a user successfully purchases or renews a subscription.
     * @param user The address of the user who purchased the subscription.
     * @param tier The subscription tier purchased by the user.
     * @param expiresAt Timestamp representing the new subscription expiry date.
     * @param pricePaid The amount of USDC paid for the subscription.
     * @param isUpgrade Boolean indicating if the purchase was an upgrade from a lower tier.
     *
     * Emitted upon successful subscription purchase, renewal, or upgrade.
     */
    event SubscriptionPurchased(
        address indexed user,
        SubscriptionTier tier,
        uint256 expiresAt,
        uint256 pricePaid, // Renamed from amount to pricePaid for clarity
        bool isUpgrade
    );

    /**
     * @dev Emitted when a user cancels their active subscription.
     * @param user The address of the user who cancelled their subscription.
     *
     * Emitted when a user cancels their paid subscription, reverting to the Basic tier.
     */
    event SubscriptionCancelled(address indexed user);

    /**
     * @dev Emitted when a user receives a refund for overpayment during subscription purchase.
     * @param user The address of the user who received the refund.
     * @param amount The amount of USDC refunded to the user.
     *
     * Emitted when excess USDC is refunded to the user after a subscription purchase.
     */
    event PaymentRefunded(address indexed user, uint256 amount);

    // Custom errors

    /**
     * @dev Custom error thrown when an invalid subscription tier is specified.
     * For example, when trying to update price for Basic tier or subscribing to an undefined tier.
     */
    error InvalidTier();

    /**
     * @dev Custom error thrown when the USDC allowance is insufficient for subscription payment.
     * Indicates that the contract is not approved to spend the required USDC amount from the user's wallet.
     */
    error InsufficientAllowance();

    /**
     * @dev Custom error thrown when the user's USDC balance is less than the subscription price.
     * Indicates that the user does not have enough USDC to purchase the selected subscription tier.
     */
    error InsufficientBalance();

    /**
     * @dev Custom error thrown when an invalid price is provided, such as setting a zero price for paid tiers.
     * Used when updating tier prices and ensuring paid tiers have a valid price.
     */
    error InvalidPrice();

    /**
     * @dev Custom error thrown when an action is attempted by an address without executive role.
     * Restricts executive-only functions to authorized addresses defined in CheBControlCenter.
     */
    error Unauthorized();

    /**
     * @dev Custom error thrown when attempting to cancel a subscription but the user has no active paid subscription.
     * Prevents cancellation requests from users who are already on the Basic tier or have no subscription.
     */
    error NoActiveSubscription();

    /**
     * @dev Custom error thrown if USDC refund fails during subscription purchase.
     * Indicates an issue with transferring refund amount back to the user.
     */
    error RefundFailed();

    /**
     * @dev Custom error thrown when a user attempts to downgrade from a higher tier to a lower tier while subscription is active.
     * Downgrading is not allowed during an active subscription period; cancellation is required first.
     */
    error CannotDowngrade();

    /**
     * @dev Custom error thrown when a user attempts to subscribe to the same tier they are already subscribed to.
     * Prevents redundant subscription actions to the same tier.
     */
    error SameTier();

    /**
     * @dev Custom error thrown when an invalid recipient address (zero address) is provided for USDC withdrawal.
     * Ensures that USDC withdrawals are made to valid, non-zero addresses.
     */
    error InvalidRecipientAddress(); // New error for invalid recipient address

    /**
     * @notice Constructor for the CheBSubscription contract.
     * @param _chebControl Address of the deployed CheBControlCenter contract.
     * @param _usdc Address of the deployed USDC token contract.
     *
     * @dev Initializes the contract with references to CheBControlCenter and USDC contracts.
     * Sets initial prices for Plus and Premium tiers and Basic tier price to zero.
     */
    constructor(
        address _chebControl,
        address _usdc
    ) {
        chebControl = ICheBControlCenter(_chebControl);
        usdc = IERC20(_usdc);

        // Initialize tier prices (Basic = 0, Plus = 10 USDC, Premium = 25 USDC)
        tierPrices[SubscriptionTier.Basic] = 0;
        tierPrices[SubscriptionTier.Plus] = 10 * 10**PRICE_DECIMALS;    // 10 USDC
        tierPrices[SubscriptionTier.Premium] = 25 * 10**PRICE_DECIMALS; // 25 USDC
    }

    /**
     * @notice Modifier to restrict function calls to only accounts with the EXECUTIVE_ROLE.
     * @dev Checks if the caller has the EXECUTIVE_ROLE in the CheBControlCenter contract.
     *
     * @custom:security Ensures that only authorized executives can perform certain administrative functions.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    modifier onlyExecutive() {
        if (!chebControl.hasRole(chebControl.EXECUTIVE_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Updates the price for a specific subscription tier.
     * @dev Allows executives to adjust the pricing of Plus and Premium subscription tiers.
     * Basic tier price is fixed at 0 and cannot be updated.
     *
     * @param tier The SubscriptionTier enum value representing the tier to update (Plus or Premium).
     * @param newPrice New price for the tier in USDC (with 6 decimals). Must be greater than 0 for paid tiers.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     * @custom:event Emits {TierPriceUpdated} event upon successful price update.
     *
     *  InvalidTier Thrown if attempting to update the price of the Basic tier.
     *  InvalidPrice Thrown if `newPrice` is zero for paid tiers.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function updateTierPrice(SubscriptionTier tier, uint256 newPrice)
        external
        onlyExecutive
        whenNotPaused
    {
        if (tier == SubscriptionTier.Basic) revert InvalidTier();
        if (newPrice == 0) revert InvalidPrice();

        uint256 oldPrice = tierPrices[tier];
        tierPrices[tier] = newPrice;

        emit TierPriceUpdated(tier, oldPrice, newPrice);
    }

    /**
     * @notice Purchases or renews a subscription to a specified tier.
     * @dev Handles new subscriptions, renewals, and upgrades to different subscription tiers.
     * For upgrades, calculates prorated price difference based on remaining subscription time.
     * For Basic tier, it grants free subscription. For paid tiers, requires USDC payment.
     *
     * @param tier The SubscriptionTier enum value representing the desired subscription tier.
     * @param amount The amount of USDC provided by the user for subscription.
     *               Should be equal to or greater than the price of the tier. Excess amount is refunded.
     *
     * @custom:security Prevents reentrancy attacks.
     * @custom:access Callable by any user.
     * @custom:event Emits {SubscriptionPurchased} event upon successful subscription.
     * @custom:event Emits {PaymentRefunded} event if excess USDC is refunded.
     *
     *  InvalidTier Thrown if an invalid subscription tier is specified.
     *  InsufficientAllowance Thrown if USDC allowance is insufficient.
     *  InsufficientBalance Thrown if user's USDC balance is less than the tier price.
     *  CannotDowngrade Thrown if attempting to downgrade to a lower tier while subscription is active.
     *  SameTier Thrown if attempting to subscribe to the same tier already subscribed to.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     */
    function subscribe(SubscriptionTier tier, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        if (uint(tier) > uint(SubscriptionTier.Premium)) revert InvalidTier();

        Subscription storage sub = subscriptions[msg.sender];
        bool isUpgrade = false;
        uint256 price = tierPrices[tier];

        // Handle Basic tier separately
        if (tier == SubscriptionTier.Basic) {
            _handleBasicSubscription(sub);
            return;
        }

        // Validate amount and allowance
        if (amount < price) revert InsufficientBalance();
        if (usdc.allowance(msg.sender, address(this)) < amount) {
            revert InsufficientAllowance();
        }

        // Handle existing subscription
        if (sub.expiresAt > block.timestamp) {
            if (tier < sub.tier) revert CannotDowngrade();
            if (tier == sub.tier) revert SameTier();

            isUpgrade = true;
            price = _calculateUpgradePrice(sub, tier);
        }

        // Calculate new expiration
        uint256 newExpiration = _calculateNewExpiration(sub, isUpgrade);

        // Transfer USDC from user
        if (price > 0) {
            usdc.safeTransferFrom(msg.sender, address(this), price);
        }

        // Update subscription
        sub.tier = tier;
        sub.expiresAt = newExpiration;
        sub.lastPayment = block.timestamp;
        sub.priceAtSubscription = tierPrices[tier];

        emit SubscriptionPurchased(msg.sender, tier, newExpiration, price, isUpgrade); // Using 'price' here

        // Refund excess USDC if any
        uint256 excess = amount - price;
        if (excess > 0) {
            usdc.safeTransfer(msg.sender, excess);
            emit PaymentRefunded(msg.sender, excess);
        }
    }

    /**
     * @notice Handles the subscription process for the Basic tier.
     * @dev Sets the user's subscription to Basic tier with a 30-day validity period from the current timestamp.
     * Basic tier is free and does not require USDC payment.
     *
     * @param sub Storage reference to the user's Subscription struct.
     * @dev Internal function called by `subscribe` function when Basic tier is selected.
     */
    function _handleBasicSubscription(Subscription storage sub) private {
        if (sub.tier > SubscriptionTier.Basic && sub.expiresAt > block.timestamp) {
            revert CannotDowngrade();
        }

        sub.tier = SubscriptionTier.Basic;
        sub.expiresAt = block.timestamp + SUBSCRIPTION_PERIOD;
        sub.lastPayment = block.timestamp;
        sub.priceAtSubscription = 0;

        emit SubscriptionPurchased(
            msg.sender,
            SubscriptionTier.Basic,
            sub.expiresAt,
            0,
            false
        );
    }

    /**
     * @notice Calculates the prorated price for upgrading a subscription to a higher tier.
     * @dev Calculates the price difference for the remaining subscription period when upgrading tiers.
     *
     * @param sub Memory copy of the current user's Subscription struct.
     * @param newTier The desired SubscriptionTier to upgrade to.
     * @return Price for the upgrade in USDC (with 6 decimals).
     *
     * @dev Internal function called by `subscribe` function during tier upgrades.
     */
    function _calculateUpgradePrice(
        Subscription memory sub,
        SubscriptionTier newTier
    ) private view returns (uint256) {
        uint256 remainingTime = sub.expiresAt - block.timestamp;
        uint256 currentMonthlyPrice = sub.priceAtSubscription;
        uint256 newMonthlyPrice = tierPrices[newTier];

        // Calculate prorated difference between new and current tier prices
        uint256 priceDifference = newMonthlyPrice > currentMonthlyPrice ?
            newMonthlyPrice - currentMonthlyPrice : 0;

        return (priceDifference * remainingTime) / SUBSCRIPTION_PERIOD;
    }

    /**
     * @notice Calculates the new subscription expiration timestamp.
     * @dev Determines the new expiration date based on whether it's a new subscription, renewal, or upgrade.
     * For renewals, extends the existing expiration. For new subscriptions, sets expiration 30 days from purchase.
     *
     * @param sub Memory copy of the current user's Subscription struct.
     * @param isUpgrade Boolean indicating if it's a tier upgrade.
     * @return New expiration timestamp as a Unix timestamp.
     *
     * @dev Internal function called by `subscribe` function to determine subscription expiry.
     */
    function _calculateNewExpiration(
        Subscription memory sub,
        bool isUpgrade
    ) private view returns (uint256) {
        if (isUpgrade) {
            return sub.expiresAt;
        }
        return block.timestamp > sub.expiresAt ?
            block.timestamp + SUBSCRIPTION_PERIOD :
            sub.expiresAt + SUBSCRIPTION_PERIOD;
    }

    /**
     * @notice Cancels an active paid subscription, reverting the user to the Basic tier.
     * @dev Cancels the current Plus or Premium subscription and sets the user's tier to Basic.
     * Subscription expires immediately upon cancellation.
     *
     * @custom:security Prevents reentrancy attacks.
     * @custom:access Callable by any user with an active paid subscription.
     * @custom:event Emits {SubscriptionCancelled} event upon successful cancellation.
     *
     *  NoActiveSubscription Thrown if the user has no active paid subscription to cancel.
     *  Pausable: paused Thrown if the contract is paused.
     *  ReentrancyGuard: reentrant call Thrown if reentrancy is detected.
     */
    function cancelSubscription() external whenNotPaused nonReentrant {
        Subscription storage sub = subscriptions[msg.sender];
        if (sub.tier == SubscriptionTier.Basic) revert NoActiveSubscription();

        sub.tier = SubscriptionTier.Basic;
        sub.expiresAt = block.timestamp;
        sub.priceAtSubscription = 0;

        emit SubscriptionCancelled(msg.sender);
    }

    /**
     * @notice Gets the current subscription details for a given user address.
     * @dev Allows anyone to query the subscription status, tier, expiry, and current price for any user.
     *
     * @param user Address of the user to query subscription details for.
     * @return tier The current SubscriptionTier of the user.
     * @return expiresAt Subscription expiration timestamp as a Unix timestamp.
     * @return isActive Boolean indicating whether the subscription is currently active (not expired).
     * @return currentPrice The price of the user's current subscription tier at the time of subscription.
     *
     * @custom:access Callable by anyone.
     */
    function getSubscription(address user)
        external
        view
        returns (
            SubscriptionTier tier,
            uint256 expiresAt,
            bool isActive,
            uint256 currentPrice
        )
    {
        Subscription memory sub = subscriptions[user];
        return (
            sub.tier,
            sub.expiresAt,
            sub.expiresAt > block.timestamp,
            sub.priceAtSubscription
        );
    }

    /**
     * @notice Allows executives to withdraw accumulated USDC from the contract.
     * @dev Transfers a specified amount of USDC from the contract balance to a recipient address.
     *
     * @param amount Amount of USDC to withdraw.
     * @param recipient Address to receive the withdrawn USDC. Must not be zero address.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     *
     *  InvalidRecipientAddress Thrown if `recipient` address is the zero address.
     *  Pausable: paused Thrown if the contract is paused.
     *  Unauthorized Thrown if the caller does not have the EXECUTIVE_ROLE.
     */
    function withdrawUSDC(uint256 amount, address recipient)
        external
        onlyExecutive
        whenNotPaused
    {
        if (recipient == address(0)) revert InvalidRecipientAddress(); // Using InvalidRecipientAddress error
        usdc.safeTransfer(recipient, amount);
    }

    /**
     * @notice Pauses the contract, halting critical operations.
     * @dev Enables emergency pause mechanism to stop subscription purchases and price updates.
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
     * @dev Reverts the contract to normal operation, allowing subscription purchases and price updates.
     * Only callable by accounts with EXECUTIVE_ROLE.
     *
     * @custom:security Only callable by accounts with `EXECUTIVE_ROLE`.
     * @custom:access Requires `onlyExecutive` modifier.
     */
    function unpause() external onlyExecutive {
        _unpause();
    }
}