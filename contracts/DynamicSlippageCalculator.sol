// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IVolatilitySource {
    function getVolatility(
        address tokenA,
        address tokenB
    ) external view returns (uint256 volatility, uint256 confidence);
}

interface I1inchPriceOracle {
    function getRate(
        address srcToken,
        address dstToken,
        bool useWrappers
    ) external view returns (uint256 weightedRate);
}

interface IChainlinkAggregator {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract DynamicSlippageCalculator is Ownable {
    struct VolatilityData {
        uint256 shortTermMA; // 5-minute moving average
        uint256 mediumTermMA; // 1-hour moving average
        uint256 longTermMA; // 24-hour moving average
        uint256 lastUpdate;
        uint256 priceDeviation; // Standard deviation
        uint256 volatilityScore; // Composite volatility score (0-10000 basis points)
    }

    struct SlippageParams {
        uint256 baseSlippage; // Base slippage in basis points (e.g., 50 = 0.5%)
        uint256 minSlippage; // Minimum allowed slippage
        uint256 maxSlippage; // Maximum allowed slippage
        uint256 volatilityMultiplier; // How much volatility affects slippage
        uint256 liquidityAdjustment; // Adjustment based on liquidity depth
    }

    struct PricePoint {
        uint256 price;
        uint256 timestamp;
        uint256 volume;
    }

    mapping(bytes32 => VolatilityData) public volatilityData;
    mapping(address => SlippageParams) public tokenSlippageParams;
    mapping(address => address) public chainlinkFeeds;
    mapping(address => bool) public volatilitySources;
    mapping(bytes32 => PricePoint[]) public priceHistory;
    mapping(bytes32 => uint256) public liquidityCache;

    I1inchPriceOracle public priceOracle;

    // Volatility calculation parameters
    uint256 constant VOLATILITY_WINDOW = 300; // 5 minutes
    uint256 constant HIGH_VOLATILITY_THRESHOLD = 500; // 5%
    uint256 constant EXTREME_VOLATILITY_THRESHOLD = 1000; // 10%
    uint256 constant PRICE_HISTORY_LENGTH = 100;
    uint256 constant LIQUIDITY_CACHE_TTL = 600; // 10 minutes

    // Slippage bounds
    uint256 constant MIN_SLIPPAGE = 10; // 0.1%
    uint256 constant MAX_SLIPPAGE = 500; // 5%
    uint256 constant DEFAULT_BASE_SLIPPAGE = 50; // 0.5%

    event VolatilityUpdated(
        address indexed tokenA,
        address indexed tokenB,
        uint256 volatility,
        uint256 confidence
    );

    event SlippageCalculated(
        address indexed token,
        uint256 baseSlippage,
        uint256 dynamicSlippage,
        uint256 volatilityScore
    );

    constructor(address _priceOracle) Ownable(msg.sender) {
        priceOracle = I1inchPriceOracle(_priceOracle);
        _setDefaultSlippageParams();
    }

    function calculateDynamicSlippage(
        address tokenA,
        address tokenB,
        uint256 orderSize
    ) external view returns (uint256 optimalSlippage) {
        // 1. Get current volatility from multiple sources
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        VolatilityData memory volData = volatilityData[pairKey];
        SlippageParams memory params = tokenSlippageParams[tokenA];

        if (params.baseSlippage == 0) {
            params.baseSlippage = DEFAULT_BASE_SLIPPAGE;
        }

        // 2. Calculate liquidity-adjusted volatility
        uint256 liquidityAdjustment = _calculateLiquidityAdjustment(
            tokenA,
            tokenB,
            orderSize
        );

        // 3. Apply volatility multiplier to base slippage
        uint256 volatilityAdjustment = (volData.volatilityScore *
            params.volatilityMultiplier) / 10000;

        // 4. Combine base slippage + volatility + liquidity adjustments
        optimalSlippage =
            params.baseSlippage +
            volatilityAdjustment +
            liquidityAdjustment;

        // 5. Ensure slippage is within bounds
        if (optimalSlippage < params.minSlippage || params.minSlippage == 0)
            optimalSlippage = params.minSlippage == 0
                ? MIN_SLIPPAGE
                : params.minSlippage;
        if (optimalSlippage > params.maxSlippage || params.maxSlippage == 0)
            optimalSlippage = params.maxSlippage == 0
                ? MAX_SLIPPAGE
                : params.maxSlippage;

        return optimalSlippage;
    }

