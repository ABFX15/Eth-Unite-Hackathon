// SPDX-License-identifier: MIT

pragma solidity 0.8.30;

interface I1inchLimitOrderProtocol {
    struct Order {
        address maker;
        address makerAsset;
        address takerAsset;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 deadline;
        bytes makerAssetData;
        bytes takerAssetData;
    }

    function submitOrder(Order calldata order) external returns (bytes32 orderHash);

    function fillOrder(
        bytes32 orderHash,
        uint256 makingAmount,
        uint256 takingAmount,
        bytes calldata interaction
    ) external;

    function cancelOrder(bytes32 orderHash) external;
}