// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IRewardVault {
    function transferReward(address to, uint256 amount) external;
    function availableRewards() external view returns (uint256);
}

interface ITreasury {
    function deposit(uint256 amount) external;
}

contract DynamicStaking is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    IERC20Upgradeable public stakingToken;
    IRewardVault public rewardVault;
    ITreasury public treasury;

    uint256 public constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;
    uint256 public constant FEE_PERCENTAGE = 2;

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
    event RewardVaultUpdated(address indexed admin, address newVault);
    event TreasuryUpdated(address indexed admin, address newTreasury);
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20Upgradeable _stakingToken, IRewardVault _rewardVault, ITreasury _treasury, uint256 _initialAPY) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        stakingToken = _stakingToken;
        rewardVault = _rewardVault;
        treasury = _treasury;
        apy = _initialAPY;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    function stake(uint256 amount) external nonReentrant updateRewards(msg.sender) {
        require(amount > 0, "Cannot stake zero tokens");

        Staker storage staker = stakers[msg.sender];
        if (staker.totalStaked == 0) {
            users.push(msg.sender);
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

        uint256 fee = (reward * FEE_PERCENTAGE) / 100;
        uint256 netReward = reward - fee;

        staker.rewardDebt = 0;

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

        uint256 fee = (stakedAmount * FEE_PERCENTAGE) / 100;
        uint256 netAmount = stakedAmount - fee;

        staker.stakes[stakeIndex] = staker.stakes[staker.stakes.length - 1];
        staker.stakes.pop();

        staker.totalStaked -= stakedAmount;

        stakingToken.transfer(msg.sender, netAmount);
        stakingToken.transfer(address(treasury), fee);
        treasury.deposit(fee);

        emit StakeWithdrawn(msg.sender, netAmount, fee, stakeIndex);
    }

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

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        stakingToken.transfer(owner(), amount);
    }

    function availableRewards() external view returns (uint256) {
        return rewardVault.availableRewards();
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
}
