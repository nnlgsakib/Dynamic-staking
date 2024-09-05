// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRewardVault {
    function transferReward(address to, uint256 amount) external;
    function availableRewards() external view returns (uint256);
}

interface ITreasury {
    function deposit(uint256 amount) external;
}

contract AdaptiveStaking is ReentrancyGuard, Ownable {
    IERC20 public stakingToken;
    IRewardVault public rewardVault;
    ITreasury public treasury;

    uint256 public constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;
    uint256 public constant FEE_PERCENTAGE = 2; // 2% fee on rewards and stake withdrawals

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 apyAtStake;
    }

    struct Staker {
        Stake[] stakes;
        uint256 totalStaked;
        uint256 rewardDebt;
    }

    mapping(address => Staker) public stakers;
    address[] public users;
    uint256 public apy;
    uint256 public totalRewardsPaid;

    event Staked(address indexed user, uint256 amount, uint256 stakeIndex);
    event RewardClaimed(address indexed user, uint256 reward, uint256 fee);
    event StakeWithdrawn(address indexed user, uint256 amount, uint256 fee, uint256 stakeIndex);
    event APYUpdated(uint256 newAPY);
    event RewardVaultUpdated(address indexed admin, address newVault);
    event TreasuryUpdated(address indexed admin, address newTreasury);

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

    constructor(IERC20 _stakingToken, IRewardVault _rewardVault, ITreasury _treasury, uint256 _initialAPY) {
        stakingToken = _stakingToken;
        rewardVault = _rewardVault;
        treasury = _treasury;
        apy = _initialAPY;
    }

    function stake(uint256 amount) external nonReentrant updateRewards(msg.sender) {
        require(amount > 0, "Cannot stake zero tokens");

        Staker storage staker = stakers[msg.sender];
        if (staker.totalStaked == 0) {
            users.push(msg.sender); // Track users
        }

        stakingToken.transferFrom(msg.sender, address(this), amount);
        staker.stakes.push(Stake({
            amount: amount,
            startTime: block.timestamp,
            apyAtStake: apy
        }));
        staker.totalStaked += amount;

        emit Staked(msg.sender, amount, staker.stakes.length - 1);
    }

    function claimReward() external nonReentrant updateRewards(msg.sender) {
        Staker storage staker = stakers[msg.sender];
        uint256 reward = staker.rewardDebt;
        require(reward > 0, "No reward available");
        require(rewardVault.availableRewards() >= reward, "Insufficient rewards in vault");

        // 2% fee on reward
        uint256 fee = (reward * FEE_PERCENTAGE) / 100;
        uint256 netReward = reward - fee;

        staker.rewardDebt = 0; // Reset reward debt
        rewardVault.transferReward(msg.sender, netReward);
        rewardVault.transferReward(address(treasury), fee);
        treasury.deposit(fee);

        totalRewardsPaid += netReward;
        emit RewardClaimed(msg.sender, netReward, fee);
    }

    function withdrawStake(uint256 stakeIndex) external nonReentrant updateRewards(msg.sender) {
        Staker storage staker = stakers[msg.sender];
        require(stakeIndex < staker.stakes.length, "Invalid stake index");

        Stake storage userStake = staker.stakes[stakeIndex];
        uint256 stakedAmount = userStake.amount;
        require(stakedAmount > 0, "No staked amount to withdraw");

        // 2% fee on withdrawal
        uint256 fee = (stakedAmount * FEE_PERCENTAGE) / 100;
        uint256 netAmount = stakedAmount - fee;

        staker.stakes[stakeIndex] = staker.stakes[staker.stakes.length - 1]; // Remove stake
        staker.stakes.pop();
        staker.totalStaked -= stakedAmount;

        stakingToken.transfer(msg.sender, netAmount);
        stakingToken.transfer(address(treasury), fee);
        treasury.deposit(fee);

        emit StakeWithdrawn(msg.sender, netAmount, fee, stakeIndex);
    }

    function calculateReward(Stake memory userStake) internal view returns (uint256) {
        if (userStake.amount == 0 || userStake.startTime == 0) return 0;

        uint256 timeDifference = block.timestamp - userStake.startTime;
        return (userStake.amount * userStake.apyAtStake * timeDifference) / (SECONDS_IN_A_YEAR * 100);
    }

    // Administrative Functions

    function setRewardVault(IRewardVault _newVault) external onlyOwner {
        rewardVault = _newVault;
        emit RewardVaultUpdated(msg.sender, address(_newVault));
    }

    function setTreasury(ITreasury _newTreasury) external onlyOwner {
        treasury = _newTreasury;
        emit TreasuryUpdated(msg.sender, address(_newTreasury));
    }

    function setAPY(uint256 newAPY) external onlyOwner {
        apy = newAPY;
        emit APYUpdated(newAPY);
    }

    // Read Functions for Admin and Users

    function getAllUsers() external view returns (address[] memory) {
        return users;
    }

    function getTotalPaid() external view returns (uint256) {
        return totalRewardsPaid;
    }

    function getUserSessions(address user) external view returns (Stake[] memory) {
        return stakers[user].stakes;
    }

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        stakingToken.transfer(owner(), amount);
    }
}
