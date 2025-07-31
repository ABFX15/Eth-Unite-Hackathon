// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IDynamicSlippageCalculator.sol";
import "./interfaces/IAmountGetter.sol";
import "./interfaces/I1inchLimitOrderProtocol.sol";

/**
 * @title AdaptiveLimitOrder
 * @notice AI-powered adaptive limit order system with dynamic slippage optimization
 * @dev Integrates with 1inch Limit Order Protocol to provide intelligent slippage management
 */
contract AdaptiveLimitOrder is ReentrancyGuard, Ownable, IAmountGetter {
    using SafeERC20 for IERC20;

    /**
     * @notice Represents an adaptive limit order with dynamic slippage
     * @param maker Address of the order creator
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @param basePrice Base price without slippage adjustments
     * @param currentSlippage Current dynamic slippage in basis points
     * @param lastSlippageUpdate Timestamp of last slippage adjustment
     * @param maxSlippageDeviation Maximum allowed slippage change per update
     * @param orderHash Hash of the corresponding 1inch order
     * @param active Whether the order is currently active
     * @param createdAt Order creation timestamp
     * @param fillAttempts Number of failed fill attempts
     */
    struct Order {
        address maker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 basePrice;
        uint256 currentSlippage;
        uint256 lastSlippageUpdate;
        uint256 maxSlippageDeviation;
        uint256 orderHash;
        bool active;
        uint256 createdAt;
        uint256 fillAttempts;
    }

    /**
     * @notice Historical record of slippage adjustments for an order
     * @param timestamp When the slippage was recorded
     * @param slippage Slippage value in basis points
     * @param volatilityScore Market volatility score at the time
     * @param fillAttempted Whether a fill was attempted
     * @param fillSuccessful Whether the fill was successful
     */
    struct SlippageHistory {
        uint256 timestamp;
        uint256 slippage;
        uint256 volatilityScore;
        bool fillAttempted;
        bool fillSuccessful;
    }

    /// @notice Mapping of order ID to order details
    mapping(uint256 => Order) public orders;
    /// @notice Mapping of order ID to its slippage history
    mapping(uint256 => SlippageHistory[]) public orderSlippageHistory;
    /// @notice Mapping of user address to their order IDs
    mapping(address => uint256[]) public userOrders;
    /// @notice Mapping of 1inch order hash to local order ID
    mapping(bytes32 => uint256) public oneInchOrderToLocal;

    /// @notice Next order ID to be assigned
    uint256 public nextOrderId;
    /// @notice Dynamic slippage calculator contract
    IDynamicSlippageCalculator public slippageCalculator;
    /// @notice 1inch Limit Order Protocol contract
    I1inchLimitOrderProtocol public limitOrderProtocol;

    /// @notice Minimum time between slippage updates (5 minutes)
    uint256 constant SLIPPAGE_UPDATE_INTERVAL = 300;
    /// @notice Maximum slippage change per update (1%)
    uint256 constant MAX_SLIPPAGE_CHANGE = 100;
    /// @notice Maximum fill attempts before pausing order
    uint256 constant FILL_ATTEMPT_LIMIT = 10;

    /**
     * @notice Emitted when a new adaptive order is created
     * @param orderId Unique identifier for the order
     * @param maker Address of the order creator
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @param basePrice Base price for the order
     * @param initialSlippage Initial slippage setting
     */
    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 basePrice,
        uint256 initialSlippage
    );

    /**
     * @notice Emitted when order slippage is adjusted
     * @param orderId Order being adjusted
     * @param oldSlippage Previous slippage value
     * @param newSlippage New slippage value
     * @param volatilityScore Current market volatility score
     */
    event SlippageAdjusted(
        uint256 indexed orderId,
        uint256 oldSlippage,
        uint256 newSlippage,
        uint256 volatilityScore
    );

    /**
     * @notice Emitted when an order is filled
     * @param orderId Order that was filled
     * @param filledAmount Amount of tokens filled
     * @param finalSlippage Final slippage used for execution
     * @param executionPrice Actual execution price
     */
    event OrderFilled(
        uint256 indexed orderId,
        uint256 filledAmount,
        uint256 finalSlippage,
        uint256 executionPrice
    );

    /**
     * @notice Emitted when an order is retried with adjusted parameters
     * @param orderId Order being retried
     * @param newSlippage New slippage for the retry
     * @param attemptNumber Attempt number for this order
     */
    event OrderRetry(
        uint256 indexed orderId,
        uint256 newSlippage,
        uint256 attemptNumber
    );

    /**
     * @notice Initializes the AdaptiveLimitOrder contract
     * @param _slippageCalculator Address of the dynamic slippage calculator
     * @param _limitOrderProtocol Address of the 1inch Limit Order Protocol
     */
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

    /**
     * @notice Calculates optimal slippage for a potential order without state changes
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return slippage Optimal slippage in basis points
     */
    function calculateOrderSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 slippage) {
        return
            slippageCalculator.calculateDynamicSlippage(
                tokenIn,
                tokenOut,
                amountIn
            );
    }

    /**
     * @notice Creates a new adaptive limit order with AI-optimized slippage
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input tokens to trade
     * @param basePrice Base price for the order (without slippage)
     * @param maxSlippageDeviation Maximum allowed slippage change per update
     * @param initialSlippage Pre-calculated initial slippage from calculateOrderSlippage
     * @return orderId Unique identifier for the created order
     */
    function createAdaptiveOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 basePrice,
        uint256 maxSlippageDeviation,
        uint256 initialSlippage
    ) external nonReentrant returns (uint256 orderId) {
        require(
            tokenIn != address(0) && tokenOut != address(0),
            "Invalid tokens"
        );
        require(amountIn > 0, "Invalid amount");
        require(basePrice > 0, "Invalid price");
        require(initialSlippage <= 1000, "Slippage too high");

        orderId = nextOrderId++;
        address maker = msg.sender;
        uint256 currentTime = block.timestamp;

        Order memory newOrder = Order({
            maker: maker,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            basePrice: basePrice,
            currentSlippage: initialSlippage,
            lastSlippageUpdate: currentTime,
            maxSlippageDeviation: maxSlippageDeviation,
            orderHash: 0,
            active: true,
            createdAt: currentTime,
            fillAttempts: 0
        });

        orders[orderId] = newOrder;
        userOrders[maker].push(orderId);

        orderSlippageHistory[orderId].push(
            SlippageHistory({
                timestamp: currentTime,
                slippage: initialSlippage,
                volatilityScore: 0,
                fillAttempted: false,
                fillSuccessful: false
            })
        );

        IERC20(tokenIn).safeTransferFrom(maker, address(this), amountIn);
        _submitToOneInch(orderId);

        emit OrderCreated(
            orderId,
            maker,
            tokenIn,
            tokenOut,
            amountIn,
            basePrice,
            initialSlippage
        );
        return orderId;
    }

    /**
     * @notice Updates the slippage for an existing order based on current market conditions
     * @param orderId ID of the order to update
     */
    function updateOrderSlippage(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.active, "Order not active");
        require(
            block.timestamp >=
                order.lastSlippageUpdate + SLIPPAGE_UPDATE_INTERVAL,
            "Too early to update"
        );

        uint256 newSlippage = slippageCalculator.calculateDynamicSlippage(
            order.tokenIn,
            order.tokenOut,
            order.amountIn
        );

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

        (uint256 volatilityScore, ) = slippageCalculator.getVolatilityScore(
            order.tokenIn,
            order.tokenOut
        );

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

        _updateOneInchOrder(orderId);
    }

    /**
     * @notice Calculates the minimum output amount for a given order
     * @param token Output token address
     * @param amount Input amount
     * @param data Encoded order ID
     * @return Minimum output amount after slippage
     */
    function getAmount(
        address token,
        uint256 amount,
        bytes calldata data
    ) external view override returns (uint256) {
        uint256 orderId = abi.decode(data, (uint256));
        Order memory order = orders[orderId];

        require(order.active, "Order not active");
        require(token == order.tokenOut, "Invalid token");

        uint256 expectedAmount = (amount * order.basePrice) / 1e18;
        uint256 slippageAmount = (expectedAmount * order.currentSlippage) /
            10000;
        uint256 minAmountOut = expectedAmount - slippageAmount;

        return minAmountOut;
    }

    /**
     * @notice Retries a failed order with increased slippage tolerance
     * @param orderId ID of the order to retry
     */
    function retryFailedOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.active, "Order not active");
        require(
            order.maker == msg.sender || msg.sender == owner(),
            "Not authorized"
        );
        require(order.fillAttempts < FILL_ATTEMPT_LIMIT, "Too many attempts");

        order.fillAttempts++;

        uint256 retrySlippage = order.currentSlippage +
            (order.fillAttempts * 25);

        emit OrderRetry(orderId, retrySlippage, order.fillAttempts);

        _resubmitToOneInch(orderId, retrySlippage);
    }

    /**
     * @notice Cancels an active order and refunds tokens to the maker
     * @param orderId ID of the order to cancel
     */
    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        require(order.active, "Order not active");
        require(order.maker == msg.sender, "Not order maker");

        order.active = false;

        IERC20(order.tokenIn).safeTransfer(order.maker, order.amountIn);

        if (order.orderHash != 0) {
            limitOrderProtocol.cancelOrder(bytes32(order.orderHash));
        }
    }

    /**
     * @notice Submits order to 1inch protocol with current slippage settings
     * @param orderId ID of the order to submit
     */
    function _submitToOneInch(uint256 orderId) internal {
        Order storage order = orders[orderId];

        uint256 expectedAmountOut = (order.amountIn * order.basePrice) / 1e18;
        uint256 slippageAmount = (expectedAmountOut * order.currentSlippage) /
            10000;
        uint256 minAmountOut = expectedAmountOut - slippageAmount;

        I1inchLimitOrderProtocol.Order
            memory oneInchOrder = I1inchLimitOrderProtocol.Order({
                maker: order.maker,
                makerAsset: order.tokenIn,
                takerAsset: order.tokenOut,
                makingAmount: order.amountIn,
                takingAmount: minAmountOut,
                deadline: block.timestamp + 86400,
                makerAssetData: "",
                takerAssetData: ""
            });

        bytes32 oneInchHash = limitOrderProtocol.submitOrder(oneInchOrder);

        order.orderHash = uint256(oneInchHash);
        oneInchOrderToLocal[oneInchHash] = orderId;
    }

    /**
     * @notice Updates existing 1inch order with new slippage parameters
     * @param orderId ID of the order to update
     */
    function _updateOneInchOrder(uint256 orderId) internal {
        Order storage order = orders[orderId];
        require(order.active, "Order not active");
        require(order.orderHash != 0, "Order not submitted");

        bytes32 oldHash = bytes32(order.orderHash);
        delete oneInchOrderToLocal[oldHash];

        limitOrderProtocol.cancelOrder(oldHash);

        uint256 expectedAmountOut = (order.amountIn * order.basePrice) / 1e18;
        uint256 slippageAmount = (expectedAmountOut * order.currentSlippage) /
            10000;
        uint256 minAmountOut = expectedAmountOut - slippageAmount;

        I1inchLimitOrderProtocol.Order
            memory newOneInchOrder = I1inchLimitOrderProtocol.Order({
                maker: order.maker,
                makerAsset: order.tokenIn,
                takerAsset: order.tokenOut,
                makingAmount: order.amountIn,
                takingAmount: minAmountOut,
                deadline: block.timestamp + 86400,
                makerAssetData: "",
                takerAssetData: ""
            });

        bytes32 newOneInchHash = limitOrderProtocol.submitOrder(
            newOneInchOrder
        );

        order.orderHash = uint256(newOneInchHash);
        oneInchOrderToLocal[newOneInchHash] = orderId;

        emit OrderRetry(orderId, order.currentSlippage, order.fillAttempts);
    }

    /**
     * @notice Resubmits order to 1inch with custom slippage for retry attempts
     * @param orderId ID of the order to resubmit
     * @param retrySlippage Custom slippage for this retry
     */
    function _resubmitToOneInch(
        uint256 orderId,
        uint256 retrySlippage
    ) internal {
        Order storage order = orders[orderId];

        if (order.orderHash != 0) {
            bytes32 oldHash = bytes32(order.orderHash);
            delete oneInchOrderToLocal[oldHash];
            limitOrderProtocol.cancelOrder(oldHash);
        }

        uint256 expectedAmountOut = (order.amountIn * order.basePrice) / 1e18;
        uint256 slippageAmount = (expectedAmountOut * retrySlippage) / 10000;
        uint256 minAmountOut = expectedAmountOut - slippageAmount;

        I1inchLimitOrderProtocol.Order
            memory retryOrder = I1inchLimitOrderProtocol.Order({
                maker: order.maker,
                makerAsset: order.tokenIn,
                takerAsset: order.tokenOut,
                makingAmount: order.amountIn,
                takingAmount: minAmountOut,
                deadline: block.timestamp + 86400,
                makerAssetData: "",
                takerAssetData: ""
            });

        bytes32 retryHash = limitOrderProtocol.submitOrder(retryOrder);

        order.orderHash = uint256(retryHash);
        oneInchOrderToLocal[retryHash] = orderId;
    }

    /**
     * @notice Retrieves order details by ID
     * @param orderId ID of the order to retrieve
     * @return Order details
     */
    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    /**
     * @notice Retrieves all order IDs for a specific user
     * @param user Address of the user
     * @return Array of order IDs belonging to the user
     */
    function getUserOrders(
        address user
    ) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    /**
     * @notice Retrieves complete slippage history for an order
     * @param orderId ID of the order
     * @return Array of slippage history records
     */
    function getOrderSlippageHistory(
        uint256 orderId
    ) external view returns (SlippageHistory[] memory) {
        return orderSlippageHistory[orderId];
    }

    /**
     * @notice Gets the current slippage setting for an order
     * @param orderId ID of the order
     * @return Current slippage in basis points
     */
    function getCurrentSlippage(
        uint256 orderId
    ) external view returns (uint256) {
        return orders[orderId].currentSlippage;
    }

    /**
     * @notice Checks if an order is eligible for filling
     * @param orderId ID of the order to check
     * @return fillable Whether the order can be filled
     * @return reason Human-readable reason if not fillable
     */
    function isOrderFillable(
        uint256 orderId
    ) external view returns (bool fillable, string memory reason) {
        Order memory order = orders[orderId];

        if (!order.active) return (false, "Order inactive");
        if (order.fillAttempts >= FILL_ATTEMPT_LIMIT)
            return (false, "Too many failed attempts");

        uint256 currentSlippage = order.currentSlippage;

        if (currentSlippage > 500) return (false, "Excessive slippage");

        if (block.timestamp > order.createdAt + 86400)
            return (false, "Order expired");

        if (block.timestamp > order.lastSlippageUpdate + 3600)
            return (false, "Slippage data stale");

        return (true, "Order fillable");
    }

    /**
     * @notice Retrieves performance metrics for an order
     * @param orderId ID of the order
     * @return avgSlippage Average slippage across all updates
     * @return slippageUpdates Total number of slippage updates
     * @return maxSlippage Highest slippage value recorded
     * @return minSlippage Lowest slippage value recorded
     */
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