    function updateVolatilityData(address tokenA, address tokenB) external {
        // 1. Get current price from 1inch oracle
        uint256 currentPrice = priceOracle.getRate(tokenA, tokenB, true);
        require(currentPrice > 0, "Invalid price from oracle");

        bytes32 pairKey = _getPairKey(tokenA, tokenB);

        // 2. Add to price history (CEI: Effects before Interactions)
        _addPricePoint(pairKey, currentPrice, block.timestamp, 0);

        // 3. Get Chainlink price if available
        uint256 chainlinkPrice = _getChainlinkPrice(tokenA, tokenB);

        // 4. Calculate volatility metrics
        VolatilityData memory newVolData = _calculateVolatilityMetrics(
            pairKey,
            currentPrice,
            chainlinkPrice
        );

        // 5. Update state (CEI: Effects)
        volatilityData[pairKey] = newVolData;

        emit VolatilityUpdated(
            tokenA,
            tokenB,
            newVolData.volatilityScore,
            80 // Default confidence
        );
    }

    function getVolatilityScore(
        address tokenA,
        address tokenB
    ) external view returns (uint256 score, uint256 confidence) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        VolatilityData memory volData = volatilityData[pairKey];

        // Calculate composite volatility score from multiple sources
        uint256 compositeScore = volData.volatilityScore;

        // Get additional confidence from data recency and quality
        uint256 dataAge = block.timestamp - volData.lastUpdate;
        if (dataAge > 3600) {
            // 1 hour old
            confidence = 30; // Low confidence
        } else if (dataAge > 600) {
            // 10 minutes old
            confidence = 60; // Medium confidence
        } else {
            confidence = 90; // High confidence
        }

        // Adjust confidence based on available data sources
        if (
            chainlinkFeeds[tokenA] != address(0) &&
            chainlinkFeeds[tokenB] != address(0)
        ) {
            confidence += 10; // Bonus for Chainlink data
        }

        return (compositeScore, confidence);
    }

    function _calculateVolatilityMetrics(
        bytes32 pairKey,
        uint256 currentPrice,
        uint256 chainlinkPrice
    ) internal view returns (VolatilityData memory) {
        PricePoint[] memory history = priceHistory[pairKey];

        if (history.length < 3) {
            return
                VolatilityData({
                    shortTermMA: currentPrice,
                    mediumTermMA: currentPrice,
                    longTermMA: currentPrice,
                    lastUpdate: block.timestamp,
                    priceDeviation: DEFAULT_BASE_SLIPPAGE,
                    volatilityScore: DEFAULT_BASE_SLIPPAGE
                });
        }

        // Calculate moving averages
        uint256 shortTermMA = _calculateMovingAverage(
            currentPrice,
            volatilityData[pairKey].shortTermMA,
            5
        );
        uint256 mediumTermMA = _calculateMovingAverage(
            currentPrice,
            volatilityData[pairKey].mediumTermMA,
            12
        );
        uint256 longTermMA = _calculateMovingAverage(
            currentPrice,
            volatilityData[pairKey].longTermMA,
            24
        );

        // Calculate price deviation (standard deviation)
        uint256[] memory recentPrices = _getRecentPrices(history, 20);
        uint256 priceDeviation = _calculatePriceDeviation(recentPrices);

        // Calculate composite volatility score
        uint256 volatilityScore = _calculateCompositeVolatility(
            shortTermMA,
            mediumTermMA,
            longTermMA,
            priceDeviation,
            currentPrice,
            chainlinkPrice
        );

        return
            VolatilityData({
                shortTermMA: shortTermMA,
                mediumTermMA: mediumTermMA,
                longTermMA: longTermMA,
                lastUpdate: block.timestamp,
                priceDeviation: priceDeviation,
                volatilityScore: volatilityScore
            });
    }

