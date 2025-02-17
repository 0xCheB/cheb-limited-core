// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { ICheBControlCenter } from "./ICheBControlCenter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ICheBSubscription
 * @author CheB Protocol
 * @notice Interface for the CheBSubscription contract, defining the API for managing user subscriptions and payments.
 * @dev This interface outlines the external functions and data structures of the CheBSubscription contract, which handles subscription tiers, pricing, user subscriptions, and USDC payments.
 * Contracts interacting with the CheBSubscription contract should use this interface to ensure proper function calls and data handling.
 */
interface ICheBSubscription {
    /**
     * @notice Enum defining the different subscription tiers available to users.
     * @dev Represents the levels of access and features users can subscribe to within the CheB platform.
     * - `Basic`: Free tier with limited features.
     * - `Plus`: Paid tier offering enhanced features at a mid-range price.
     * - `Premium`: Highest paid tier providing full access to all premium features.
     */
    enum SubscriptionTier {
        Basic,
        Plus,
        Premium
    }

    /**
     * @dev Custom error thrown when an invalid subscription tier is specified as a function parameter.
     * @dev Implementations should revert with this error if an unsupported or out-of-range `SubscriptionTier` enum value is provided.
     */
    error InvalidTier();

    /**
     * @dev Custom error thrown when the user has not granted sufficient USDC allowance to the contract for subscription payment.
     * @dev Implementations should revert with this error if the contract is unable to transfer the required USDC amount due to insufficient allowance.
     */
    error InsufficientAllowance();

    /**
     * @dev Custom error thrown when the user's USDC balance is less than the required subscription price.
     * @dev Implementations should revert with this error if the user does not have enough USDC to complete the subscription purchase.
     */
    error InsufficientBalance();

    /**
     * @dev Custom error thrown when an invalid price is provided, such as setting a zero price for a paid tier.
     * @dev Implementations should revert with this error if a price is invalid for the intended operation, like setting a zero price for Plus or Premium tiers.
     */
    error InvalidPrice();

    /**
     * @dev Custom error thrown when an action is attempted by an unauthorized account, typically for executive-only functions.
     * @dev Implementations should revert with this error to restrict access to functions intended only for executive roles defined in CheBControlCenter.
     */
    error Unauthorized();

    /**
     * @dev Custom error thrown when attempting to cancel a subscription but the user does not have an active paid subscription.
     * @dev Implementations should revert with this error if a user tries to cancel a subscription when they are already on the Basic tier or have no active paid subscription.
     */
    error NoActiveSubscription();

    /**
     * @dev Custom error thrown if a USDC refund fails during a subscription purchase process.
     * @dev Implementations should revert with this error if a refund of excess USDC amount fails to be transferred back to the user.
     */
    error RefundFailed();

    /**
     * @dev Custom error thrown when a user attempts to downgrade their subscription to a lower tier while their current subscription is still active.
     * @dev Implementations should revert with this error to prevent direct downgrading during an active subscription period; users should cancel first and then subscribe to a lower tier.
     */
    error CannotDowngrade();

    /**
     * @dev Custom error thrown when a user attempts to subscribe to the same subscription tier they are already subscribed to.
     * @dev Implementations should revert with this error to prevent redundant subscription actions to the same tier.
     */
    error SameTier();

    /**
     * @dev Custom error thrown when an invalid recipient address (zero address) is provided for USDC withdrawal.
     * @dev Implementations should revert with this error to ensure that USDC withdrawals are only made to valid, non-zero addresses.
     */
    error InvalidRecipientAddress();

    /**
     * @notice Returns the address of the CheBControlCenter contract associated with this subscription contract.
     * @return ICheBControlCenter The contract address of the CheBControlCenter.
     *
     * @dev Implementations should provide a view function to retrieve the address of the linked CheBControlCenter contract, used for access control and role verification.
     */
    function chebControl() external view returns (ICheBControlCenter);

    /**
     * @notice Returns the address of the USDC token contract used for subscription payments.
     * @return IERC20 The contract address of the USDC token (ERC20).
     *
     * @dev Implementations should provide a view function to retrieve the address of the USDC token contract, which is the payment currency for subscriptions.
     */
    function usdc() external view returns (IERC20);

    /**
     * @notice Returns the current price for a given subscription tier.
     * @param tier The SubscriptionTier enum value to query the price for.
     * @return uint256 The price of the specified subscription tier in USDC (with decimals).
     *
     * @dev Implementations should provide a view function to get the current subscription price for each tier. Prices are typically in USDC with a fixed number of decimals.
     */
    function tierPrices(SubscriptionTier tier) external view returns (uint256);

