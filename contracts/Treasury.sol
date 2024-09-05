
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract Treasury is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    IERC20Upgradeable public treasuryToken;

    event FeeDeposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed recipient, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20Upgradeable _treasuryToken) initializer public {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        treasuryToken = _treasuryToken;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    function deposit(uint256 amount) external {
        require(amount > 0, "Cannot deposit zero tokens");
        treasuryToken.transferFrom(msg.sender, address(this), amount);
        emit FeeDeposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(treasuryToken.balanceOf(address(this)) >= amount, "Insufficient funds");
        treasuryToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        treasuryToken.transfer(owner(), amount);
    }
}
