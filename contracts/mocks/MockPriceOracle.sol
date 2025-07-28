// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract MockPriceOracle {
    mapping(bytes32 => uint256) public prices;

    event PriceUpdated(
        address indexed srcToken,
        address indexed dstToken,
        uint256 rate
    );

    constructor() {
        // Set some default prices for testing
        // USDC/ETH rate (example: 1 ETH = 2000 USDC)
        prices[_getPairKey(address(0x1), address(0x2))] = 2000 * 1e18;
        // ETH/USDC rate
        prices[_getPairKey(address(0x2), address(0x1))] = 1e18 / 2000;
    }

    function getRate(
        address srcToken,
        address dstToken,
        bool /* useWrappers */
    ) external view returns (uint256 weightedRate) {
        bytes32 key = _getPairKey(srcToken, dstToken);
        uint256 rate = prices[key];

        if (rate == 0) {
            // Return default rate for unknown pairs
            return 1e18;
        }

        return rate;
    }

    function setPrice(
        address srcToken,
        address dstToken,
        uint256 rate
    ) external {
        prices[_getPairKey(srcToken, dstToken)] = rate;
        emit PriceUpdated(srcToken, dstToken, rate);
    }

    function _getPairKey(
        address srcToken,
        address dstToken
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(srcToken, dstToken));
    }
}