    /**
     * @notice Returns the subscription details for a given user address.
     * @param user The address of the user to query the subscription for.
     * @return tier The current subscription tier of the user.
     * @return expiresAt Timestamp representing the subscription expiration date.
     * @return lastPayment Timestamp of the last successful subscription payment.
     * @return priceAtSubscription Price of the subscription tier at the time of subscription.
     *
     * @dev Implementations should provide a view function to retrieve comprehensive subscription details for a user, including tier, expiry, payment history and price at subscription time.
     */
    function subscriptions(address user) external view returns (
        SubscriptionTier tier,
        uint256 expiresAt,
        uint256 lastPayment,
        uint256 priceAtSubscription
    );

    /**
     * @notice Updates the price for a specific subscription tier.
     * @param tier The SubscriptionTier enum value for which to update the price.
     * @param newPrice The new price for the subscription tier in USDC (with decimals).
     *
     * @dev Implementations should provide a function to allow executives to update the subscription price for Plus and Premium tiers. Basic tier price is typically fixed at zero.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     *  InvalidTier Implementations should revert with this error if attempting to update the price of the Basic tier.
     *  InvalidPrice Implementations should revert with this error if `newPrice` is zero for paid tiers.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     */
    function updateTierPrice(SubscriptionTier tier, uint256 newPrice) external;

    /**
     * @notice Subscribes a user to a specific subscription tier or renews/upgrades their existing subscription.
     * @param tier The SubscriptionTier enum value to subscribe to.
     * @param amount The amount of USDC provided by the user for the subscription. Should be equal to or greater than the tier price.
     *
     * @dev Implementations should provide a function for users to subscribe to different tiers. This function should handle new subscriptions, renewals and upgrades, and manage USDC payments.
     *
     *  InvalidTier Implementations should revert with this error if an invalid subscription tier is specified.
     *  InsufficientAllowance Implementations should revert with this error if USDC allowance is insufficient.
     *  InsufficientBalance Implementations should revert with this error if user's USDC balance is less than the tier price.
     *  CannotDowngrade Implementations should revert with this error if attempting to downgrade to a lower tier while subscription is active.
     *  SameTier Implementations should revert with this error if attempting to subscribe to the same tier already subscribed to.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function subscribe(SubscriptionTier tier, uint256 amount) external;

    /**
     * @notice Cancels an active paid subscription for the calling user, reverting them to the Basic tier.
     *
     * @dev Implementations should provide a function for users to cancel their active Plus or Premium subscriptions. Upon cancellation, the user typically reverts to the Basic tier.
     *
     *  NoActiveSubscription Implementations should revert with this error if the user has no active paid subscription to cancel.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     *  ReentrancyGuard: reentrant call Implementations may revert with this error if reentrancy is detected.
     */
    function cancelSubscription() external;

    /**
     * @notice Gets the current subscription details for a given user address.
     * @param user Address of the user to check the subscription details for.
     * @return tier The current subscription tier of the user.
     * @return expiresAt Subscription expiration timestamp.
     * @return isActive Boolean indicating if the subscription is currently active.
     * @return currentPrice The current price being paid for the subscription.
     *
     * @dev Implementations should provide a view function to retrieve detailed subscription information for any user. This is a read-only function to query subscription status.
     */
    function getSubscription(address user) external view returns (
        SubscriptionTier tier,
        uint256 expiresAt,
        bool isActive,
        uint256 currentPrice
    );

    /**
     * @notice Allows executives to withdraw accumulated USDC from the subscription contract.
     * @param amount The amount of USDC to withdraw.
     * @param recipient The address to which the USDC should be transferred.
     *
     * @dev Implementations should provide a function for executives to withdraw USDC accumulated from subscription payments.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     *  InvalidRecipientAddress Implementations should revert with this error if `recipient` is the zero address.
     *  Pausable: paused Implementations may revert with this error if the contract is paused.
     */
    function withdrawUSDC(uint256 amount, address recipient) external;

    /**
     * @notice Pauses the contract, halting critical operations such as subscription purchases and price updates.
     *
     * @dev Implementations should provide a function for executives to pause the contract in case of emergencies or for maintenance.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     */
    function pause() external;

    /**
     * @notice Resumes contract operations after being paused, allowing subscription purchases and price updates to proceed.
     *
     * @dev Implementations should provide a function for executives to unpause the contract, restoring normal operations.
     *
     *  Unauthorized Implementations should revert with this error if the caller is not an executive.
     */
    function unpause() external;

    /**
     * @notice Checks if the contract is currently paused.
     * @return bool True if the contract is paused, false otherwise.
     *
     * @dev Implementations should provide a view function to check the current pause state of the contract, allowing external contracts and users to determine if the subscription system is active.
     */
    function paused() external view returns (bool);
}