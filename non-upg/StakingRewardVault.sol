// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingRewardVault is Ownable {
    IERC20 public rewardToken;
    mapping(address => bool) public whitelistedContracts;

    event WhitelistedContract(address indexed contractAddress, bool status);

    constructor(IERC20 _rewardToken) {
        rewardToken = _rewardToken;
    }

    modifier onlyWhitelisted() {
        require(whitelistedContracts[msg.sender], "Not authorized");
        _;
    }

    // Allow the owner to whitelist or remove a contract from the whitelist
    function whitelistContract(address _contract, bool _status) external onlyOwner {
        whitelistedContracts[_contract] = _status;
        emit WhitelistedContract(_contract, _status);
    }

    // Transfer rewards to the specified address, only callable by whitelisted contracts
    function transferReward(address to, uint256 amount) external onlyWhitelisted {
        require(rewardToken.balanceOf(address(this)) >= amount, "Insufficient rewards");
        rewardToken.transfer(to, amount);
    }

    // Get available rewards in the vault
    function availableRewards() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    // Allow the owner to recover any leftover tokens
    function recoverTokens(IERC20 token, uint256 amount) external onlyOwner {
        token.transfer(owner(), amount);
    }
}
