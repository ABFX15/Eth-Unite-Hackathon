// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IAdaptiveLimitOrder {
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
        );
}

interface IDynamicSlippageCalculator {
    function getVolatilityScore(
        address tokenA,
        address tokenB
    ) external view returns (uint256 score, uint256 confidence);
}

contract SlippageOptimizer is Ownable {
    struct OptimizerParams {
        uint256 learningRate; // How quickly to adapt (basis points)
        uint256 momentumFactor; // Momentum for gradient descent (basis points)
        uint256 regularization; // L2 regularization factor
        uint256 explorationRate; // Exploration vs exploitation (basis points)
    }

    struct TokenPairMetrics {
        uint256 totalOrders;
        uint256 successfulFills;
        uint256 totalVolume;
        uint256 avgFillTime;
        uint256 optimalSlippageMA; // Moving average of optimal slippage
        uint256 lastOptimization;
        mapping(uint256 => uint256) volatilityToSlippage; // Volatility bucket -> optimal slippage
    }

    struct PerformanceData {
        uint256 volatilityBucket; // 0-100 (volatility / 100)
        uint256 orderSize; // Order size bucket
        uint256 slippageUsed;
        uint256 fillTime;
        bool successful;
        uint256 timestamp;
    }

    mapping(bytes32 => TokenPairMetrics) public pairMetrics;
    mapping(bytes32 => PerformanceData[]) public performanceHistory;
    mapping(address => OptimizerParams) public tokenOptimizerParams;

    IAdaptiveLimitOrder public limitOrderContract;
    IDynamicSlippageCalculator public slippageCalculator;

    OptimizerParams public defaultParams;

    // Bucketing parameters
    uint256 constant VOLATILITY_BUCKETS = 20; // 0-5%, 5-10%, etc.
    uint256 constant SIZE_BUCKETS = 10; // Small, medium, large orders
    uint256 constant HISTORY_LIMIT = 1000; // Max performance records per pair

    // Learning parameters
    uint256 constant MIN_SAMPLES = 10; // Minimum samples for optimization
    uint256 constant OPTIMIZATION_INTERVAL = 3600; // 1 hour

    event SlippageOptimized(
        address indexed tokenA,
        address indexed tokenB,
        uint256 volatilityBucket,
        uint256 oldSlippage,
        uint256 newSlippage,
        uint256 confidence
    );

    event PerformanceRecorded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 orderId,
        bool successful,
        uint256 slippage,
        uint256 fillTime
    );

    constructor(
        address _limitOrderContract,
        address _slippageCalculator
    ) Ownable(msg.sender) {
        limitOrderContract = IAdaptiveLimitOrder(_limitOrderContract);
        slippageCalculator = IDynamicSlippageCalculator(_slippageCalculator);

        // Set default optimizer parameters
        defaultParams = OptimizerParams({
            learningRate: 100, // 1%
            momentumFactor: 900, // 90% momentum
            regularization: 10, // 0.1% regularization
            explorationRate: 100 // 1% exploration
        });
    }

    function optimizeSlippage(
        address tokenA,
        address tokenB,
        uint256 orderSize,
        uint256 currentVolatility
    ) external view returns (uint256 optimizedSlippage, uint256 confidence) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);

        uint256 volatilityBucket = currentVolatility / 250; // 250 bps per bucket (2.5%)
        if (volatilityBucket >= VOLATILITY_BUCKETS)
            volatilityBucket = VOLATILITY_BUCKETS - 1;

        uint256 sizeBucket = _getOrderSizeBucket(orderSize);

        // Get historical performance for this volatility range
        (
            uint256 historicalOptimal,
            uint256 sampleCount
        ) = _getHistoricalOptimal(pairKey, volatilityBucket, sizeBucket);

        if (sampleCount < MIN_SAMPLES) {
            // Insufficient data - use conservative default
            return (_getDefaultSlippage(currentVolatility), 25);
        }

        // Apply machine learning optimization
        optimizedSlippage = _applyMLOptimization(
            pairKey,
            volatilityBucket,
            sizeBucket,
            historicalOptimal,
            currentVolatility
        );

        // Calculate confidence based on sample size and recency
        confidence = _calculateOptimizationConfidence(sampleCount, pairKey);

        return (optimizedSlippage, confidence);
    }

    function recordOrderPerformance(
        address tokenA,
        address tokenB,
        uint256 orderId,
        uint256 slippageUsed,
        uint256 fillTime,
        bool successful
    ) external {
        // Only allow calls from the limit order contract
        require(msg.sender == address(limitOrderContract), "Unauthorized");

        bytes32 pairKey = _getPairKey(tokenA, tokenB);

        // Get volatility at time of order
        (uint256 volatility, ) = slippageCalculator.getVolatilityScore(
            tokenA,
            tokenB
        );
        uint256 volatilityBucket = volatility / 250;
        if (volatilityBucket >= VOLATILITY_BUCKETS)
            volatilityBucket = VOLATILITY_BUCKETS - 1;

        // Record performance data
        PerformanceData memory perfData = PerformanceData({
            volatilityBucket: volatilityBucket,
            orderSize: 0, // TODO: Get order size from order ID
            slippageUsed: slippageUsed,
            fillTime: fillTime,
            successful: successful,
            timestamp: block.timestamp
        });

        _addPerformanceData(pairKey, perfData);

        // Update pair metrics
        TokenPairMetrics storage metrics = pairMetrics[pairKey];
        metrics.totalOrders++;
        if (successful) {
            metrics.successfulFills++;
            metrics.avgFillTime = (metrics.avgFillTime + fillTime) / 2;
        }

        emit PerformanceRecorded(
            tokenA,
            tokenB,
            orderId,
            successful,
            slippageUsed,
            fillTime
        );

        if (
            block.timestamp - metrics.lastOptimization > OPTIMIZATION_INTERVAL
        ) {
            _triggerOptimization(pairKey, tokenA, tokenB);
        }
    }

    function _applyMLOptimization(
        bytes32 pairKey,
        uint256 volatilityBucket,
        uint256 sizeBucket,
        uint256 historicalOptimal,
        uint256 currentVolatility
    ) internal view returns (uint256) {
        PerformanceData[] memory history = performanceHistory[pairKey];

        int256 gradient = _calculateGradient(history, volatilityBucket);

        OptimizerParams memory params = tokenOptimizerParams[address(0)]; // Use default
        if (params.learningRate == 0) params = defaultParams;

        int256 adjustment = (gradient * int256(params.learningRate)) / 10000;

        uint256 momentum = params.momentumFactor;
        int256 momentumAdjusted = (int256(historicalOptimal) *
            int256(momentum) +
            adjustment *
            int256(10000 - momentum)) / 10000;

        uint256 regularized = uint256(momentumAdjusted) +
            (params.regularization * currentVolatility) /
            10000;

        uint256 exploration = (params.explorationRate * _pseudoRandom()) /
            100000;

        return regularized + exploration;
    }

    function _calculateGradient(
        PerformanceData[] memory history,
        uint256 volatilityBucket
    ) internal pure returns (int256 gradient) {
        uint256 lowSlippageSuccess = 0;
        uint256 lowSlippageTotal = 0;
        uint256 highSlippageSuccess = 0;
        uint256 highSlippageTotal = 0;

        uint256 medianSlippage = _calculateMedianSlippage(
            history,
            volatilityBucket
        );

        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].volatilityBucket == volatilityBucket) {
                if (history[i].slippageUsed <= medianSlippage) {
                    lowSlippageTotal++;
                    if (history[i].successful) lowSlippageSuccess++;
                } else {
                    highSlippageTotal++;
                    if (history[i].successful) highSlippageSuccess++;
                }
            }
        }

        if (lowSlippageTotal == 0 || highSlippageTotal == 0) return 0;

        uint256 lowSuccessRate = (lowSlippageSuccess * 10000) /
            lowSlippageTotal;
        uint256 highSuccessRate = (highSlippageSuccess * 10000) /
            highSlippageTotal;

        gradient = int256(highSuccessRate) - int256(lowSuccessRate);

        return gradient;
    }

    function _calculateMedianSlippage(
        PerformanceData[] memory history,
        uint256 volatilityBucket
    ) internal pure returns (uint256) {
        uint256[] memory slippages = new uint256[](history.length);
        uint256 count = 0;

        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].volatilityBucket == volatilityBucket) {
                slippages[count] = history[i].slippageUsed;
                count++;
            }
        }

        if (count == 0) return 50;

        for (uint256 i = 0; i < count - 1; i++) {
            for (uint256 j = 0; j < count - i - 1; j++) {
                if (slippages[j] > slippages[j + 1]) {
                    uint256 temp = slippages[j];
                    slippages[j] = slippages[j + 1];
                    slippages[j + 1] = temp;
                }
            }
        }

        return slippages[count / 2];
    }

    function _getHistoricalOptimal(
        bytes32 pairKey,
        uint256 volatilityBucket,
        uint256 sizeBucket
    ) internal view returns (uint256 optimal, uint256 sampleCount) {
        PerformanceData[] memory history = performanceHistory[pairKey];

        uint256 totalSlippage = 0;
        uint256 successfulSlippage = 0;
        uint256 successCount = 0;
        sampleCount = 0;

        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].volatilityBucket == volatilityBucket) {
                sampleCount++;
                totalSlippage += history[i].slippageUsed;

                if (history[i].successful) {
                    successfulSlippage += history[i].slippageUsed;
                    successCount++;
                }
            }
        }

        if (successCount > 0) {
            optimal = successfulSlippage / successCount;
        } else if (sampleCount > 0) {
            optimal = totalSlippage / sampleCount;
        } else {
            optimal = 50; // Default 0.5%
        }

        return (optimal, sampleCount);
    }

    function _addPerformanceData(
        bytes32 pairKey,
        PerformanceData memory data
    ) internal {
        PerformanceData[] storage history = performanceHistory[pairKey];

        if (history.length >= HISTORY_LIMIT) {
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history[history.length - 1] = data;
        } else {
            history.push(data);
        }
    }

    function _triggerOptimization(
        bytes32 pairKey,
        address tokenA,
        address tokenB
    ) internal {
        // Update last optimization timestamp
        pairMetrics[pairKey].lastOptimization = block.timestamp;

        // TODO: Trigger batch optimization for all volatility buckets
        // This could be done in a separate transaction to avoid gas limits
    }

    function _getOrderSizeBucket(
        uint256 orderSize
    ) internal pure returns (uint256) {
        // Bucket orders by size (logarithmic scale)
        if (orderSize < 1000e18) return 0; // < 1K
        if (orderSize < 10000e18) return 1; // 1K-10K
        if (orderSize < 100000e18) return 2; // 10K-100K
        return 3; // > 100K
    }

    function _getDefaultSlippage(
        uint256 volatility
    ) internal pure returns (uint256) {
        // Conservative default based on volatility
        if (volatility < 100) return 25; // 0.25% for low volatility
        if (volatility < 500) return 50; // 0.5% for medium volatility
        if (volatility < 1000) return 100; // 1% for high volatility
        return 200; // 2% for extreme volatility
    }

    function _calculateOptimizationConfidence(
        uint256 sampleCount,
        bytes32 pairKey
    ) internal view returns (uint256) {
        TokenPairMetrics storage metrics = pairMetrics[pairKey];

        uint256 sampleConfidence = sampleCount >= MIN_SAMPLES * 2
            ? 100
            : (sampleCount * 100) / (MIN_SAMPLES * 2);

        uint256 successRate = metrics.totalOrders > 0
            ? (metrics.successfulFills * 100) / metrics.totalOrders
            : 50;
        uint256 successConfidence = successRate;

        return (sampleConfidence + successConfidence) / 2;
    }

    function _pseudoRandom() internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        msg.sender
                    )
                )
            ) % 1000;
    }

    function _getPairKey(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    tokenA < tokenB ? tokenA : tokenB,
                    tokenA < tokenB ? tokenB : tokenA
                )
            );
    }

    function setOptimizerParams(
        address token,
        uint256 learningRate,
        uint256 momentumFactor,
        uint256 regularization,
        uint256 explorationRate
    ) external onlyOwner {
        tokenOptimizerParams[token] = OptimizerParams({
            learningRate: learningRate,
            momentumFactor: momentumFactor,
            regularization: regularization,
            explorationRate: explorationRate
        });
    }

    // View functions
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
        )
    {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        TokenPairMetrics storage metrics = pairMetrics[pairKey];

        uint256 successRateBps = metrics.totalOrders > 0
            ? (metrics.successfulFills * 10000) / metrics.totalOrders
            : 0;

        return (
            metrics.totalOrders,
            successRateBps,
            metrics.avgFillTime,
            metrics.optimalSlippageMA
        );
    }
}
