// SPDX-License-identifier: MIT

pragma solidity 0.8.20;

interface IAmountGetter {
    function getAmount(
        address token,
        uint256 amount,
        bytes calldata data
    ) external view returns (uint256);
}