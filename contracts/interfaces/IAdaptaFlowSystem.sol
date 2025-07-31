// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAdaptaFlowSystem
 * @dev Comprehensive interface for the AdaptaFlow Protocol system
 * Demonstrates modular architecture and CEI pattern compliance
 */
interface IAdaptaFlowSystem {
    // =================
    // CORE STRUCTURES
    // =================

    struct SystemOrder {
        uint256 orderId;
        address maker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 basePrice;
        uint256 currentSlippage;
        uint256 volatilityScore;
        bool isActive;
    }

    struct SlippageMetrics {
        uint256 dynamicSlippage;
        uint256 volatilityScore;
        uint256 confidence;
        uint256 liquidityAdjustment;
    }

    // =================
    // CORE FUNCTIONS
    // =================

    /**
     * @dev Calculate optimal slippage using multiple data sources
     * @param tokenA First token in pair
     * @param tokenB Second token in pair
     * @param orderSize Size of the order
     * @return metrics Complete slippage metrics
     */
    function calculateOptimalSlippage(
        address tokenA,
        address tokenB,
        uint256 orderSize
    ) external view returns (SlippageMetrics memory metrics);

    /**
     * @dev Create an adaptive limit order with dynamic slippage
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount to swap
     * @param basePrice Base price without slippage
     * @param maxSlippageDeviation Maximum allowed slippage change
     * @return orderId Unique order identifier
     */
    function createSystemOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 basePrice,
        uint256 maxSlippageDeviation
    ) external returns (uint256 orderId);

    /**
     * @dev Update order slippage based on market conditions
     * @param orderId Order to update
     */
    function updateOrderSlippage(uint256 orderId) external;

    /**
     * @dev Get comprehensive order information
     * @param orderId Order identifier
     * @return order Complete order details
     */
    function getSystemOrder(
        uint256 orderId
    ) external view returns (SystemOrder memory order);

    // =================
    // CROSS-CHAIN FUNCTIONS
    // =================

    /**
     * @dev Create cross-chain order linking ETH and NEAR
     * @param nearOrderId Order ID from NEAR contract
     * @param tokenOut ETH token to receive
     * @param amountOut Expected amount
     * @param hashlock Hash for atomic swap
     * @param timelock Expiration timestamp
     * @param initialSlippage Starting slippage
     */
    function createCrossChainOrder(
        uint256 nearOrderId,
        address tokenOut,
        uint256 amountOut,
        bytes32 hashlock,
        uint256 timelock,
        uint256 initialSlippage
    ) external;

    /**
     * @dev Claim cross-chain order with secret
     * @param hashlock Order identifier
     * @param secret Atomic swap secret
     * @param recipient Token recipient
     */
    function claimCrossChainOrder(
        bytes32 hashlock,
        string calldata secret,
        address recipient
    ) external;

    // =================
    // VOLATILITY MANAGEMENT
    // =================

    /**
     * @dev Update volatility data from multiple sources
     * @param tokenA First token
     * @param tokenB Second token
     */
    function updateVolatilityData(address tokenA, address tokenB) external;

    /**
     * @dev Get detailed volatility breakdown
     * @param tokenA First token
     * @param tokenB Second token
     * @return priceVol Price volatility
     * @return volumeVol Volume volatility
     * @return spreadVol Spread volatility
     * @return composite Composite score
     * @return confidence Confidence level
     */
    function getDetailedVolatility(
        address tokenA,
        address tokenB
    )
        external
        view
        returns (
            uint256 priceVol,
            uint256 volumeVol,
            uint256 spreadVol,
            uint256 composite,
            uint256 confidence
        );

    // =================
    // OPTIMIZATION
    // =================

    /**
     * @dev Record order performance for ML optimization
     * @param tokenA First token
     * @param tokenB Second token
     * @param orderId Order identifier
     * @param slippageUsed Actual slippage
     * @param fillTime Time to fill
     * @param successful Whether fill succeeded
     */
    function recordOrderPerformance(
        address tokenA,
        address tokenB,
        uint256 orderId,
        uint256 slippageUsed,
        uint256 fillTime,
        bool successful
    ) external;

    /**
     * @dev Get optimization metrics for token pair
     * @param tokenA First token
     * @param tokenB Second token
     * @return totalOrders Total orders processed
     * @return successRate Success rate in basis points
     * @return avgFillTime Average fill time
     * @return optimalSlippage Optimal slippage
     */
    function getOptimizationMetrics(
        address tokenA,
        address tokenB
    )
        external
        view
        returns (
            uint256 totalOrders,
            uint256 successRate,
            uint256 avgFillTime,
            uint256 optimalSlippage
        );

    // =================
    // EVENTS
    // =================

    event SystemOrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 dynamicSlippage
    );

    event SlippageOptimized(
        address indexed tokenA,
        address indexed tokenB,
        uint256 oldSlippage,
        uint256 newSlippage,
        uint256 confidence
    );

    event CrossChainOrderExecuted(
        bytes32 indexed hashlock,
        uint256 amountOut,
        address recipient,
        uint256 finalSlippage
    );

    event VolatilityUpdated(
        address indexed tokenA,
        address indexed tokenB,
        uint256 volatilityScore,
        uint256 confidence
    );
}
