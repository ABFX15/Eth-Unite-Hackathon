// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockLimitOrderProtocol {
    using SafeERC20 for IERC20;

    event OrderFilled(
        bytes32 indexed orderHash,
        uint256 makingAmount,
        uint256 takingAmount
    );

    event OrderCancelled(bytes32 indexed orderHash);

    mapping(bytes32 => bool) public cancelled;
    mapping(bytes32 => uint256) public filled;

    function fillOrder(
        bytes32 orderHash,
        uint256 makingAmount,
        uint256 takingAmount,
        bytes calldata /* interaction */
    ) external {
        require(!cancelled[orderHash], "Order cancelled");

        filled[orderHash] += makingAmount;

        emit OrderFilled(orderHash, makingAmount, takingAmount);
    }

    function cancelOrder(bytes32 orderHash) external {
        cancelled[orderHash] = true;
        emit OrderCancelled(orderHash);
    }

    // Simplified for testing
    function fillOrder(
        bytes32 orderHash,
        uint256 makingAmount,
        uint256 takingAmount
    ) external {
        this.fillOrder(orderHash, makingAmount, takingAmount, "");
    }
}
