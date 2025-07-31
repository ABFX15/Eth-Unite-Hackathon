// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface I1inchPriceOracle {
    function getRate(
        address srcToken,
        address dstToken,
        bool useWrappers
    ) external view returns (uint256 weightedRate);
}

interface IAggregatorV3 {
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

interface IDEXAggregator {
    function getPoolVolatility(
        address tokenA,
        address tokenB
    ) external view returns (uint256 volatility);
}

contract VolatilityProxy is Ownable {
    struct PriceDataPoint {
        uint256 price;
        uint256 timestamp;
        uint256 volume;
    }

    struct VolatilityMetrics {
        uint256 priceVolatility; // Price-based volatility (standard deviation)
        uint256 volumeVolatility; // Volume-based volatility
        uint256 spreadVolatility; // Bid-ask spread volatility
        uint256 compositeScore; // Weighted composite volatility score
        uint256 confidence; // Confidence level (0-100)
        uint256 lastUpdate;
    }

    mapping(bytes32 => PriceDataPoint[]) public priceHistory;
    mapping(bytes32 => VolatilityMetrics) public volatilityMetrics;
    mapping(address => address) public chainlinkFeeds;
    mapping(address => bool) public dexAggregators;
    mapping(bytes32 => uint256) public priceHistoryIndex; // Current index for circular buffer

    I1inchPriceOracle public oneInchOracle;

    // Configuration parameters
    uint256 constant PRICE_HISTORY_SIZE = 288; // 24 hours at 5-minute intervals
    uint256 constant MIN_DATA_POINTS = 12; // Minimum points for volatility calculation
    uint256 constant VOLATILITY_WINDOW = 86400; // 24 hours
    uint256 constant UPDATE_THRESHOLD = 300; // 5 minutes

    // Volatility weights (total = 100)
    uint256 constant PRICE_WEIGHT = 50;
    uint256 constant VOLUME_WEIGHT = 30;
    uint256 constant SPREAD_WEIGHT = 20;

    event VolatilityUpdated(
        address indexed tokenA,
        address indexed tokenB,
        uint256 volatility,
        uint256 confidence
    );

    event PriceDataAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 price,
        uint256 timestamp
    );

    constructor(address _oneInchOracle) Ownable(msg.sender) {
        oneInchOracle = I1inchPriceOracle(_oneInchOracle);
    }

    function getVolatility(
        address tokenA,
        address tokenB
    ) external view returns (uint256) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        VolatilityMetrics memory metrics = volatilityMetrics[pairKey];

        // Return cached volatility if recently updated
        if (block.timestamp - metrics.lastUpdate < UPDATE_THRESHOLD) {
            return metrics.compositeScore;
        }

