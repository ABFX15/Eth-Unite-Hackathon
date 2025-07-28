// SPDX-License-identifier: MIT

pragma solidity 0.8.20;

interface I1inchLimitOrderProtocol {
    function fillOrder(
        bytes32 orderHash,
        uint256 makingAmount,
        uint256 takingAmount,
        bytes calldata interaction
    ) external;

    function cancelOrder(bytes32 orderHash) external;
}