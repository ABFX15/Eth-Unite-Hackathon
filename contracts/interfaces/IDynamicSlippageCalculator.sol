// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDynamicSlippageCalculator {
    function calculateDynamicSlippage(
        address tokenA,
        address tokenB,
        uint256 orderSize
    ) external view returns (uint256 optimalSlippage);

    function updateVolatilityData(address tokenA, address tokenB) external;

    function getVolatilityScore(
        address tokenA,
        address tokenB
    ) external view returns (uint256 score, uint256 confidence);

    function setSlippageParams(
        address token,
        uint256 baseSlippage,
        uint256 minSlippage,
        uint256 maxSlippage,
        uint256 volatilityMultiplier
    ) external;
}
