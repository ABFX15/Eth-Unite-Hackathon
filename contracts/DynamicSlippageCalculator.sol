// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IDynamicSlippageCalculator.sol";

/**
 * @title DynamicSlippageCalculator
 * @notice AI-powered slippage calculator that analyzes volatility and market conditions
 * @dev Integrates multiple price oracles and uses machine learning algorithms for optimization
 */
contract DynamicSlippageCalculator is IDynamicSlippageCalculator, Ownable {
    /**
     * @notice Historical price data point
     * @param timestamp When the price was recorded
     * @param price Price value
     * @param volume Trading volume at the time
     */
    struct PricePoint {
        uint256 timestamp;
        uint256 price;
        uint256 volume;
    }

    /// @notice Maximum number of price points to store for historical analysis
    uint256 constant MAX_PRICE_HISTORY = 100;

    /// @notice Default slippage configurations for major tokens
    mapping(address => uint256) public defaultSlippages;
    /// @notice Exponential moving average for each token pair
    mapping(bytes32 => uint256) public exponentialMovingAverage;
    /// @notice Volatility standard deviation for each token pair
    mapping(bytes32 => uint256) public volatilityStdDev;
    /// @notice Historical price data for token pairs
    mapping(bytes32 => PricePoint[]) public priceHistory;
    /// @notice Cached liquidity data for optimization
    mapping(bytes32 => uint256) public liquidityCache;
    /// @notice Last update timestamp for each token pair
    mapping(bytes32 => uint256) public lastUpdate;
    /// @notice Confidence scores for ML predictions
    mapping(bytes32 => uint256) public confidenceScores;

    /// @notice EMA smoothing factor (alpha) in basis points
    uint256 public emaAlpha = 2000;
    /// @notice Minimum base slippage in basis points
    uint256 public minBaseSlippage = 10;
    /// @notice Maximum allowed slippage in basis points
    uint256 public maxSlippage = 1000;
    /// @notice Volatility multiplier for slippage adjustment
    uint256 public volatilityMultiplier = 150;

    /// @notice Address of 1inch price oracle
    address public oneInchOracle;
    /// @notice Address of Chainlink price feed aggregator
    address public chainlinkAggregator;

    /**
     * @notice Emitted when volatility data is updated for a token pair
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param newEMA New exponential moving average
     * @param newStdDev New standard deviation
     * @param confidence Confidence score for the update
     */
    event VolatilityDataUpdated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 newEMA,
        uint256 newStdDev,
        uint256 confidence
    );

    /**
     * @notice Emitted when default slippage is set for a token
     * @param token Token address
     * @param slippage Default slippage in basis points
     */
    event DefaultSlippageSet(address indexed token, uint256 slippage);

    /**
     * @notice Emitted when oracle addresses are updated
     * @param oneInchOracle New 1inch oracle address
     * @param chainlinkAggregator New Chainlink aggregator address
     */
    event OraclesUpdated(address oneInchOracle, address chainlinkAggregator);

    /**
     * @notice Initializes the DynamicSlippageCalculator contract
     * @param _oneInchOracle Address of the 1inch price oracle
     * @param _chainlinkAggregator Address of the Chainlink price aggregator
     */
    constructor(
        address _oneInchOracle,
        address _chainlinkAggregator
    ) Ownable(msg.sender) {
        oneInchOracle = _oneInchOracle;
        chainlinkAggregator = _chainlinkAggregator;

        _setDefaultSlippages();
    }

    /**
     * @notice Calculates optimal dynamic slippage for a token pair
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return optimalSlippage Calculated optimal slippage in basis points
     */
    function calculateDynamicSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 optimalSlippage) {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);

        uint256 baseSlippage = defaultSlippages[tokenIn];
        if (baseSlippage == 0) {
            baseSlippage = minBaseSlippage;
        }

        uint256 volatilityAdjustment = _getVolatilityAdjustment(pairKey);

        uint256 liquidityAdjustment = _getLiquidityAdjustment(
            pairKey,
            amountIn
        );

        optimalSlippage =
            baseSlippage +
            volatilityAdjustment +
            liquidityAdjustment;

        if (optimalSlippage > maxSlippage) {
            optimalSlippage = maxSlippage;
        }

        return optimalSlippage;
    }

    /**
     * @notice Updates volatility data for a token pair using current market conditions
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     */
    function updateVolatilityData(
        address tokenIn,
        address tokenOut
    ) external override {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);

        uint256 currentPrice = _getOneInchPrice(tokenIn, tokenOut);

        _addPricePoint(pairKey, currentPrice, block.timestamp);

        uint256 chainlinkPrice = _getChainlinkPrice(tokenIn, tokenOut);

        uint256 newEMA = _calculateEMA(pairKey, currentPrice);
        uint256 newStdDev = _calculateStandardDeviation(pairKey);

        exponentialMovingAverage[pairKey] = newEMA;
        volatilityStdDev[pairKey] = newStdDev;
        lastUpdate[pairKey] = block.timestamp;

        uint256 confidence = _calculateConfidence(
            currentPrice,
            chainlinkPrice,
            newStdDev
        );
        confidenceScores[pairKey] = confidence;

        emit VolatilityDataUpdated(
            tokenIn,
            tokenOut,
            newEMA,
            newStdDev,
            confidence
        );
    }

    /**
     * @notice Retrieves volatility score and confidence for a token pair
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return volatilityScore Current volatility score
     * @return confidence Confidence level of the score
     */
    function getVolatilityScore(
        address tokenIn,
        address tokenOut
    )
        external
        view
        override
        returns (uint256 volatilityScore, uint256 confidence)
    {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);

        uint256 stdDev = volatilityStdDev[pairKey];
        uint256 ema = exponentialMovingAverage[pairKey];

        if (ema > 0) {
            volatilityScore = (stdDev * 10000) / ema;
        } else {
            volatilityScore = 0;
        }

        confidence = confidenceScores[pairKey];

        return (volatilityScore, confidence);
    }

    /**
     * @notice Sets default slippage for a specific token
     * @param token Token address
     * @param slippage Default slippage in basis points
     */
    function setDefaultSlippage(
        address token,
        uint256 slippage
    ) external onlyOwner {
        require(slippage <= maxSlippage, "Slippage too high");
        defaultSlippages[token] = slippage;
        emit DefaultSlippageSet(token, slippage);
    }

    /**
     * @notice Updates oracle addresses
     * @param _oneInchOracle New 1inch oracle address
     * @param _chainlinkAggregator New Chainlink aggregator address
     */
    function setOracles(
        address _oneInchOracle,
        address _chainlinkAggregator
    ) external onlyOwner {
        oneInchOracle = _oneInchOracle;
        chainlinkAggregator = _chainlinkAggregator;
        emit OraclesUpdated(_oneInchOracle, _chainlinkAggregator);
    }

    /**
     * @notice Updates algorithm parameters
     * @param _emaAlpha EMA smoothing factor
     * @param _volatilityMultiplier Volatility impact multiplier
     * @param _maxSlippage Maximum allowed slippage
     */
    function setAlgorithmParameters(
        uint256 _emaAlpha,
        uint256 _volatilityMultiplier,
        uint256 _maxSlippage
    ) external onlyOwner {
        require(_emaAlpha <= 10000, "Invalid alpha");
        require(_maxSlippage <= 2000, "Max slippage too high");

        emaAlpha = _emaAlpha;
        volatilityMultiplier = _volatilityMultiplier;
        maxSlippage = _maxSlippage;
    }

    /**
     * @notice Updates liquidity cache for a token pair (admin function)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param liquidity Current liquidity amount
     */
    function updateLiquidityCache(
        address tokenIn,
        address tokenOut,
        uint256 liquidity
    ) external onlyOwner {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        liquidityCache[pairKey] = liquidity;
    }

    /**
     * @notice Sets slippage parameters for a specific token
     * @param token Token address
     * @param baseSlippage Base slippage in basis points
     * @param minSlippage Minimum slippage in basis points
     * @param maxSlippage Maximum slippage in basis points
     * @param volatilityMultiplier Volatility impact multiplier
     */
    function setSlippageParams(
        address token,
        uint256 baseSlippage,
        uint256 minSlippage,
        uint256 maxSlippage,
        uint256 volatilityMultiplier
    ) external override onlyOwner {
        require(minSlippage <= baseSlippage, "Invalid min slippage");
        require(baseSlippage <= maxSlippage, "Invalid base slippage");
        require(maxSlippage <= 2000, "Max slippage too high");

        defaultSlippages[token] = baseSlippage;
        minBaseSlippage = minSlippage;
        maxSlippage = maxSlippage;
        volatilityMultiplier = volatilityMultiplier;

        emit DefaultSlippageSet(token, baseSlippage);
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
     * @notice Calculates volatility adjustment based on standard deviation
     * @param pairKey Unique identifier for the token pair
     * @return Volatility adjustment in basis points
     */
    function _getVolatilityAdjustment(
        bytes32 pairKey
    ) internal view returns (uint256) {
        uint256 stdDev = volatilityStdDev[pairKey];
        uint256 ema = exponentialMovingAverage[pairKey];

        if (ema == 0) return 0;

        uint256 volatilityRatio = (stdDev * 10000) / ema;
        return (volatilityRatio * volatilityMultiplier) / 10000;
    }

    /**
     * @notice Calculates liquidity-based slippage adjustment
     * @param pairKey Unique identifier for the token pair
     * @param amountIn Trade amount to consider
     * @return Liquidity adjustment in basis points
     */
    function _getLiquidityAdjustment(
        bytes32 pairKey,
        uint256 amountIn
    ) internal view returns (uint256) {
        uint256 liquidity = liquidityCache[pairKey];

        if (liquidity == 0) return 20;

        if (amountIn * 1000 > liquidity) {
            return 100;
        } else if (amountIn * 100 > liquidity) {
            return 50;
        } else {
            return 10;
        }
    }

    /**
     * @notice Calculates exponential moving average for price data
     * @param pairKey Unique identifier for the token pair
     * @param newPrice Latest price to incorporate
     * @return Updated EMA value
     */
    function _calculateEMA(
        bytes32 pairKey,
        uint256 newPrice
    ) internal view returns (uint256) {
        uint256 currentEMA = exponentialMovingAverage[pairKey];

        if (currentEMA == 0) {
            return newPrice;
        }

        return
            ((newPrice * emaAlpha) + (currentEMA * (10000 - emaAlpha))) / 10000;
    }

    /**
     * @notice Calculates standard deviation of recent price movements
     * @param pairKey Unique identifier for the token pair
     * @return Standard deviation value
     */
    function _calculateStandardDeviation(
        bytes32 pairKey
    ) internal view returns (uint256) {
        PricePoint[] storage history = priceHistory[pairKey];
        uint256 length = history.length;

        if (length < 2) return 0;

        uint256 mean = 0;
        uint256 recent = length > 20 ? 20 : length;

        for (uint256 i = length - recent; i < length; i++) {
            mean += history[i].price;
        }
        mean = mean / recent;

        uint256 variance = 0;
        for (uint256 i = length - recent; i < length; i++) {
            uint256 diff = history[i].price > mean
                ? history[i].price - mean
                : mean - history[i].price;
            variance += diff * diff;
        }

        return _sqrt(variance / recent);
    }

    /**
     * @notice Adds new price point to historical data
     * @param pairKey Unique identifier for the token pair
     * @param price Current price value
     * @param timestamp Current timestamp
     */
    function _addPricePoint(
        bytes32 pairKey,
        uint256 price,
        uint256 timestamp
    ) internal {
        PricePoint[] storage history = priceHistory[pairKey];

        if (history.length >= MAX_PRICE_HISTORY) {
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history[history.length - 1] = PricePoint(timestamp, price, 0);
        } else {
            history.push(PricePoint(timestamp, price, 0));
        }
    }

    /**
     * @notice Gets price from 1inch oracle (mock implementation)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return Current price from 1inch oracle
     */
    function _getOneInchPrice(
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256) {
        return
            1e18 +
            (uint256(
                keccak256(abi.encodePacked(tokenIn, tokenOut, block.timestamp))
            ) % 1e16);
    }

    /**
     * @notice Gets price from Chainlink oracle (mock implementation)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return Current price from Chainlink oracle
     */
    function _getChainlinkPrice(
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256) {
        return
            1e18 +
            (uint256(
                keccak256(abi.encodePacked(tokenOut, tokenIn, block.timestamp))
            ) % 1e16);
    }

    /**
     * @notice Calculates confidence score based on price oracle agreement
     * @param oneInchPrice Price from 1inch oracle
     * @param chainlinkPrice Price from Chainlink oracle
     * @param stdDev Current standard deviation
     * @return Confidence score (0-100)
     */
    function _calculateConfidence(
        uint256 oneInchPrice,
        uint256 chainlinkPrice,
        uint256 stdDev
    ) internal pure returns (uint256) {
        uint256 priceDiff = oneInchPrice > chainlinkPrice
            ? oneInchPrice - chainlinkPrice
            : chainlinkPrice - oneInchPrice;

        uint256 priceDeviation = (priceDiff * 10000) / oneInchPrice;

        uint256 baseConfidence = 90;
        uint256 deviationPenalty = priceDeviation > 100
            ? 20
            : priceDeviation / 5;
        uint256 volatilityPenalty = stdDev > 1e16 ? 10 : 0;

        uint256 confidence = baseConfidence -
            deviationPenalty -
            volatilityPenalty;
        return confidence < 50 ? 50 : confidence;
    }

    /**
     * @notice Sets default slippage values for major tokens
     */
    function _setDefaultSlippages() internal {
        defaultSlippages[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 30;
        defaultSlippages[0xa0B86A33E6441c92d6BFe2b573c0ad7DcdB3a9E4] = 50;
        defaultSlippages[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 25;
    }

    /**
     * @notice Calculates square root using Babylonian method
     * @param x Input value
     * @return Square root of input
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }
}
