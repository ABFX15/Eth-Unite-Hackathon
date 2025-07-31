// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./AdaptiveLimitOrder.sol";

contract CrossChainBridge is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct CrossChainOrder {
        uint256 nearOrderId; // Order ID from NEAR contract
        address tokenOut; // ETH token to receive
        uint256 amountOut; // Amount of ETH token expected
        bytes32 hashlock; // Hash for atomic swap
        uint256 timelock; // Expiration timestamp
        address recipient; // Who receives the tokens
        uint256 currentSlippage; // Current slippage from NEAR
        bool completed;
        bool cancelled;
    }

    mapping(bytes32 => CrossChainOrder) public crossChainOrders;
    mapping(uint256 => bytes32) public nearOrderToHash; // NEAR order ID to hashlock

    AdaptiveLimitOrder public immutable adaptiveLimitOrder;
    address public nearBridgeContract; // Rainbow Bridge contract address

    // Events
    event CrossChainOrderCreated(
        uint256 indexed nearOrderId,
        bytes32 indexed hashlock,
        address tokenOut,
        uint256 amountOut,
        uint256 slippage
    );

    event CrossChainOrderClaimed(
        bytes32 indexed hashlock,
        uint256 amountOut,
        address recipient
    );

    event SlippageUpdated(
        uint256 indexed nearOrderId,
        uint256 oldSlippage,
        uint256 newSlippage
    );

    constructor(
        address _adaptiveLimitOrder,
        address _nearBridgeContract
    ) Ownable(msg.sender) {
        adaptiveLimitOrder = AdaptiveLimitOrder(_adaptiveLimitOrder);
        nearBridgeContract = _nearBridgeContract;
    }

    // CEI Pattern: Checks-Effects-Interactions
    function createCrossChainOrder(
        uint256 nearOrderId,
        address tokenOut,
        uint256 amountOut,
        bytes32 hashlock,
        uint256 timelock,
        uint256 initialSlippage
    ) external {
        // CHECKS
        require(msg.sender == nearBridgeContract, "Only bridge can call");
        require(
            crossChainOrders[hashlock].timelock == 0,
            "Order already exists"
        );
        require(tokenOut != address(0), "Invalid token");
        require(amountOut > 0, "Invalid amount");
        require(timelock > block.timestamp, "Invalid timelock");

        // EFFECTS
        crossChainOrders[hashlock] = CrossChainOrder({
            nearOrderId: nearOrderId,
            tokenOut: tokenOut,
            amountOut: amountOut,
            hashlock: hashlock,
            timelock: timelock,
            recipient: address(0), // Will be set when claimed
            currentSlippage: initialSlippage,
            completed: false,
            cancelled: false
        });

        nearOrderToHash[nearOrderId] = hashlock;

        // INTERACTIONS (events only)
        emit CrossChainOrderCreated(
            nearOrderId,
            hashlock,
            tokenOut,
            amountOut,
            initialSlippage
        );
    }

    // CEI Pattern: Checks-Effects-Interactions
    function claimCrossChainOrder(
        bytes32 hashlock,
        string calldata secret,
        address recipient
    ) external nonReentrant {
        // CHECKS
        CrossChainOrder storage order = crossChainOrders[hashlock];
        require(order.timelock > 0, "Order not found");
        require(block.timestamp < order.timelock, "Order expired");
        require(!order.completed, "Order already completed");
        require(!order.cancelled, "Order cancelled");
        require(recipient != address(0), "Invalid recipient");

        // Verify secret matches hashlock
        require(
            keccak256(abi.encodePacked(secret)) == hashlock,
            "Invalid secret"
        );

        // Calculate final amount with current slippage
        uint256 slippageAmount = (order.amountOut * order.currentSlippage) /
            10000;
        uint256 finalAmount = order.amountOut - slippageAmount;
        require(finalAmount > 0, "Amount too small after slippage");

        // Check contract has sufficient balance
        require(
            IERC20(order.tokenOut).balanceOf(address(this)) >= finalAmount,
            "Insufficient contract balance"
        );

        // EFFECTS
        order.completed = true;
        order.recipient = recipient;

        // INTERACTIONS
        IERC20(order.tokenOut).safeTransfer(recipient, finalAmount);

        emit CrossChainOrderClaimed(hashlock, finalAmount, recipient);
    }

    // CEI Pattern: Checks-Effects-Interactions
    function updateSlippage(uint256 nearOrderId, uint256 newSlippage) external {
        // CHECKS
        require(msg.sender == nearBridgeContract, "Only bridge can call");
        require(newSlippage <= 1000, "Slippage too high"); // Max 10%

        bytes32 hashlock = nearOrderToHash[nearOrderId];
        require(hashlock != bytes32(0), "Order not found");

        CrossChainOrder storage order = crossChainOrders[hashlock];
        require(!order.completed && !order.cancelled, "Order not active");

        // EFFECTS
        uint256 oldSlippage = order.currentSlippage;
        order.currentSlippage = newSlippage;

        // INTERACTIONS (events only)
        emit SlippageUpdated(nearOrderId, oldSlippage, newSlippage);
    }

    // CEI Pattern: Checks-Effects-Interactions
    function refundExpiredOrder(bytes32 hashlock) external {
        // CHECKS
        CrossChainOrder storage order = crossChainOrders[hashlock];
        require(order.timelock > 0, "Order not found");
        require(block.timestamp >= order.timelock, "Order not expired");
        require(!order.completed, "Order already completed");

        // EFFECTS
        order.cancelled = true;

        // INTERACTIONS
        // In a real implementation, this would trigger a refund message
        // back to the NEAR contract to release the locked NEAR tokens
        // For now, we just mark as cancelled
    }

    // Integration with existing AdaptiveLimitOrder contract
    // CEI Pattern: Checks-Effects-Interactions
    function createAdaptiveOrderForCrossChain(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 basePrice,
        uint256 maxSlippageDeviation,
        bytes32 crossChainHashlock,
        uint256 initialSlippage
    ) external nonReentrant returns (uint256 orderId) {
        // CHECKS
        require(
            tokenIn != address(0) && tokenOut != address(0),
            "Invalid tokens"
        );
        require(amountIn > 0, "Invalid amount");
        require(basePrice > 0, "Invalid price");

        // Check allowance
        require(
            IERC20(tokenIn).allowance(msg.sender, address(this)) >= amountIn,
            "Insufficient allowance"
        );

        // EFFECTS - none here, handled in external calls

        // INTERACTIONS
        // First calculate slippage (view function, safe)
        uint256 calculatedSlippage = adaptiveLimitOrder.calculateOrderSlippage(
            tokenIn,
            tokenOut,
            amountIn
        );

        // Use the calculated slippage or provided initial slippage, whichever is higher
        uint256 finalSlippage = calculatedSlippage > initialSlippage
            ? calculatedSlippage
            : initialSlippage;

        // Transfer tokens from user to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve the AdaptiveLimitOrder contract
        IERC20(tokenIn).forceApprove(address(adaptiveLimitOrder), amountIn);

        // Create the adaptive order
        orderId = adaptiveLimitOrder.createAdaptiveOrder(
            tokenIn,
            tokenOut,
            amountIn,
            basePrice,
            maxSlippageDeviation,
            finalSlippage
        );

        // Store relationship between adaptive order and cross-chain order
        // This would be expanded with proper storage and events in a full implementation
        return orderId;
    }

    // View functions
    function getCrossChainOrder(
        bytes32 hashlock
    ) external view returns (CrossChainOrder memory) {
        return crossChainOrders[hashlock];
    }

    function isOrderExpired(bytes32 hashlock) external view returns (bool) {
        CrossChainOrder memory order = crossChainOrders[hashlock];
        return order.timelock > 0 && block.timestamp >= order.timelock;
    }

    function calculateFinalAmount(
        bytes32 hashlock
    ) external view returns (uint256) {
        CrossChainOrder memory order = crossChainOrders[hashlock];
        require(order.timelock > 0, "Order not found");

        uint256 slippageAmount = (order.amountOut * order.currentSlippage) /
            10000;
        return order.amountOut - slippageAmount;
    }

    // Admin functions with proper access control
    function updateNearBridgeContract(
        address newBridgeContract
    ) external onlyOwner {
        require(newBridgeContract != address(0), "Invalid address");
        nearBridgeContract = newBridgeContract;
    }

    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");
        IERC20(token).safeTransfer(owner(), amount);
    }

    function fundContract(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}
