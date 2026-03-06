// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Ensure this path matches your project structure
import "./YieldToken.sol";

/**
 * @title YieldFarm
 * @dev Modernized staking contract for the CYSE protocol.
 * Inherits from YieldToken to leverage its reward-tracking hooks.
 */
contract YieldFarm is YieldToken, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public stakingToken;

    /**
     * @param _name Name for the receipt token (e.g., "Staked CYSE")
     * @param _symbol Symbol for the receipt token (e.g., "sCYSE")
     * @param _stakingToken The address of the token users deposit (e.g., USDC or CYSE)
     */
    constructor(
        string memory _name, 
        string memory _symbol, 
        address _stakingToken
    ) YieldToken(_name, _symbol) {
        stakingToken = _stakingToken;
    }

    /**
     * @dev Deposits tokens into the farm and mints receipt tokens.
     * Inherited YieldToken._update hook automatically triggers Reward updates.
     * @param _amount Amount of staking tokens to deposit.
     */
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "YieldFarm: cannot stake 0");

        // 1. Pull the actual tokens from the user
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        
        // 2. Mint YieldTokens to the user
        // This triggers the _update() hook in YieldToken.sol, 
        // which notifies the YieldTracker to snapshot rewards.
        _mint(msg.sender, _amount);
    }

    /**
     * @dev Withdraws tokens from the farm and burns receipt tokens.
     * @param _amount Amount of staking tokens to withdraw.
     */
    function unstake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "YieldFarm: cannot unstake 0");
        require(balanceOf(msg.sender) >= _amount, "YieldFarm: burn amount exceeds balance");

        // 1. Burn the receipt tokens (receipt tokens = sCYSE)
        // This triggers the _update() hook to snapshot rewards BEFORE balance decreases.
        _burn(msg.sender, _amount);
        
        // 2. Return the original staking tokens (e.g., USDC/CYSE) to the user
        IERC20(stakingToken).safeTransfer(msg.sender, _amount);
    }

    /**
     * @dev View function to return the token being staked.
     */
    function getStakingToken() external view returns (address) {
        return stakingToken;
    }
}