    function _calculateMovingAverage(
        uint256 currentPrice,
        uint256 previousMA,
        uint256 periods
    ) internal pure returns (uint256) {
        // Exponential Moving Average (EMA)
        // EMA = (currentPrice * 2 / (periods + 1)) + (previousMA * (1 - 2 / (periods + 1)))
        if (previousMA == 0) return currentPrice;

        uint256 multiplier = (2 * 10000) / (periods + 1); // Scale by 10000
        uint256 emaComponent = (currentPrice * multiplier) / 10000;
        uint256 previousComponent = (previousMA * (10000 - multiplier)) / 10000;

        return emaComponent + previousComponent;
    }

    function _calculatePriceDeviation(
        uint256[] memory prices
    ) internal pure returns (uint256 deviation) {
        if (prices.length < 2) return 0;

        // Calculate mean
        uint256 sum = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            sum += prices[i];
        }
        uint256 mean = sum / prices.length;

        // Calculate variance
        uint256 variance = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            uint256 diff = prices[i] > mean
                ? prices[i] - mean
                : mean - prices[i];
            variance += (diff * diff * 10000) / (mean * mean); // Relative variance in basis points
        }
        variance = variance / prices.length;

        // Return standard deviation in basis points
        return _sqrt(variance);
    }

    function _calculateCompositeVolatility(
        uint256 shortTermMA,
        uint256 mediumTermMA,
        uint256 longTermMA,
        uint256 priceDeviation,
        uint256 currentPrice,
        uint256 chainlinkPrice
    ) internal pure returns (uint256) {
        // Calculate trend volatility (MA divergence)
        uint256 trendVolatility = 0;
        if (shortTermMA > 0 && mediumTermMA > 0) {
            uint256 shortMedDiff = shortTermMA > mediumTermMA
                ? shortTermMA - mediumTermMA
                : mediumTermMA - shortTermMA;
            trendVolatility = (shortMedDiff * 10000) / mediumTermMA;
        }

        // Calculate oracle divergence if Chainlink available
        uint256 oracleDivergence = 0;
        if (chainlinkPrice > 0 && currentPrice > 0) {
            uint256 priceDiff = currentPrice > chainlinkPrice
                ? currentPrice - chainlinkPrice
                : chainlinkPrice - currentPrice;
            oracleDivergence = (priceDiff * 10000) / chainlinkPrice;
        }

        // Weighted composite score
        uint256 composite = (priceDeviation *
            40 +
            trendVolatility *
            35 +
            oracleDivergence *
            25) / 100;

        // Cap at reasonable bounds
        if (composite < 10) composite = 10;
        if (composite > 2000) composite = 2000;

        return composite;
    }

    function _calculateLiquidityAdjustment(
        address tokenA,
        address tokenB,
        uint256 orderSize
    ) internal view returns (uint256) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        uint256 cachedLiquidity = liquidityCache[pairKey];

        // Simple liquidity adjustment based on order size
        if (cachedLiquidity == 0) return 0;

        // Larger orders relative to liquidity need higher slippage
        uint256 liquidityRatio = (orderSize * 10000) / cachedLiquidity;

        if (liquidityRatio > 1000) return 100; // 1% extra for very large orders
        if (liquidityRatio > 500) return 50; // 0.5% extra for large orders
        if (liquidityRatio > 100) return 25; // 0.25% extra for medium orders

        return 0; // No adjustment for small orders
    }

    function _getChainlinkPrice(
        address tokenA,
        address tokenB
    ) internal view returns (uint256) {
        address feedA = chainlinkFeeds[tokenA];
        address feedB = chainlinkFeeds[tokenB];

        if (feedA == address(0) || feedB == address(0)) return 0;

        try IChainlinkAggregator(feedA).latestRoundData() returns (
            uint80,
            int256 priceA,
            uint256,
            uint256 updatedAtA,
            uint80
        ) {
            try IChainlinkAggregator(feedB).latestRoundData() returns (
                uint80,
                int256 priceB,
                uint256,
                uint256 updatedAtB,
                uint80
            ) {
                // Check data freshness (within 1 hour)
                if (
                    block.timestamp - updatedAtA > 3600 ||
                    block.timestamp - updatedAtB > 3600
                ) return 0;

                if (priceA > 0 && priceB > 0) {
                    return (uint256(priceA) * 1e18) / uint256(priceB);
                }
            } catch {}
        } catch {}

        return 0;
    }

    function _addPricePoint(
        bytes32 pairKey,
        uint256 price,
        uint256 timestamp,
        uint256 volume
    ) internal {
        PricePoint[] storage history = priceHistory[pairKey];

        if (history.length >= PRICE_HISTORY_LENGTH) {
            // Remove oldest entry (shift array)
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history[history.length - 1] = PricePoint(price, timestamp, volume);
        } else {
            history.push(PricePoint(price, timestamp, volume));
        }
    }

    function _getRecentPrices(
        PricePoint[] memory history,
        uint256 count
    ) internal pure returns (uint256[] memory) {
        uint256 length = history.length > count ? count : history.length;
        uint256[] memory prices = new uint256[](length);

        uint256 startIndex = history.length > count
            ? history.length - count
            : 0;
        for (uint256 i = 0; i < length; i++) {
            prices[i] = history[startIndex + i].price;
        }

        return prices;
    }

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

    function _setDefaultSlippageParams() internal {
        // Set reasonable defaults for different token types
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH
        address USDC = 0xa0b86A33E6441b59205ede8DdA1dcf51E9a7bCed; // Mainnet USDC
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // Mainnet USDT

        // ETH: Lower volatility, tighter slippage
        tokenSlippageParams[WETH] = SlippageParams({
            baseSlippage: 30,
            minSlippage: 10,
            maxSlippage: 200,
            volatilityMultiplier: 200,
            liquidityAdjustment: 0
        });

        // Stablecoins: Very low volatility, minimal slippage
        tokenSlippageParams[USDC] = SlippageParams({
            baseSlippage: 10,
            minSlippage: 5,
            maxSlippage: 50,
            volatilityMultiplier: 50,
            liquidityAdjustment: 0
        });

        tokenSlippageParams[USDT] = SlippageParams({
            baseSlippage: 10,
            minSlippage: 5,
            maxSlippage: 50,
            volatilityMultiplier: 50,
            liquidityAdjustment: 0
        });
    }

    // Admin functions with proper access control
    function setSlippageParams(
        address token,
        uint256 baseSlippage,
        uint256 minSlippage,
        uint256 maxSlippage,
        uint256 volatilityMultiplier
    ) external onlyOwner {
        require(
            minSlippage <= baseSlippage && baseSlippage <= maxSlippage,
            "Invalid slippage bounds"
        );

        tokenSlippageParams[token] = SlippageParams({
            baseSlippage: baseSlippage,
            minSlippage: minSlippage,
            maxSlippage: maxSlippage,
            volatilityMultiplier: volatilityMultiplier,
            liquidityAdjustment: 0
        });
    }

    function addVolatilitySource(address source) external onlyOwner {
        volatilitySources[source] = true;
    }

    function setChainlinkFeed(address token, address feed) external onlyOwner {
        chainlinkFeeds[token] = feed;
    }

    function updateLiquidityCache(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external onlyOwner {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        liquidityCache[pairKey] = liquidity;
    }

    // View functions for debugging and monitoring
    function getSlippageParams(
        address token
    ) external view returns (SlippageParams memory) {
        return tokenSlippageParams[token];
    }

    function getVolatilityData(
        address tokenA,
        address tokenB
    ) external view returns (VolatilityData memory) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        return volatilityData[pairKey];
    }

    function getPriceHistory(
        address tokenA,
        address tokenB
    ) external view returns (PricePoint[] memory) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        return priceHistory[pairKey];
    }
}