        // Calculate real-time volatility
        return _calculateRealTimeVolatility(tokenA, tokenB);
    }

    function updateVolatilityData(address tokenA, address tokenB) external {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);

        // Get current price from 1inch oracle
        uint256 currentPrice = oneInchOracle.getRate(tokenA, tokenB, true);
        require(currentPrice > 0, "Invalid price");

        // Add to price history
        _addPriceDataPoint(pairKey, currentPrice, block.timestamp, 0);

        // Calculate new volatility metrics
        VolatilityMetrics memory newMetrics = _calculateVolatilityMetrics(
            pairKey
        );
        volatilityMetrics[pairKey] = newMetrics;

        emit VolatilityUpdated(
            tokenA,
            tokenB,
            newMetrics.compositeScore,
            newMetrics.confidence
        );
        emit PriceDataAdded(tokenA, tokenB, currentPrice, block.timestamp);
    }

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
        )
    {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        VolatilityMetrics memory metrics = volatilityMetrics[pairKey];

        return (
            metrics.priceVolatility,
            metrics.volumeVolatility,
            metrics.spreadVolatility,
            metrics.compositeScore,
            metrics.confidence
        );
    }

    function _calculateRealTimeVolatility(
        address tokenA,
        address tokenB
    ) internal view returns (uint256) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        PriceDataPoint[] memory history = priceHistory[pairKey];

        if (history.length < MIN_DATA_POINTS) {
            return 500; // Default 5% volatility for insufficient data
        }

        // Calculate price volatility (standard deviation)
        uint256 priceVol = _calculatePriceVolatility(history);

        // Get spread volatility from multiple DEXs
        uint256 spreadVol = _getSpreadVolatility(tokenA, tokenB);

        // Combine metrics with weights
        uint256 composite = (priceVol *
            PRICE_WEIGHT +
            spreadVol *
            SPREAD_WEIGHT) / 100;

        // Cap at reasonable bounds (0.1% to 20%)
        if (composite < 10) composite = 10;
        if (composite > 2000) composite = 2000;

        return composite;
    }

    function _calculateVolatilityMetrics(
        bytes32 pairKey
    ) internal view returns (VolatilityMetrics memory) {
        PriceDataPoint[] memory history = priceHistory[pairKey];

        if (history.length < MIN_DATA_POINTS) {
            return
                VolatilityMetrics({
                    priceVolatility: 500,
                    volumeVolatility: 0,
                    spreadVolatility: 0,
                    compositeScore: 500,
                    confidence: 20, // Low confidence
                    lastUpdate: block.timestamp
                });
        }

        uint256 priceVol = _calculatePriceVolatility(history);
        uint256 volumeVol = _calculateVolumeVolatility(history);
        uint256 spreadVol = 0; // TODO: Implement spread volatility

        uint256 composite = (priceVol *
            PRICE_WEIGHT +
            volumeVol *
            VOLUME_WEIGHT +
            spreadVol *
            SPREAD_WEIGHT) / 100;

        uint256 confidence = _calculateConfidence(
            history.length,
            block.timestamp - history[0].timestamp
        );

        return
            VolatilityMetrics({
                priceVolatility: priceVol,
                volumeVolatility: volumeVol,
                spreadVolatility: spreadVol,
                compositeScore: composite,
                confidence: confidence,
                lastUpdate: block.timestamp
            });
    }

    function _calculatePriceVolatility(
        PriceDataPoint[] memory history
    ) internal pure returns (uint256) {
        if (history.length < 2) return 0;

        // Calculate mean price
        uint256 sum = 0;
        uint256 count = 0;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].timestamp > 0) {
                sum += history[i].price;
                count++;
            }
        }

        if (count == 0) return 0;
        uint256 mean = sum / count;

        // Calculate variance
        uint256 variance = 0;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].timestamp > 0) {
                uint256 diff = history[i].price > mean
                    ? history[i].price - mean
                    : mean - history[i].price;
                variance += (diff * diff) / mean; // Relative variance
            }
        }
        variance = variance / count;

        // Return standard deviation as basis points
        return _sqrt(variance);
    }

    function _calculateVolumeVolatility(
        PriceDataPoint[] memory history
    ) internal pure returns (uint256) {
        if (history.length < 2) return 0;

        // Calculate mean volume
        uint256 sum = 0;
        uint256 count = 0;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].timestamp > 0 && history[i].volume > 0) {
                sum += history[i].volume;
                count++;
            }
        }

        if (count == 0) return 0;
        uint256 mean = sum / count;

        // Calculate volume variance
        uint256 variance = 0;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].timestamp > 0 && history[i].volume > 0) {
                uint256 diff = history[i].volume > mean
                    ? history[i].volume - mean
                    : mean - history[i].volume;
                variance += (diff * diff * 10000) / (mean * mean); // Relative variance in basis points
            }
        }

        if (count == 0) return 0;
        variance = variance / count;

        // Return standard deviation as basis points
        return _sqrt(variance);
    }

    function _getSpreadVolatility(
        address tokenA,
        address tokenB
    ) internal view returns (uint256) {
        // Get spread data from multiple DEX aggregators
        uint256 totalSpread = 0;
        uint256 sourceCount = 0;

        // Simple implementation: use price difference as proxy for spread
        uint256 oneInchRate = oneInchOracle.getRate(tokenA, tokenB, true);
        if (oneInchRate == 0) return 100; // Default spread volatility

        // Check if we have Chainlink data for comparison
        address feedA = chainlinkFeeds[tokenA];
        address feedB = chainlinkFeeds[tokenB];

        if (feedA != address(0) && feedB != address(0)) {
            try IAggregatorV3(feedA).latestRoundData() returns (
                uint80,
                int256 priceA,
                uint256,
                uint256 updatedAtA,
                uint80
            ) {
                try IAggregatorV3(feedB).latestRoundData() returns (
                    uint80,
                    int256 priceB,
                    uint256,
                    uint256 updatedAtB,
                    uint80
                ) {
                    // Check data freshness (within 1 hour)
                    if (
                        block.timestamp - updatedAtA <= 3600 &&
                        block.timestamp - updatedAtB <= 3600 &&
                        priceA > 0 &&
                        priceB > 0
                    ) {
                        uint256 chainlinkRate = (uint256(priceA) * 1e18) /
                            uint256(priceB);

                        // Calculate spread as difference between oracle rates
                        uint256 spread = oneInchRate > chainlinkRate
                            ? oneInchRate - chainlinkRate
                            : chainlinkRate - oneInchRate;
                        totalSpread += (spread * 10000) / chainlinkRate; // Spread in basis points
                        sourceCount++;
                    }
                } catch {}
            } catch {}
        }

        // Add more DEX aggregator sources if configured
        for (uint256 i = 0; i < 5; i++) {
            // Check up to 5 DEX aggregators
            address aggregator = _getDEXAggregator(i);
            if (aggregator != address(0) && dexAggregators[aggregator]) {
                try
                    IDEXAggregator(aggregator).getPoolVolatility(tokenA, tokenB)
                returns (uint256 poolVolatility) {
                    totalSpread += poolVolatility;
                    sourceCount++;
                } catch {}
            }
        }

        if (sourceCount == 0) return 50; // Default spread volatility

        return totalSpread / sourceCount;
    }

    function _getDEXAggregator(uint256 index) internal pure returns (address) {
        // Return different DEX aggregator addresses based on index
        // This would be configured with real DEX aggregator addresses
        if (index == 0) return 0x1111111254fb6c44bAC0beD2854e76F90643097d; // 1inch
        if (index == 1) return 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3
        if (index == 2) return 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2
        if (index == 3) return 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // SushiSwap
        return address(0);
    }

    function _calculateConfidence(
        uint256 dataPoints,
        uint256 timeSpan
    ) internal pure returns (uint256) {
        // Confidence based on data quantity and recency
        uint256 dataConfidence = dataPoints >= PRICE_HISTORY_SIZE
            ? 100
            : (dataPoints * 100) / PRICE_HISTORY_SIZE;
        uint256 timeConfidence = timeSpan >= VOLATILITY_WINDOW
            ? 100
            : (timeSpan * 100) / VOLATILITY_WINDOW;

        return (dataConfidence + timeConfidence) / 2;
    }

    function _addPriceDataPoint(
        bytes32 pairKey,
        uint256 price,
        uint256 timestamp,
        uint256 volume
    ) internal {
        PriceDataPoint[] storage history = priceHistory[pairKey];
        uint256 index = priceHistoryIndex[pairKey];

        if (history.length < PRICE_HISTORY_SIZE) {
            history.push(
                PriceDataPoint({
                    price: price,
                    timestamp: timestamp,
                    volume: volume
                })
            );
        } else {
            // Circular buffer - overwrite oldest data
            history[index] = PriceDataPoint({
                price: price,
                timestamp: timestamp,
                volume: volume
            });
            priceHistoryIndex[pairKey] = (index + 1) % PRICE_HISTORY_SIZE;
        }
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

    // Admin functions
    function setChainlinkFeed(address token, address feed) external onlyOwner {
        chainlinkFeeds[token] = feed;
    }

    function addDEXAggregator(address aggregator) external onlyOwner {
        dexAggregators[aggregator] = true;
    }

    function removeDEXAggregator(address aggregator) external onlyOwner {
        dexAggregators[aggregator] = false;
    }

    // View functions
    function getPriceHistory(
        address tokenA,
        address tokenB
    ) external view returns (PriceDataPoint[] memory) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        return priceHistory[pairKey];
    }

    function getLatestPrice(
        address tokenA,
        address tokenB
    ) external view returns (uint256 price, uint256 timestamp) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        PriceDataPoint[] memory history = priceHistory[pairKey];

        if (history.length == 0) return (0, 0);

        uint256 latestIndex = priceHistoryIndex[pairKey];
        if (latestIndex > 0) latestIndex--;
        else latestIndex = history.length - 1;

        return (history[latestIndex].price, history[latestIndex].timestamp);
    }
}
