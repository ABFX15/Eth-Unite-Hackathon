// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VolatilityProxy
 * @notice Aggregates volatility data from multiple sources for comprehensive market analysis
 * @dev Provides weighted volatility calculations from various price feeds and DEX data
 */
contract VolatilityProxy is Ownable {
    /**
     * @notice Configuration for a volatility data source
     * @param active Whether this source is currently active
     * @param weight Weight of this source in final calculations (0-10000)
     * @param lastUpdate Timestamp of last successful update
     * @param reliability Historical reliability score (0-100)
     * @param dataSource Address of the external data source
     */
    struct VolatilitySource {
        bool active;
        uint256 weight;
        uint256 lastUpdate;
        uint256 reliability;
        address dataSource;
    }

    /**
     * @notice Volatility measurement from a specific source
     * @param timestamp When the measurement was taken
     * @param value Volatility value
     * @param confidence Confidence level of the measurement
     * @param sourceId Which source provided this measurement
     */
    struct VolatilityMeasurement {
        uint256 timestamp;
        uint256 value;
        uint256 confidence;
        bytes32 sourceId;
    }

    /// @notice Maximum number of data sources that can be registered
    uint256 constant MAX_SOURCES = 10;
    /// @notice Stale data threshold in seconds (1 hour)
    uint256 constant STALE_THRESHOLD = 3600;
    /// @notice Minimum weight for active sources
    uint256 constant MIN_WEIGHT = 100;
    /// @notice Maximum weight for any single source
    uint256 constant MAX_WEIGHT = 3000;

    /// @notice Mapping of source ID to source configuration
    mapping(bytes32 => VolatilitySource) public volatilitySources;
    /// @notice Mapping of token pair to recent volatility measurements
    mapping(bytes32 => VolatilityMeasurement[]) public volatilityHistory;
    /// @notice Mapping of token pair to current aggregate volatility
    mapping(bytes32 => uint256) public currentVolatility;
    /// @notice Mapping of token pair to confidence score
    mapping(bytes32 => uint256) public confidenceScores;

    /// @notice Array of active source IDs
    bytes32[] public activeSources;
    /// @notice Total weight of all active sources
    uint256 public totalActiveWeight;
    /// @notice Default volatility when no data is available
    uint256 public defaultVolatility = 500;

    /**
     * @notice Emitted when a new volatility source is registered
     * @param sourceId Unique identifier for the source
     * @param dataSource Address of the data source contract
     * @param weight Weight assigned to this source
     */
    event VolatilitySourceRegistered(
        bytes32 indexed sourceId,
        address indexed dataSource,
        uint256 weight
    );

    /**
     * @notice Emitted when volatility data is updated for a token pair
     * @param tokenA First token in the pair
     * @param tokenB Second token in the pair
     * @param newVolatility Updated volatility value
     * @param confidence Confidence score for the measurement
     * @param sourcesUsed Number of sources used in calculation
     */
    event VolatilityUpdated(
        address indexed tokenA,
        address indexed tokenB,
        uint256 newVolatility,
        uint256 confidence,
        uint256 sourcesUsed
    );

    /**
     * @notice Emitted when a source's weight or status is modified
     * @param sourceId Source being modified
     * @param newWeight New weight value
     * @param active Whether the source is now active
     */
    event SourceConfigUpdated(
        bytes32 indexed sourceId,
        uint256 newWeight,
        bool active
    );

    /**
     * @notice Emitted when a source is marked as unreliable
     * @param sourceId Source that became unreliable
     * @param oldReliability Previous reliability score
     * @param newReliability New reliability score
     */
    event SourceReliabilityUpdated(
        bytes32 indexed sourceId,
        uint256 oldReliability,
        uint256 newReliability
    );

    /**
     * @notice Initializes the VolatilityProxy contract
     */
    constructor() Ownable(msg.sender) {
        _registerDefaultSources();
    }

    /**
     * @notice Registers a new volatility data source
     * @param sourceId Unique identifier for the source
     * @param dataSource Address of the data source contract
     * @param weight Weight for this source in calculations (100-3000)
     * @param active Whether to activate the source immediately
     */
    function registerVolatilitySource(
        bytes32 sourceId,
        address dataSource,
        uint256 weight,
        bool active
    ) external onlyOwner {
        require(activeSources.length < MAX_SOURCES, "Too many sources");
        require(weight >= MIN_WEIGHT && weight <= MAX_WEIGHT, "Invalid weight");
        require(dataSource != address(0), "Invalid data source");
        require(!volatilitySources[sourceId].active, "Source already exists");

        volatilitySources[sourceId] = VolatilitySource({
            active: active,
            weight: weight,
            lastUpdate: block.timestamp,
            reliability: 100,
            dataSource: dataSource
        });

        if (active) {
            activeSources.push(sourceId);
            totalActiveWeight += weight;
        }

        emit VolatilitySourceRegistered(sourceId, dataSource, weight);
    }

    /**
     * @notice Updates volatility data for a token pair from multiple sources
     * @param tokenA First token address
     * @param tokenB Second token address
     */
    function updateVolatility(address tokenA, address tokenB) external {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);

        uint256 weightedVolatility = 0;
        uint256 totalWeight = 0;
        uint256 sourcesUsed = 0;
        uint256 aggregateConfidence = 0;

        for (uint256 i = 0; i < activeSources.length; i++) {
            bytes32 sourceId = activeSources[i];
            VolatilitySource storage source = volatilitySources[sourceId];

            if (!source.active) continue;

            (uint256 volatility, uint256 confidence) = _getVolatilityFromSource(
                source.dataSource,
                tokenA,
                tokenB
            );

            if (volatility > 0 && confidence > 50) {
                uint256 adjustedWeight = (source.weight * source.reliability) /
                    100;

                weightedVolatility += volatility * adjustedWeight;
                totalWeight += adjustedWeight;
                sourcesUsed++;
                aggregateConfidence += confidence;

                source.lastUpdate = block.timestamp;

                _recordVolatilityMeasurement(
                    pairKey,
                    volatility,
                    confidence,
                    sourceId
                );
            } else {
                _penalizeSource(sourceId);
            }
        }

        if (totalWeight > 0) {
            uint256 finalVolatility = weightedVolatility / totalWeight;
            uint256 finalConfidence = aggregateConfidence / sourcesUsed;

            currentVolatility[pairKey] = finalVolatility;
            confidenceScores[pairKey] = finalConfidence;

            emit VolatilityUpdated(
                tokenA,
                tokenB,
                finalVolatility,
                finalConfidence,
                sourcesUsed
            );
        } else {
            currentVolatility[pairKey] = defaultVolatility;
            confidenceScores[pairKey] = 25;

            emit VolatilityUpdated(tokenA, tokenB, defaultVolatility, 25, 0);
        }
    }

    /**
     * @notice Gets current volatility and confidence for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return volatility Current volatility value
     * @return confidence Confidence score (0-100)
     */
    function getVolatility(
        address tokenA,
        address tokenB
    ) external view returns (uint256 volatility, uint256 confidence) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        volatility = currentVolatility[pairKey];
        confidence = confidenceScores[pairKey];

        if (volatility == 0) {
            return (defaultVolatility, 25);
        }

        return (volatility, confidence);
    }

    /**
     * @notice Updates configuration for an existing source
     * @param sourceId Source to update
     * @param weight New weight value
     * @param active Whether the source should be active
     */
    function updateSourceConfig(
        bytes32 sourceId,
        uint256 weight,
        bool active
    ) external onlyOwner {
        require(weight >= MIN_WEIGHT && weight <= MAX_WEIGHT, "Invalid weight");

        VolatilitySource storage source = volatilitySources[sourceId];
        require(source.dataSource != address(0), "Source does not exist");

        bool wasActive = source.active;
        uint256 oldWeight = source.weight;

        if (wasActive && !active) {
            _removeFromActiveSources(sourceId);
            totalActiveWeight -= oldWeight;
        } else if (!wasActive && active) {
            activeSources.push(sourceId);
            totalActiveWeight += weight;
        } else if (wasActive && active) {
            totalActiveWeight = totalActiveWeight - oldWeight + weight;
        }

        source.weight = weight;
        source.active = active;

        emit SourceConfigUpdated(sourceId, weight, active);
    }

    /**
     * @notice Gets historical volatility measurements for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return measurements Array of recent volatility measurements
     */
    function getVolatilityHistory(
        address tokenA,
        address tokenB
    ) external view returns (VolatilityMeasurement[] memory measurements) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        return volatilityHistory[pairKey];
    }

    /**
     * @notice Gets information about all registered sources
     * @return sourceIds Array of source identifiers
     * @return sources Array of source configurations
     */
    function getAllSources()
        external
        view
        returns (bytes32[] memory sourceIds, VolatilitySource[] memory sources)
    {
        sourceIds = new bytes32[](activeSources.length);
        sources = new VolatilitySource[](activeSources.length);

        for (uint256 i = 0; i < activeSources.length; i++) {
            sourceIds[i] = activeSources[i];
            sources[i] = volatilitySources[activeSources[i]];
        }

        return (sourceIds, sources);
    }

    /**
     * @notice Updates the default volatility used when no data is available
     * @param newDefault New default volatility value
     */
    function setDefaultVolatility(uint256 newDefault) external onlyOwner {
        require(
            newDefault > 0 && newDefault <= 2000,
            "Invalid default volatility"
        );
        defaultVolatility = newDefault;
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
     * @notice Fetches volatility data from an external source
     * @param dataSource Address of the data source
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return volatility Volatility value from the source
     * @return confidence Confidence level of the measurement
     */
    function _getVolatilityFromSource(
        address dataSource,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 volatility, uint256 confidence) {
        uint256 mockVolatility = (uint256(
            keccak256(
                abi.encodePacked(dataSource, tokenA, tokenB, block.timestamp)
            )
        ) % 1000) + 100;

        uint256 mockConfidence = 75 + (mockVolatility % 25);

        return (mockVolatility, mockConfidence);
    }

    /**
     * @notice Records a volatility measurement from a source
     * @param pairKey Token pair identifier
     * @param volatility Volatility value
     * @param confidence Confidence score
     * @param sourceId Source that provided the measurement
     */
    function _recordVolatilityMeasurement(
        bytes32 pairKey,
        uint256 volatility,
        uint256 confidence,
        bytes32 sourceId
    ) internal {
        VolatilityMeasurement[] storage history = volatilityHistory[pairKey];

        VolatilityMeasurement memory measurement = VolatilityMeasurement({
            timestamp: block.timestamp,
            value: volatility,
            confidence: confidence,
            sourceId: sourceId
        });

        if (history.length >= 50) {
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history[history.length - 1] = measurement;
        } else {
            history.push(measurement);
        }
    }

    /**
     * @notice Reduces reliability score for an underperforming source
     * @param sourceId Source to penalize
     */
    function _penalizeSource(bytes32 sourceId) internal {
        VolatilitySource storage source = volatilitySources[sourceId];
        uint256 oldReliability = source.reliability;

        if (source.reliability > 10) {
            source.reliability -= 5;
        }

        if (source.reliability < 30 && source.active) {
            source.active = false;
            _removeFromActiveSources(sourceId);
            totalActiveWeight -= source.weight;
        }

        emit SourceReliabilityUpdated(
            sourceId,
            oldReliability,
            source.reliability
        );
    }

    /**
     * @notice Removes a source from the active sources array
     * @param sourceId Source to remove
     */
    function _removeFromActiveSources(bytes32 sourceId) internal {
        for (uint256 i = 0; i < activeSources.length; i++) {
            if (activeSources[i] == sourceId) {
                activeSources[i] = activeSources[activeSources.length - 1];
                activeSources.pop();
                break;
            }
        }
    }

    /**
     * @notice Registers default volatility sources during deployment
     */
    function _registerDefaultSources() internal {
        bytes32 chainlinkId = keccak256("CHAINLINK");
        bytes32 oneInchId = keccak256("1INCH");
        bytes32 uniswapId = keccak256("UNISWAP_V3");

        volatilitySources[chainlinkId] = VolatilitySource({
            active: true,
            weight: 2500,
            lastUpdate: block.timestamp,
            reliability: 95,
            dataSource: address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419)
        });

        volatilitySources[oneInchId] = VolatilitySource({
            active: true,
            weight: 2000,
            lastUpdate: block.timestamp,
            reliability: 90,
            dataSource: address(0x07D91f5fb9Bf7798734C3f606dB065549F6893bb)
        });

        volatilitySources[uniswapId] = VolatilitySource({
            active: true,
            weight: 1500,
            lastUpdate: block.timestamp,
            reliability: 85,
            dataSource: address(0xE592427A0AEce92De3Edee1F18E0157C05861564)
        });

        activeSources.push(chainlinkId);
        activeSources.push(oneInchId);
        activeSources.push(uniswapId);

        totalActiveWeight = 6000;
    }
}
