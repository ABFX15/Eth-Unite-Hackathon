// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./AdaptiveLimitOrder.sol";

/**
 * @title CrossChainBridge
 * @notice Ethereum-side bridge contract for cross-chain atomic swaps with NEAR Protocol
 * @dev Implements hashlock/timelock mechanisms for secure cross-chain transactions
 */
contract CrossChainBridge is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /**
     * @notice Represents a cross-chain order between NEAR and Ethereum
     * @param nearOrderId Order ID from the NEAR contract
     * @param tokenOut Ethereum token address to receive
     * @param amountOut Amount of Ethereum tokens expected
     * @param hashlock Hash for atomic swap security
     * @param timelock Expiration timestamp for the order
     * @param recipient Address that will receive the tokens
     * @param currentSlippage Current slippage value from NEAR side
     * @param completed Whether the order has been successfully completed
     * @param cancelled Whether the order has been cancelled
     */
    struct CrossChainOrder {
        uint256 nearOrderId;
        address tokenOut;
        uint256 amountOut;
        bytes32 hashlock;
        uint256 timelock;
        address recipient;
        uint256 currentSlippage;
        bool completed;
        bool cancelled;
    }

    /// @notice Mapping of hashlock to cross-chain order details
    mapping(bytes32 => CrossChainOrder) public crossChainOrders;
    /// @notice Mapping of NEAR order ID to corresponding hashlock
    mapping(uint256 => bytes32) public nearOrderToHash;

    /// @notice Reference to the AdaptiveLimitOrder contract
    AdaptiveLimitOrder public immutable adaptiveLimitOrder;
    /// @notice Address of the NEAR bridge contract for communication
    address public nearBridgeContract;

    /**
     * @notice Emitted when a new cross-chain order is created
     * @param nearOrderId Order ID from NEAR contract
     * @param hashlock Hash used for atomic swap
     * @param tokenOut Token to be received on Ethereum
     * @param amountOut Amount of tokens expected
     * @param slippage Current slippage for the order
     */
    event CrossChainOrderCreated(
        uint256 indexed nearOrderId,
        bytes32 indexed hashlock,
        address tokenOut,
        uint256 amountOut,
        uint256 slippage
    );

    /**
     * @notice Emitted when a cross-chain order is successfully claimed
     * @param hashlock Hash of the claimed order
     * @param amountOut Amount of tokens transferred
     * @param recipient Address that received the tokens
     */
    event CrossChainOrderClaimed(
        bytes32 indexed hashlock,
        uint256 amountOut,
        address recipient
    );

    /**
     * @notice Emitted when slippage is updated for an existing order
     * @param nearOrderId NEAR order ID being updated
     * @param oldSlippage Previous slippage value
     * @param newSlippage New slippage value
     */
    event SlippageUpdated(
        uint256 indexed nearOrderId,
        uint256 oldSlippage,
        uint256 newSlippage
    );

    /**
     * @notice Emitted when an expired order is refunded
     * @param hashlock Hash of the refunded order
     * @param recipient Address that received the refund
     * @param amount Amount refunded
     */
    event OrderRefunded(
        bytes32 indexed hashlock,
        address recipient,
        uint256 amount
    );

    /**
     * @notice Emitted when an adaptive order is created for cross-chain trading
     * @param nearOrderId NEAR order ID
     * @param ethOrderId Ethereum adaptive order ID
     * @param hashlock Cross-chain hash identifier
     */
    event AdaptiveOrderCreated(
        uint256 indexed nearOrderId,
        uint256 indexed ethOrderId,
        bytes32 indexed hashlock
    );

    /**
     * @notice Initializes the CrossChainBridge contract
     * @param _adaptiveLimitOrder Address of the AdaptiveLimitOrder contract
     * @param _nearBridgeContract Address of the NEAR bridge contract
     */
    constructor(
        address _adaptiveLimitOrder,
        address _nearBridgeContract
    ) Ownable(msg.sender) {
        require(
            _adaptiveLimitOrder != address(0),
            "Invalid adaptive order contract"
        );
        require(
            _nearBridgeContract != address(0),
            "Invalid NEAR bridge contract"
        );

        adaptiveLimitOrder = AdaptiveLimitOrder(_adaptiveLimitOrder);
        nearBridgeContract = _nearBridgeContract;
    }

    /**
     * @notice Creates a new cross-chain order with hashlock/timelock security
     * @param nearOrderId Order ID from NEAR contract
     * @param tokenOut Ethereum token to receive
     * @param amountOut Amount of tokens expected
     * @param hashlock Hash for atomic swap
     * @param timelock Expiration timestamp
     * @param recipient Address to receive tokens
     * @param slippage Current slippage value
     */
    function createCrossChainOrder(
        uint256 nearOrderId,
        address tokenOut,
        uint256 amountOut,
        bytes32 hashlock,
        uint256 timelock,
        address recipient,
        uint256 slippage
    ) external nonReentrant {
        require(tokenOut != address(0), "Invalid token");
        require(amountOut > 0, "Invalid amount");
        require(hashlock != bytes32(0), "Invalid hashlock");
        require(timelock > block.timestamp, "Invalid timelock");
        require(recipient != address(0), "Invalid recipient");
        require(
            crossChainOrders[hashlock].hashlock == bytes32(0),
            "Order exists"
        );

        CrossChainOrder memory newOrder = CrossChainOrder({
            nearOrderId: nearOrderId,
            tokenOut: tokenOut,
            amountOut: amountOut,
            hashlock: hashlock,
            timelock: timelock,
            recipient: recipient,
            currentSlippage: slippage,
            completed: false,
            cancelled: false
        });

        crossChainOrders[hashlock] = newOrder;
        nearOrderToHash[nearOrderId] = hashlock;

        emit CrossChainOrderCreated(
            nearOrderId,
            hashlock,
            tokenOut,
            amountOut,
            slippage
        );
    }

    /**
     * @notice Claims tokens from a cross-chain order using the preimage
     * @param hashlock Hash identifying the order
     * @param preimage Secret that unlocks the hashlock
     */
    function claimCrossChainOrder(
        bytes32 hashlock,
        bytes32 preimage
    ) external nonReentrant {
        CrossChainOrder storage order = crossChainOrders[hashlock];

        require(order.hashlock != bytes32(0), "Order not found");
        require(!order.completed, "Order already completed");
        require(!order.cancelled, "Order cancelled");
        require(block.timestamp <= order.timelock, "Order expired");
        require(
            keccak256(abi.encodePacked(preimage)) == hashlock,
            "Invalid preimage"
        );

        uint256 contractBalance = IERC20(order.tokenOut).balanceOf(
            address(this)
        );
        require(
            contractBalance >= order.amountOut,
            "Insufficient contract balance"
        );

        order.completed = true;

        IERC20(order.tokenOut).safeTransfer(order.recipient, order.amountOut);

        emit CrossChainOrderClaimed(hashlock, order.amountOut, order.recipient);
    }

    /**
     * @notice Updates slippage for an existing cross-chain order
     * @param nearOrderId NEAR order ID to update
     * @param newSlippage New slippage value
     */
    function updateSlippage(uint256 nearOrderId, uint256 newSlippage) external {
        bytes32 hashlock = nearOrderToHash[nearOrderId];
        require(hashlock != bytes32(0), "Order not found");

        CrossChainOrder storage order = crossChainOrders[hashlock];
        require(!order.completed, "Order already completed");
        require(!order.cancelled, "Order cancelled");
        require(block.timestamp <= order.timelock, "Order expired");

        uint256 oldSlippage = order.currentSlippage;
        order.currentSlippage = newSlippage;

        emit SlippageUpdated(nearOrderId, oldSlippage, newSlippage);
    }

    /**
     * @notice Refunds tokens from an expired cross-chain order
     * @param hashlock Hash identifying the expired order
     */
    function refundExpiredOrder(bytes32 hashlock) external nonReentrant {
        CrossChainOrder storage order = crossChainOrders[hashlock];

        require(order.hashlock != bytes32(0), "Order not found");
        require(!order.completed, "Order already completed");
        require(!order.cancelled, "Order already cancelled");
        require(block.timestamp > order.timelock, "Order not expired");

        order.cancelled = true;

        uint256 contractBalance = IERC20(order.tokenOut).balanceOf(
            address(this)
        );
        if (contractBalance >= order.amountOut) {
            IERC20(order.tokenOut).safeTransfer(owner(), order.amountOut);
        }

        emit OrderRefunded(hashlock, order.recipient, order.amountOut);
    }

    /**
     * @notice Creates an adaptive order specifically for cross-chain trading
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @param basePrice Base price for the order
     * @param maxSlippageDeviation Maximum allowed slippage deviation
     * @param nearOrderId Corresponding NEAR order ID
     * @param hashlock Cross-chain hash identifier
     * @return ethOrderId ID of the created Ethereum adaptive order
     */
    function createAdaptiveOrderForCrossChain(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 basePrice,
        uint256 maxSlippageDeviation,
        uint256 nearOrderId,
        bytes32 hashlock
    ) external nonReentrant returns (uint256 ethOrderId) {
        require(
            tokenIn != address(0) && tokenOut != address(0),
            "Invalid tokens"
        );
        require(amountIn > 0, "Invalid amount");
        require(basePrice > 0, "Invalid price");
        require(hashlock != bytes32(0), "Invalid hashlock");

        uint256 senderBalance = IERC20(tokenIn).balanceOf(msg.sender);
        require(senderBalance >= amountIn, "Insufficient balance");

        uint256 allowance = IERC20(tokenIn).allowance(
            msg.sender,
            address(this)
        );
        require(allowance >= amountIn, "Insufficient allowance");

        uint256 initialSlippage = adaptiveLimitOrder.calculateOrderSlippage(
            tokenIn,
            tokenOut,
            amountIn
        );

        IERC20(tokenIn).safeTransferFrom(
            msg.sender,
            address(adaptiveLimitOrder),
            amountIn
        );

        ethOrderId = adaptiveLimitOrder.createAdaptiveOrder(
            tokenIn,
            tokenOut,
            amountIn,
            basePrice,
            maxSlippageDeviation,
            initialSlippage
        );

        emit AdaptiveOrderCreated(nearOrderId, ethOrderId, hashlock);

        return ethOrderId;
    }

    /**
     * @notice Gets details of a cross-chain order by hashlock
     * @param hashlock Hash identifying the order
     * @return order Complete order details
     */
    function getCrossChainOrder(
        bytes32 hashlock
    ) external view returns (CrossChainOrder memory order) {
        return crossChainOrders[hashlock];
    }

    /**
     * @notice Gets hashlock for a given NEAR order ID
     * @param nearOrderId NEAR order ID to lookup
     * @return hashlock Corresponding hashlock
     */
    function getHashlockForNearOrder(
        uint256 nearOrderId
    ) external view returns (bytes32 hashlock) {
        return nearOrderToHash[nearOrderId];
    }

    /**
     * @notice Checks if a cross-chain order is claimable
     * @param hashlock Hash identifying the order
     * @return claimable Whether the order can be claimed
     * @return reason Reason if not claimable
     */
    function isOrderClaimable(
        bytes32 hashlock
    ) external view returns (bool claimable, string memory reason) {
        CrossChainOrder memory order = crossChainOrders[hashlock];

        if (order.hashlock == bytes32(0)) return (false, "Order not found");
        if (order.completed) return (false, "Order already completed");
        if (order.cancelled) return (false, "Order cancelled");
        if (block.timestamp > order.timelock) return (false, "Order expired");

        uint256 contractBalance = IERC20(order.tokenOut).balanceOf(
            address(this)
        );
        if (contractBalance < order.amountOut)
            return (false, "Insufficient contract balance");

        return (true, "Order claimable");
    }

    /**
     * @notice Updates the NEAR bridge contract address
     * @param newBridgeContract New bridge contract address
     */
    function updateNearBridgeContract(
        address newBridgeContract
    ) external onlyOwner {
        require(newBridgeContract != address(0), "Invalid bridge contract");
        nearBridgeContract = newBridgeContract;
    }

    /**
     * @notice Emergency function to fund the contract with tokens
     * @param token Token address to fund
     * @param amount Amount to fund
     */
    function fundContract(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Emergency withdrawal function for contract owner
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");

        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient balance");

        IERC20(token).safeTransfer(owner(), amount);
    }
}
