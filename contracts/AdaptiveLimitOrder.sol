// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

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

    // Separate function for external slippage calculation (NO state changes)
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
        require(initialSlippage <= 1000, "Slippage too high"); // Max 10%


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
            orderHash: 0, // Will be set when submitting to 1inch
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
                volatilityScore: 0, // Will be updated
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
            (order.fillAttempts * 25); // +0.25% per attempt

        emit OrderRetry(orderId, retrySlippage, order.fillAttempts);

        _resubmitToOneInch(orderId, retrySlippage);
    }

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

    function _submitToOneInch(uint256 orderId) internal {
        Order storage order = orders[orderId];

        uint256 expectedAmountOut = (order.amountIn * order.basePrice) / 1e18;
        uint256 slippageAmount = (expectedAmountOut * order.currentSlippage) /
            10000;
        uint256 minAmountOut = expectedAmountOut - slippageAmount;

        I1inchLimitOrderProtocol.Order memory oneInchOrder = I1inchLimitOrderProtocol
            .Order({
                maker: order.maker,
                makerAsset: order.tokenIn,
                takerAsset: order.tokenOut,
                makingAmount: order.amountIn,
                takingAmount: minAmountOut,
                deadline: block.timestamp + 86400, // 24 hours
                makerAssetData: "",
                takerAssetData: ""
            });


        bytes32 oneInchHash = limitOrderProtocol.submitOrder(oneInchOrder);

        order.orderHash = uint256(oneInchHash);
        oneInchOrderToLocal[oneInchHash] = orderId;
    }

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

        I1inchLimitOrderProtocol.Order memory newOneInchOrder = I1inchLimitOrderProtocol
            .Order({
                maker: order.maker,
                makerAsset: order.tokenIn,
                takerAsset: order.tokenOut,
                makingAmount: order.amountIn,
                takingAmount: minAmountOut,
                deadline: block.timestamp + 86400, // 24 hours
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

        I1inchLimitOrderProtocol.Order memory retryOrder = I1inchLimitOrderProtocol
            .Order({
                maker: order.maker,
                makerAsset: order.tokenIn,
                takerAsset: order.tokenOut,
                makingAmount: order.amountIn,
                takingAmount: minAmountOut,
                deadline: block.timestamp + 86400, // 24 hours
                makerAssetData: "",
                takerAssetData: ""
            });


        bytes32 retryHash = limitOrderProtocol.submitOrder(retryOrder);


        order.orderHash = uint256(retryHash);
        oneInchOrderToLocal[retryHash] = orderId;
    }


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

        uint256 currentSlippage = order.currentSlippage;

        if (currentSlippage > 500) return (false, "Excessive slippage");

        if (block.timestamp > order.createdAt + 86400)
            return (false, "Order expired");

        if (block.timestamp > order.lastSlippageUpdate + 3600)
            return (false, "Slippage data stale");

        return (true, "Order fillable");
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
