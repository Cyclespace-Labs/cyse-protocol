// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Corrected relative paths based on your structure
import "./IDistributor.sol";
import "./IYieldTracker.sol";
import "./IYieldToken.sol";

/**
 * @title YieldTracker
 * @dev Modernized YieldTracker using OpenZeppelin v5.
 * This contract calculates and distributes rewards based on CYSE token snapshots.
 */
contract YieldTracker is IYieldTracker, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e30;

    address public yieldToken;
    address public distributor;

    uint256 public cumulativeRewardPerToken;
    mapping(address => uint256) public claimableReward;
    mapping(address => uint256) public previousCumulatedRewardPerToken;

    event Claim(address receiver, uint256 amount);
    event DistributorSet(address distributor);

    constructor(address _yieldToken) Ownable(msg.sender) {
        yieldToken = _yieldToken;
    }

    // ==========================================
    // Admin Functions
    // ==========================================

    function setDistributor(address _distributor) external onlyOwner {
        distributor = _distributor;
        emit DistributorSet(_distributor);
    }

    // ==========================================
    // Core Reward Logic
    // ==========================================

    /**
     * @dev Updates reward accounting for a specific account.
     * Called by the CYSE token contract during every transfer/mint/burn.
     */
    function updateRewards(address _account) external override nonReentrant {
        uint256 blockReward = 0;
        
        // Fetch rewards from the distributor if it exists
        if (distributor != address(0)) {
            blockReward = IDistributor(distributor).distribute();
        }

        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();

        // Update global reward index
        if (totalStaked > 0 && blockReward > 0) {
            _cumulativeRewardPerToken += (blockReward * PRECISION) / totalStaked;
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // If no rewards have ever been distributed, exit
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        // Update specific account's reward snapshot
        if (_account != address(0)) {
            uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(_account);
            uint256 _previousCumulatedReward = previousCumulatedRewardPerToken[_account];
            
            uint256 _claimableReward = claimableReward[_account] + (
                (stakedBalance * (_cumulativeRewardPerToken - _previousCumulatedReward)) / PRECISION
            );

            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[_account] = _cumulativeRewardPerToken;
        }
    }

    /**
     * @dev Claims accumulated rewards for a user.
     */
    function claim(address _account, address _receiver) external override nonReentrant returns (uint256) {
        // Only the yieldToken (CYSE) or the user themselves can trigger a claim via this flow
        // In GMX, usually the token calls this.
        require(msg.sender == yieldToken || msg.sender == _account, "YieldTracker: forbidden");

        uint256 amount = claimableReward[_account];
        if (amount == 0) {
            return 0;
        }

        claimableReward[_account] = 0;
        
        address rewardToken = IDistributor(distributor).getRewardToken(_account);
        IERC20(rewardToken).safeTransfer(_receiver, amount);

        emit Claim(_receiver, amount);
        return amount;
    }

    // ==========================================
    // View Functions
    // ==========================================

    function getTokensPerInterval() external view override returns (uint256) {
        return IDistributor(distributor).tokensPerInterval(address(this));
    }

    function claimable(address _account) external view override returns (uint256) {
        uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(_account);
        if (stakedBalance == 0) {
            return claimableReward[_account];
        }

        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        uint256 blockReward = IDistributor(distributor).getDistributionAmount(address(this));

        if (totalStaked > 0 && blockReward > 0) {
            _cumulativeRewardPerToken += (blockReward * PRECISION) / totalStaked;
        }

        return claimableReward[_account] + (
            (stakedBalance * (_cumulativeRewardPerToken - previousCumulatedRewardPerToken[_account])) / PRECISION
        );
    }
}