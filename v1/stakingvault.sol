
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardVaultv2 is Ownable {
    IERC20 public immutable rewardToken;
    address public stakingContract;

    event Refill(uint256 amount);
    event RewardTransferred(address indexed user, uint256 amount);
    event StakingContractUpdated(address indexed admin, address newStakingContract);

    constructor(IERC20 _rewardToken) {
        rewardToken = _rewardToken;
    }

    modifier onlyStakingContractOrOwner() {
        require(msg.sender == stakingContract || msg.sender == owner(), "Not authorized");
        _;
    }

    function setStakingContract(address _stakingContract) external onlyOwner {
        stakingContract = _stakingContract;
        emit StakingContractUpdated(msg.sender, _stakingContract);
    }

    function refill(uint256 amount) external onlyOwner {
        rewardToken.transferFrom(msg.sender, address(this), amount);
        emit Refill(amount);
    }

    function transferReward(address to, uint256 amount) external onlyStakingContractOrOwner {
        require(rewardToken.balanceOf(address(this)) >= amount, "Insufficient reward balance");
        rewardToken.transfer(to, amount);
        emit RewardTransferred(to, amount);
    }

    function availableRewards() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
}
