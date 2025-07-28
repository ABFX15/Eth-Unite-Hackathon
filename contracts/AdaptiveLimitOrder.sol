// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IDynamicsSlippageCalculator.sol";
import "./interfaces/IAmountGetter.sol";
import "./interfaces/I1inchLimitOrderProtocol.sol";

contract AdaptiveLimitOrder is ReentrancyGuard, Ownable, IAmountGetter {
    using SafeERC20 for IERC20;

    struct Order {
        address maker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 basePrice; // Base price without slippage
        uint256 currentSlippage; // Current dynamic slippage in basis points
        uint256 lastSlippageUpdate; // Timestamp of last slippage adjustment
        uint256 maxSlippageDeviation; // Maximum allowed slippage change
        uint256 orderHash; // 1inch order hash
        bool active;
        uint256 createdAt;
        uint256 fillAttempts; // Number of failed fill attempts
    }

    struct SlippageHistory {
        uint256 timestamp;
        uint256 slippage;
        uint256 volatilityScore;
        bool fillAttempted;
        bool fillSuccessful;
    }

    mapping(uint256 => Order) public orders;
    mapping(uint256 => SlippageHistory[]) public orderSlippageHistory;
    mapping(address => uint256[]) public userOrders;
    mapping(bytes32 => uint256) public oneInchOrderToLocal; // Maps 1inch order hash to local order ID

    uint256 public nextOrderId;
    IDynamicSlippageCalculator public slippageCalculator;
    I1inchLimitOrderProtocol public limitOrderProtocol;

    // Protocol parameters
    uint256 constant SLIPPAGE_UPDATE_INTERVAL = 300; // 5 minutes
    uint256 constant MAX_SLIPPAGE_CHANGE = 100; // 1% max change per update
    uint256 constant FILL_ATTEMPT_LIMIT = 10; // Max retries before pausing order

    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 basePrice,
        uint256 initialSlippage
    );

    event SlippageAdjusted(
        uint256 indexed orderId,
        uint256 oldSlippage,
        uint256 newSlippage,
        uint256 volatilityScore
    );

    event OrderFilled(
        uint256 indexed orderId,
        uint256 filledAmount,
        uint256 finalSlippage,
        uint256 executionPrice
    );

    event OrderRetry(
        uint256 indexed orderId,
        uint256 newSlippage,
        uint256 attemptNumber
    );

    constructor(
        address _slippageCalculator,
        address _limitOrderProtocol
    ) Ownable(msg.sender) {
        require(
            _slippageCalculator != address(0),
            "Invalid slippage calculator"
        );
        require(
            _limitOrderProtocol != address(0),
            "Invalid limit order protocol"
        );
        slippageCalculator = IDynamicSlippageCalculator(_slippageCalculator);
        limitOrderProtocol = I1inchLimitOrderProtocol(_limitOrderProtocol);
    }

    function createAdaptiveOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 basePrice,
        uint256 maxSlippageDeviation
    ) external nonReentrant returns (uint256 orderId) {
        require(
            tokenIn != address(0) && tokenOut != address(0),
            "Invalid tokens"
        );
        require(amountIn > 0, "Invalid amount");
        require(basePrice > 0, "Invalid price");

        orderId = nextOrderId++;

        uint256 initialSlippage = slippageCalculator.calculateDynamicSlippage(
            tokenIn,
            tokenOut,
            amountIn
        );

        orders[orderId] = Order({
            maker: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            basePrice: basePrice,
            currentSlippage: initialSlippage,
            lastSlippageUpdate: block.timestamp,
            maxSlippageDeviation: maxSlippageDeviation,
            orderHash: 0, // Will be set when submitting to 1inch
            active: true,
            createdAt: block.timestamp,
            fillAttempts: 0
        });

        userOrders[msg.sender].push(orderId);

        // Record initial slippage
        orderSlippageHistory[orderId].push(
            SlippageHistory({
                timestamp: block.timestamp,
                slippage: initialSlippage,
                volatilityScore: 0, // Will be updated
                fillAttempted: false,
                fillSuccessful: false
            })
        );

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        emit OrderCreated(
            orderId,
            msg.sender,
            tokenIn,
            tokenOut,
            amountIn,
            basePrice,
            initialSlippage
        );

        // TODO: Submit order to 1inch Limit Order Protocol
        _submitToOneInch(orderId);

        return orderId;
    }

    function updateOrderSlippage(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.active, "Order not active");
        require(
            block.timestamp >=
                order.lastSlippageUpdate + SLIPPAGE_UPDATE_INTERVAL,
            "Too early to update"
        );

        // Calculate new optimal slippage
        uint256 newSlippage = slippageCalculator.calculateDynamicSlippage(
            order.tokenIn,
            order.tokenOut,
            order.amountIn
        );

        // Ensure slippage change is within limits
        uint256 slippageChange = newSlippage > order.currentSlippage
            ? newSlippage - order.currentSlippage
            : order.currentSlippage - newSlippage;

        if (slippageChange > order.maxSlippageDeviation) {
            if (newSlippage > order.currentSlippage) {
                newSlippage =
                    order.currentSlippage +
                    order.maxSlippageDeviation;
            } else {
                newSlippage = order.currentSlippage > order.maxSlippageDeviation
                    ? order.currentSlippage - order.maxSlippageDeviation
                    : 0;
            }
        }

        uint256 oldSlippage = order.currentSlippage;
        order.currentSlippage = newSlippage;
        order.lastSlippageUpdate = block.timestamp;

        // Get volatility score for tracking
        (uint256 volatilityScore, ) = slippageCalculator.getVolatilityScore(
            order.tokenIn,
            order.tokenOut
        );

        // Record slippage change
        orderSlippageHistory[orderId].push(
            SlippageHistory({
                timestamp: block.timestamp,
                slippage: newSlippage,
                volatilityScore: volatilityScore,
                fillAttempted: false,
                fillSuccessful: false
            })
        );

        emit SlippageAdjusted(
            orderId,
            oldSlippage,
            newSlippage,
            volatilityScore
        );

        // TODO: Update order in 1inch protocol with new slippage
        _updateOneInchOrder(orderId);
    }

    function getAmount(
        address token,
        uint256 amount,
        bytes calldata data
    ) external view override returns (uint256) {
        // IAmountGetter implementation for 1inch integration
        // This function is called by 1inch protocol to get dynamic amounts

        // Decode order ID from data
        uint256 orderId = abi.decode(data, (uint256));
        Order memory order = orders[orderId];

        require(order.active, "Order not active");
        require(token == order.tokenOut, "Invalid token");

        // Calculate minimum amount out based on current slippage
        uint256 expectedAmount = (amount * order.basePrice) / 1e18;
        uint256 slippageAmount = (expectedAmount * order.currentSlippage) /
            10000;
        uint256 minAmountOut = expectedAmount - slippageAmount;

        return minAmountOut;
    }

    function retryFailedOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.active, "Order not active");
        require(
            order.maker == msg.sender || msg.sender == owner(),
            "Not authorized"
        );
        require(order.fillAttempts < FILL_ATTEMPT_LIMIT, "Too many attempts");

        order.fillAttempts++;

        // Increase slippage for retry (more aggressive)
        uint256 retrySlippage = order.currentSlippage +
            (order.fillAttempts * 25); // +0.25% per attempt

        emit OrderRetry(orderId, retrySlippage, order.fillAttempts);

        // TODO: Resubmit to 1inch with increased slippage
        _resubmitToOneInch(orderId, retrySlippage);
    }

    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.active, "Order not active");
        require(order.maker == msg.sender, "Not order maker");

        order.active = false;

        // Return tokens to maker
        IERC20(order.tokenIn).safeTransfer(order.maker, order.amountIn);

        // TODO: Cancel order in 1inch protocol
        if (order.orderHash != 0) {
            limitOrderProtocol.cancelOrder(bytes32(order.orderHash));
        }
    }

    function _submitToOneInch(uint256 orderId) internal {
        // TODO: Create and submit order to 1inch Limit Order Protocol
        // Current interface only supports fillOrder and cancelOrder
        // Need to implement proper order submission logic based on 1inch SDK
        Order storage order = orders[orderId];

        // Generate deterministic unique order hash (like 1inch does)
        order.orderHash = uint256(
            keccak256(
                abi.encode(
                    orderId,
                    order.maker,
                    order.tokenIn,
                    order.tokenOut,
                    order.amountIn,
                    order.basePrice,
                    order.currentSlippage,
                    address(this),
                    block.chainid
                )
            )
        );
        oneInchOrderToLocal[bytes32(order.orderHash)] = orderId;
    }

    function _updateOneInchOrder(uint256 orderId) internal {
        // TODO: Update existing 1inch order with new slippage
        // - Cancel old order
        // - Create new order with updated slippage
        // - Update stored order hash
    }

    function _resubmitToOneInch(
        uint256 orderId,
        uint256 retrySlippage
    ) internal {
        // TODO: Resubmit order with higher slippage for failed fills
    }

    // View functions
    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    function getUserOrders(
        address user
    ) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    function getOrderSlippageHistory(
        uint256 orderId
    ) external view returns (SlippageHistory[] memory) {
        return orderSlippageHistory[orderId];
    }

    function getCurrentSlippage(
        uint256 orderId
    ) external view returns (uint256) {
        return orders[orderId].currentSlippage;
    }

    function isOrderFillable(
        uint256 orderId
    ) external view returns (bool fillable, string memory reason) {
        Order memory order = orders[orderId];

        if (!order.active) return (false, "Order inactive");
        if (order.fillAttempts >= FILL_ATTEMPT_LIMIT)
            return (false, "Too many failed attempts");

        // TODO: Check market conditions, slippage vs market spread, etc.
        return (true, "");
    }

    function getOrderPerformanceMetrics(
        uint256 orderId
    )
        external
        view
        returns (
            uint256 avgSlippage,
            uint256 slippageUpdates,
            uint256 maxSlippage,
            uint256 minSlippage
        )
    {
        SlippageHistory[] memory history = orderSlippageHistory[orderId];

        if (history.length == 0) return (0, 0, 0, 0);

        uint256 totalSlippage = 0;
        uint256 max = history[0].slippage;
        uint256 min = history[0].slippage;

        for (uint256 i = 0; i < history.length; i++) {
            totalSlippage += history[i].slippage;
            if (history[i].slippage > max) max = history[i].slippage;
            if (history[i].slippage < min) min = history[i].slippage;
        }

        return (totalSlippage / history.length, history.length, max, min);
    }
}
