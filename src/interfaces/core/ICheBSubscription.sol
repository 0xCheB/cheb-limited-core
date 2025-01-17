// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICheBSubscription Interface
 * @notice Interface for the CheBSubscription contract
 * @dev Defines the external functions and events for subscription management
 */
interface ICheBSubscription {
    /* @notice Enum defining subscription tiers */
    enum SubscriptionTier {
        Basic,      // Free tier
        Plus,       // $10 USDC/month
        Premium     // $25 USDC/month
    }

    /* @notice Events */
    event TierPriceUpdated(SubscriptionTier indexed tier, uint256 oldPrice, uint256 newPrice);
    event SubscriptionPurchased(
        address indexed user, 
        SubscriptionTier tier, 
        uint256 expiresAt, 
        uint256 amount,
        bool isUpgrade
    );
    event SubscriptionCancelled(address indexed user);
    event PaymentRefunded(address indexed user, uint256 amount);

    /**
     * @notice Updates the price for a subscription tier
     * @param tier The tier to update
     * @param newPrice New price in USDC (6 decimals)
     */
    function updateTierPrice(SubscriptionTier tier, uint256 newPrice) external;

    /**
     * @notice Purchases or renews a subscription
     * @param tier The desired subscription tier
     * @param amount The amount of USDC to spend
     */
    function subscribe(SubscriptionTier tier, uint256 amount) external;

    /**
     * @notice Cancels an active subscription
     */
    function cancelSubscription() external;

    /**
     * @notice Gets the current subscription details for an address
     * @param user Address to check
     * @return tier Current subscription tier
     * @return expiresAt Subscription expiration timestamp
     * @return isActive Whether the subscription is currently active
     * @return currentPrice Current price being paid
     */
    function getSubscription(address user) 
        external 
        view 
        returns (
            SubscriptionTier tier,
            uint256 expiresAt,
            bool isActive,
            uint256 currentPrice
        );

    /**
     * @notice Allows executives to withdraw accumulated USDC
     * @param amount Amount of USDC to withdraw
     * @param recipient Address to receive the USDC
     */
    function withdrawUSDC(uint256 amount, address recipient) external;

    /**
     * @notice Emergency pause function
     */
    function pause() external;

    /**
     * @notice Resume contract operations
     */
    function unpause() external;

    /**
     * @notice Gets the price for a specific tier
     * @param tier The subscription tier to check
     * @return The price for the specified tier
     */
    function tierPrices(SubscriptionTier tier) external view returns (uint256);
}