// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SlippageOptimizer
 * @notice Machine learning-powered slippage optimization using historical performance data
 * @dev Uses gradient descent and volatility bucketing to continuously improve slippage predictions
 */
contract SlippageOptimizer is Ownable {
    /**
     * @notice Historical performance record for slippage predictions
     * @param slippageUsed Slippage that was used for the trade
     * @param actualSlippage Actual slippage that occurred
     * @param success Whether the trade was successful
     * @param timestamp When the trade occurred
     * @param volatilityBucket Volatility category at time of trade
     */
    struct PerformanceRecord {
        uint256 slippageUsed;
        uint256 actualSlippage;
        bool success;
        uint256 timestamp;
        uint256 volatilityBucket;
    }

    /**
     * @notice Optimization parameters for a specific volatility bucket
     * @param learningRate Rate at which the algorithm learns from new data
     * @param momentum Momentum factor for gradient descent
     * @param averageError Running average of prediction errors
     * @param totalSamples Total number of samples in this bucket
     */
    struct OptimizationParams {
        uint256 learningRate;
        uint256 momentum;
        uint256 averageError;
        uint256 totalSamples;
    }

    /// @notice Maximum number of performance records to store
    uint256 constant MAX_PERFORMANCE_HISTORY = 1000;
    /// @notice Number of volatility buckets for ML optimization
    uint256 constant VOLATILITY_BUCKETS = 5;

    /// @notice Historical performance data for each token pair
    mapping(bytes32 => PerformanceRecord[]) public performanceHistory;
    /// @notice Optimization parameters for each volatility bucket
    mapping(uint256 => OptimizationParams) public bucketParams;
    /// @notice Current optimal slippage for each volatility bucket
    mapping(uint256 => uint256) public optimalSlippageByBucket;
    /// @notice Confidence scores for each bucket's predictions
    mapping(uint256 => uint256) public bucketConfidence;
    /// @notice Total number of successful predictions
    uint256 public totalSuccessfulPredictions;
    /// @notice Total number of predictions made
    uint256 public totalPredictions;

    /**
     * @notice Emitted when performance data is recorded
     * @param pairKey Token pair identifier
     * @param slippageUsed Slippage that was used
     * @param actualSlippage Actual slippage that occurred
     * @param success Whether the trade was successful
     * @param volatilityBucket Volatility category
     */
    event PerformanceRecorded(
        bytes32 indexed pairKey,
        uint256 slippageUsed,
        uint256 actualSlippage,
        bool success,
        uint256 volatilityBucket
    );

    /**
     * @notice Emitted when optimization parameters are updated
     * @param volatilityBucket Bucket being updated
     * @param newOptimalSlippage New optimal slippage for the bucket
     * @param confidence Confidence level of the optimization
     */
    event OptimizationUpdated(
        uint256 indexed volatilityBucket,
        uint256 newOptimalSlippage,
        uint256 confidence
    );

    /**
     * @notice Emitted when gradient descent optimization is performed
     * @param volatilityBucket Bucket being optimized
     * @param oldValue Previous optimal value
     * @param newValue New optimal value
     * @param gradient Calculated gradient
     */
    event GradientDescentPerformed(
        uint256 indexed volatilityBucket,
        uint256 oldValue,
        uint256 newValue,
        int256 gradient
    );

    /**
     * @notice Initializes the SlippageOptimizer with default parameters
     */
    constructor() Ownable(msg.sender) {
        _initializeOptimizationParams();
    }

    /**
     * @notice Records performance data for a completed trade
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param slippageUsed Slippage that was set for the trade
     * @param actualSlippage Actual slippage that occurred
     * @param success Whether the trade was successful
     * @param volatilityScore Current volatility score for bucketing
     */
    function recordPerformance(
        address tokenIn,
        address tokenOut,
        uint256 slippageUsed,
        uint256 actualSlippage,
        bool success,
        uint256 volatilityScore
    ) external {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        uint256 volatilityBucket = _getVolatilityBucket(volatilityScore);

        PerformanceRecord memory record = PerformanceRecord({
            slippageUsed: slippageUsed,
            actualSlippage: actualSlippage,
            success: success,
            timestamp: block.timestamp,
            volatilityBucket: volatilityBucket
        });

        _addPerformanceRecord(pairKey, record);

        totalPredictions++;
        if (success) {
            totalSuccessfulPredictions++;
        }

        _updateBucketParams(
            volatilityBucket,
            slippageUsed,
            actualSlippage,
            success
        );

        emit PerformanceRecorded(
            pairKey,
            slippageUsed,
            actualSlippage,
            success,
            volatilityBucket
        );
    }

    /**
     * @notice Optimizes slippage for a given volatility level using ML algorithms
     * @param volatilityScore Current market volatility score
     * @return optimizedSlippage ML-optimized slippage recommendation
     * @return confidence Confidence level of the recommendation (0-100)
     */
    function optimizeSlippage(
        uint256 volatilityScore
    ) external view returns (uint256 optimizedSlippage, uint256 confidence) {
        uint256 volatilityBucket = _getVolatilityBucket(volatilityScore);

        optimizedSlippage = optimalSlippageByBucket[volatilityBucket];
        confidence = bucketConfidence[volatilityBucket];

        if (optimizedSlippage == 0) {
            optimizedSlippage = _getDefaultSlippageForBucket(volatilityBucket);
            confidence = 50;
        }

        return (optimizedSlippage, confidence);
    }

    /**
     * @notice Performs gradient descent optimization for all volatility buckets
     */
    function performGradientDescent() external onlyOwner {
        for (uint256 bucket = 0; bucket < VOLATILITY_BUCKETS; bucket++) {
            _optimizeBucket(bucket);
        }
    }

    /**
     * @notice Gets performance metrics for the optimization system
     * @return successRate Overall success rate of predictions
     * @return totalSamples Total number of trades analyzed
     * @return averageConfidence Average confidence across all buckets
     */
    function getPerformanceMetrics()
        external
        view
        returns (
            uint256 successRate,
            uint256 totalSamples,
            uint256 averageConfidence
        )
    {
        successRate = totalPredictions > 0
            ? (totalSuccessfulPredictions * 100) / totalPredictions
            : 0;

        totalSamples = totalPredictions;

        uint256 confidenceSum = 0;
        uint256 activeBuckets = 0;

        for (uint256 i = 0; i < VOLATILITY_BUCKETS; i++) {
            if (bucketConfidence[i] > 0) {
                confidenceSum += bucketConfidence[i];
                activeBuckets++;
            }
        }

        averageConfidence = activeBuckets > 0
            ? confidenceSum / activeBuckets
            : 0;

        return (successRate, totalSamples, averageConfidence);
    }

    /**
     * @notice Gets detailed optimization parameters for a volatility bucket
     * @param volatilityBucket Bucket to query (0-4)
     * @return params Optimization parameters for the bucket
     */
    function getBucketParams(
        uint256 volatilityBucket
    ) external view returns (OptimizationParams memory params) {
        require(volatilityBucket < VOLATILITY_BUCKETS, "Invalid bucket");
        return bucketParams[volatilityBucket];
    }

    /**
     * @notice Gets performance history for a specific token pair
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return history Array of performance records
     */
    function getPerformanceHistory(
        address tokenIn,
        address tokenOut
    ) external view returns (PerformanceRecord[] memory history) {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        return performanceHistory[pairKey];
    }

    /**
     * @notice Updates learning parameters for a volatility bucket
     * @param volatilityBucket Bucket to update
     * @param learningRate New learning rate
     * @param momentum New momentum factor
     */
    function updateBucketParams(
        uint256 volatilityBucket,
        uint256 learningRate,
        uint256 momentum
    ) external onlyOwner {
        require(volatilityBucket < VOLATILITY_BUCKETS, "Invalid bucket");
        require(learningRate <= 1000, "Learning rate too high");
        require(momentum <= 1000, "Momentum too high");

        bucketParams[volatilityBucket].learningRate = learningRate;
        bucketParams[volatilityBucket].momentum = momentum;
    }

    /**
     * @notice Generates unique key for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return Unique bytes32 key for the pair
     */
    function _getPairKey(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }

    /**
     * @notice Determines volatility bucket based on volatility score
     * @param volatilityScore Current volatility score
     * @return bucket Volatility bucket (0-4, low to high volatility)
     */
    function _getVolatilityBucket(
        uint256 volatilityScore
    ) internal pure returns (uint256 bucket) {
        if (volatilityScore < 100) return 0;
        if (volatilityScore < 300) return 1;
        if (volatilityScore < 600) return 2;
        if (volatilityScore < 1000) return 3;
        return 4;
    }

    /**
     * @notice Adds performance record to history with circular buffer
     * @param pairKey Token pair identifier
     * @param record Performance record to add
     */
    function _addPerformanceRecord(
        bytes32 pairKey,
        PerformanceRecord memory record
    ) internal {
        PerformanceRecord[] storage history = performanceHistory[pairKey];

        if (history.length >= MAX_PERFORMANCE_HISTORY) {
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history[history.length - 1] = record;
        } else {
            history.push(record);
        }
    }

    /**
     * @notice Updates bucket parameters based on new performance data
     * @param volatilityBucket Bucket to update
     * @param slippageUsed Slippage that was used
     * @param actualSlippage Actual slippage that occurred
     * @param success Whether the trade was successful
     */
    function _updateBucketParams(
        uint256 volatilityBucket,
        uint256 slippageUsed,
        uint256 actualSlippage,
        bool success
    ) internal {
        OptimizationParams storage params = bucketParams[volatilityBucket];

        uint256 error = slippageUsed > actualSlippage
            ? slippageUsed - actualSlippage
            : actualSlippage - slippageUsed;

        if (params.totalSamples == 0) {
            params.averageError = error;
        } else {
            params.averageError =
                (params.averageError * params.totalSamples + error) /
                (params.totalSamples + 1);
        }

        params.totalSamples++;

        uint256 successWeight = success ? 100 : 50;
        uint256 newConfidence = params.totalSamples > 10
            ? (successWeight * 90) / 100
            : (successWeight * params.totalSamples * 9) / 100;

        bucketConfidence[volatilityBucket] = newConfidence;
    }

    /**
     * @notice Optimizes slippage for a specific volatility bucket using gradient descent
     * @param volatilityBucket Bucket to optimize
     */
    function _optimizeBucket(uint256 volatilityBucket) internal {
        OptimizationParams storage params = bucketParams[volatilityBucket];

        if (params.totalSamples < 5) return;

        uint256 currentOptimal = optimalSlippageByBucket[volatilityBucket];
        if (currentOptimal == 0) {
            currentOptimal = _getDefaultSlippageForBucket(volatilityBucket);
        }

        int256 gradient = _calculateGradient(volatilityBucket);

        int256 adjustment = (gradient * int256(params.learningRate)) / 1000;

        uint256 newOptimal;
        if (adjustment < 0 && uint256(-adjustment) > currentOptimal) {
            newOptimal = 1;
        } else if (adjustment < 0) {
            newOptimal = currentOptimal - uint256(-adjustment);
        } else {
            newOptimal = currentOptimal + uint256(adjustment);
        }

        if (newOptimal > 1000) {
            newOptimal = 1000;
        }
        if (newOptimal < 5) {
            newOptimal = 5;
        }

        optimalSlippageByBucket[volatilityBucket] = newOptimal;

        emit GradientDescentPerformed(
            volatilityBucket,
            currentOptimal,
            newOptimal,
            gradient
        );

        emit OptimizationUpdated(
            volatilityBucket,
            newOptimal,
            bucketConfidence[volatilityBucket]
        );
    }

    /**
     * @notice Calculates gradient for optimization based on recent performance
     * @param volatilityBucket Bucket to calculate gradient for
     * @return gradient Calculated gradient for optimization
     */
    function _calculateGradient(
        uint256 volatilityBucket
    ) internal view returns (int256 gradient) {
        OptimizationParams storage params = bucketParams[volatilityBucket];

        if (params.averageError > 50) {
            return -10;
        } else if (params.averageError > 25) {
            return -5;
        } else if (params.averageError < 5) {
            return 5;
        } else {
            return 0;
        }
    }

    /**
     * @notice Gets default slippage for a volatility bucket
     * @param volatilityBucket Bucket to get default for
     * @return Default slippage value in basis points
     */
    function _getDefaultSlippageForBucket(
        uint256 volatilityBucket
    ) internal pure returns (uint256) {
        if (volatilityBucket == 0) return 20;
        if (volatilityBucket == 1) return 35;
        if (volatilityBucket == 2) return 60;
        if (volatilityBucket == 3) return 100;
        return 150;
    }

    /**
     * @notice Initializes optimization parameters for all volatility buckets
     */
    function _initializeOptimizationParams() internal {
        for (uint256 i = 0; i < VOLATILITY_BUCKETS; i++) {
            bucketParams[i] = OptimizationParams({
                learningRate: 100,
                momentum: 50,
                averageError: 0,
                totalSamples: 0
            });

            optimalSlippageByBucket[i] = _getDefaultSlippageForBucket(i);
            bucketConfidence[i] = 50;
        }
    }
}
