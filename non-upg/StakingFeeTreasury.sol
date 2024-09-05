// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingFeeTreasury is Ownable {
    IERC20 public immutable treasuryToken;

    event FeeDeposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed recipient, uint256 amount);

    constructor(IERC20 _treasuryToken) {
        treasuryToken = _treasuryToken;
    }

    function deposit(uint256 amount) external {
        treasuryToken.transferFrom(msg.sender, address(this), amount);
        emit FeeDeposited(msg.sender, amount);
    }

    function withdraw(address recipient, uint256 amount) external onlyOwner {
        require(treasuryToken.balanceOf(address(this)) >= amount, "Insufficient balance");
        treasuryToken.transfer(recipient, amount);
        emit Withdrawn(recipient, amount);
    }

    function getTreasuryBalance() external view returns (uint256) {
        return treasuryToken.balanceOf(address(this));
    }

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        treasuryToken.transfer(owner(), amount);
    }
}

