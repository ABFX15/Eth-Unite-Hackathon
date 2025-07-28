// SPDX-License-identifier: MIT

pragma solidity 0.8.20;

interface IDynamicSlippageCalculator {
    function calculateDynamicSlippage(
        address tokenA,
        address tokenB,
        uint256 orderSize
    ) external view returns (uint256 optimalSlippage);

    function getVolatilityScore(
        address tokenA,
        address tokenB
    ) external view returns (uint256 score, uint256 confidence);
}