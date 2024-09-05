// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract RewardVault is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    IERC20Upgradeable public rewardToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20Upgradeable _rewardToken) initializer public {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        rewardToken = _rewardToken;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    function transferReward(address to, uint256 amount) external onlyOwner {
        require(amount > 0, "Cannot transfer zero reward");
        require(rewardToken.balanceOf(address(this)) >= amount, "Insufficient reward tokens");
        rewardToken.transfer(to, amount);
    }

    function availableRewards() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    function depositRewards(uint256 amount) external onlyOwner {
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        rewardToken.transfer(owner(), amount);
    }
}

