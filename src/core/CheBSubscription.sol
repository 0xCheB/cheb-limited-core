// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/accesscontrol/ICheBControlCenter.sol";

/**
 * @title CheBSubscription Contract
 * @notice Manages subscription tiers and USDC payments for the CheB Protocol
 * @dev Implements subscription logic with executive-controlled pricing and tier upgrades
 */
contract CheBSubscription is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* @notice Reference to the CheBControlCenter contract for access control */
    ICheBControlCenter public immutable chebControl;

    /* @notice Reference to the USDC token contract */
    IERC20 public immutable usdc;

    /* @notice Enum defining subscription tiers */
    enum SubscriptionTier {
        Basic,      // Free tier
        Plus,       // $10 USDC/month
        Premium     // $25 USDC/month
    }

    /* @notice Struct defining subscription details */
    struct Subscription {
        SubscriptionTier tier;
        uint256 expiresAt;
        uint256 lastPayment;
        uint256 priceAtSubscription;  // Price locked at subscription time
    }

    /* @notice Mapping of subscription prices in USDC (6 decimals) */
    mapping(SubscriptionTier => uint256) public tierPrices;
    
    /* @notice Mapping of user subscriptions */
    mapping(address => Subscription) public subscriptions;

    /* @notice Constants */
    uint256 private constant SUBSCRIPTION_PERIOD = 30 days;
    uint256 private constant PRICE_DECIMALS = 6; // USDC decimals

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

    /* @notice Custom errors */
    error InvalidTier();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidPrice();
    error Unauthorized();
    error NoActiveSubscription();
    error RefundFailed();
    error CannotDowngrade();
    error SameTier();

    /**
     * @notice Contract constructor
     * @param _chebControl Address of the CheBControlCenter contract
     * @param _usdc Address of the USDC token contract
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
     * @notice Modifier to check for executive role
     */
    modifier onlyExecutive() {
        if (!chebControl.hasRole(chebControl.EXECUTIVE_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Updates the price for a subscription tier
     * @dev Can only be called by executives
     * @param tier The tier to update
     * @param newPrice New price in USDC (6 decimals)
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
     * @notice Purchases or renews a subscription
     * @dev Handles new subscriptions, renewals, and upgrades
     * @param tier The desired subscription tier
     * @param amount The amount of USDC to spend
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

        emit SubscriptionPurchased(msg.sender, tier, newExpiration, price, isUpgrade);

        // Refund excess USDC if any
        uint256 excess = amount - price;
        if (excess > 0) {
            usdc.safeTransfer(msg.sender, excess);
            emit PaymentRefunded(msg.sender, excess);
        }
    }

    /**
     * @notice Handles subscription to Basic tier
     * @param sub The subscription storage reference
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
     * @notice Calculates the price for upgrading a subscription
     * @param sub Current subscription
     * @param newTier Desired tier
     * @return Price for the upgrade
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
     * @notice Calculates new expiration timestamp
     * @param sub Current subscription
     * @param isUpgrade Whether this is an upgrade
     * @return New expiration timestamp
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
     * @notice Cancels an active subscription
     */
    function cancelSubscription() external whenNotPaused {
        Subscription storage sub = subscriptions[msg.sender];
        if (sub.tier == SubscriptionTier.Basic) revert NoActiveSubscription();

        sub.tier = SubscriptionTier.Basic;
        sub.expiresAt = block.timestamp;
        sub.priceAtSubscription = 0;
        
        emit SubscriptionCancelled(msg.sender);
    }

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
     * @notice Allows executives to withdraw accumulated USDC
     * @param amount Amount of USDC to withdraw
     * @param recipient Address to receive the USDC
     */
    function withdrawUSDC(uint256 amount, address recipient) 
        external 
        onlyExecutive 
        whenNotPaused 
    {
        if (recipient == address(0)) revert InvalidPrice();
        usdc.safeTransfer(recipient, amount);
    }

    /**
     * @notice Emergency pause function
     */
    function pause() external onlyExecutive {
        _pause();
    }

    /**
     * @notice Resume contract operations
     */
    function unpause() external onlyExecutive {
        _unpause();
    }
}