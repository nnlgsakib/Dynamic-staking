
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRewardVault {
    function transferReward(address to, uint256 amount) external;
    function availableRewards() external view returns (uint256);
}

contract DynamicStaking is ReentrancyGuard, Ownable {
    IERC20 public immutable stakingToken;
    IRewardVault public rewardVault;

    uint256 public constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 apyAtStake; // Store APY at the time of staking
    }

    struct Staker {
        Stake[] stakes;
        uint256 totalStaked;
        uint256 rewardDebt;
    }

    mapping(address => Staker) public stakers;
    address[] public users;  // Keep track of users who have interacted with the contract

    uint256 public apy; // Modifiable APY for future adjustments
    uint256 public totalRewardsPaid; // Track total rewards paid to users

    event Staked(address indexed user, uint256 amount, uint256 stakeIndex);
    event RewardClaimed(address indexed user, uint256 amount);
    event StakeWithdrawn(address indexed user, uint256 amount, uint256 stakeIndex);
    event RewardVaultUpdated(address indexed admin, address newVault);
    event APYUpdated(uint256 newAPY);

    modifier updateRewards(address stakerAddress) {
        Staker storage staker = stakers[stakerAddress];
        uint256 accumulatedReward = 0;

        for (uint256 i = 0; i < staker.stakes.length; i++) {
            Stake storage userStake = staker.stakes[i];
            uint256 reward = calculateReward(userStake);
            accumulatedReward += reward;
        }

        staker.rewardDebt += accumulatedReward;
        _;
    }

    constructor(IERC20 _stakingToken, IRewardVault _rewardVault, uint256 _initialAPY) {
        stakingToken = _stakingToken;
        rewardVault = _rewardVault;
        apy = _initialAPY; // Initialize the APY at deployment
    }

    function stake(uint256 amount) external nonReentrant updateRewards(msg.sender) {
        require(amount > 0, "Cannot stake zero tokens");

        Staker storage staker = stakers[msg.sender];

        // Add the user to the users array if they are staking for the first time
        if (staker.totalStaked == 0) {
            users.push(msg.sender);
        }

        stakingToken.transferFrom(msg.sender, address(this), amount);

        staker.stakes.push(Stake({
            amount: amount,
            startTime: block.timestamp,
            apyAtStake: apy // Store APY when staking
        }));

        staker.totalStaked += amount;
        emit Staked(msg.sender, amount, staker.stakes.length - 1);
    }

    function claimReward() external nonReentrant updateRewards(msg.sender) {
        Staker storage staker = stakers[msg.sender];
        uint256 reward = staker.rewardDebt;

        require(reward > 0, "No reward available");

        // Check if reward vault has enough funds
        require(rewardVault.availableRewards() >= reward, "Insufficient rewards in vault");

        // Reset reward debt
        staker.rewardDebt = 0;

        // Transfer rewards from the vault
        rewardVault.transferReward(msg.sender, reward);

        // Track total rewards paid
        totalRewardsPaid += reward;

        emit RewardClaimed(msg.sender, reward);
    }

    function withdrawStake(uint256 stakeIndex) external nonReentrant updateRewards(msg.sender) {
        Staker storage staker = stakers[msg.sender];
        require(stakeIndex < staker.stakes.length, "Invalid stake index");

        Stake storage userStake = staker.stakes[stakeIndex];
        uint256 stakedAmount = userStake.amount;
        require(stakedAmount > 0, "No staked amount to withdraw");

        // Remove stake by swapping with the last stake and popping the array
        staker.stakes[stakeIndex] = staker.stakes[staker.stakes.length - 1];
        staker.stakes.pop();

        staker.totalStaked -= stakedAmount;

        // Transfer the staked tokens back to the user
        stakingToken.transfer(msg.sender, stakedAmount);
        emit StakeWithdrawn(msg.sender, stakedAmount, stakeIndex);
    }

    // New Admin Function: Get all users
    function getAllUsers() external view returns (address[] memory) {
        return users;
    }

    // New Admin Function: Get total rewards paid over contract lifetime
    function getTotalPaid() external view returns (uint256) {
        return totalRewardsPaid;
    }

    // New User Function: Get all active sessions for a user
    function getUserActiveSessions(address user) external view returns (
        uint256[] memory sessionIndexes, 
        uint256[] memory amounts, 
        uint256[] memory rewardsPerDay, 
        uint256[] memory annualRewards
    ) {
        Staker storage staker = stakers[user];
        uint256 activeSessions = staker.stakes.length;

        sessionIndexes = new uint256[](activeSessions);
        amounts = new uint256[](activeSessions);
        rewardsPerDay = new uint256[](activeSessions);
        annualRewards = new uint256[](activeSessions);

        for (uint256 i = 0; i < activeSessions; i++) {
            Stake storage userStake = staker.stakes[i];
            sessionIndexes[i] = i;
            amounts[i] = userStake.amount;

            uint256 rewardPerDay = calculateReward(userStake) / SECONDS_IN_A_YEAR * 86400;
            uint256 annualReward = calculateReward(userStake);

            rewardsPerDay[i] = rewardPerDay;
            annualRewards[i] = annualReward;
        }

        return (sessionIndexes, amounts, rewardsPerDay, annualRewards);
    }

    function totalReward() external view returns (uint256) {
        Staker memory staker = stakers[msg.sender];
        uint256 accumulatedReward = staker.rewardDebt;

        for (uint256 i = 0; i < staker.stakes.length; i++) {
            accumulatedReward += calculateReward(staker.stakes[i]);
        }

        return accumulatedReward;
    }

    function calculateReward(Stake memory userStake) internal view returns (uint256) {
        if (userStake.amount == 0 || userStake.startTime == 0) {
            return 0;
        }

        uint256 timeDifference = block.timestamp - userStake.startTime;
        return (userStake.amount * userStake.apyAtStake * timeDifference) / (SECONDS_IN_A_YEAR * 100);
    }

    function setRewardVault(IRewardVault _newVault) external onlyOwner {
        rewardVault = _newVault;
        emit RewardVaultUpdated(msg.sender, address(_newVault));
    }

    function setAPY(uint256 newAPY) external onlyOwner {
        apy = newAPY;
        emit APYUpdated(newAPY);
    }

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        stakingToken.transfer(owner(), amount);
    }

    function availableRewards() external view returns (uint256) {
        return rewardVault.availableRewards();
    }
}
