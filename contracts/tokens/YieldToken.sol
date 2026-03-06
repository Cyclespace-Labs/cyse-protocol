// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IYieldTracker.sol";
import "./IYieldToken.sol";

/**
 * @title YieldToken
 * @dev Modernized YieldToken using OpenZeppelin v5.
 * Replaces manual balance/transfer logic with the _update hook.
 */
contract YieldToken is ERC20, AccessControl, IYieldToken {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant HANDLER_ROLE = keccak256("HANDLER_ROLE");

    uint256 public nonStakingSupply;
    bool public inWhitelistMode;
    address[] public yieldTrackers;

    mapping(address => bool) public nonStakingAccounts;
    mapping(address => bool) public whitelistedHandlers;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ==========================================
    // Core ERC20 Overrides & Hooks
    // ==========================================

    /**
     * @dev Unified hook for all balance changes.
     * Replaces the manual _transfer logic from the old version.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        // Update rewards and non-staking supply for the sender (if not minting)
        if (from != address(0)) {
            _updateRewards(from);
            if (nonStakingAccounts[from]) {
                nonStakingSupply -= value;
            }
        }

        // Update rewards and non-staking supply for the receiver (if not burning)
        if (to != address(0)) {
            _updateRewards(to);
            if (nonStakingAccounts[to]) {
                nonStakingSupply += value;
            }
        }

        super._update(from, to, value);
    }

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        if (inWhitelistMode) {
            require(hasRole(HANDLER_ROLE, _msgSender()), "YieldToken: msg.sender not whitelisted");
        }
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        // Allow handlers to bypass allowance checks
        if (hasRole(HANDLER_ROLE, _msgSender())) {
            _transfer(from, to, value);
            return true;
        }

        if (inWhitelistMode) {
            revert("YieldToken: msg.sender not whitelisted");
        }

        return super.transferFrom(from, to, value);
    }

    // ==========================================
    // Internal Logic
    // ==========================================

    function _updateRewards(address _account) private {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            IYieldTracker(yieldTrackers[i]).updateRewards(_account);
        }
    }

    // ==========================================
    // View Functions (IYieldToken)
    // ==========================================

    function totalStaked() external view override returns (uint256) {
        return totalSupply() - nonStakingSupply;
    }

    function stakedBalance(address _account) external view override returns (uint256) {
        if (nonStakingAccounts[_account]) {
            return 0;
        }
        return balanceOf(_account);
    }

    // ==========================================
    // Admin Functions
    // ==========================================

    function setYieldTrackers(address[] memory _yieldTrackers) external onlyRole(DEFAULT_ADMIN_ROLE) {
        yieldTrackers = _yieldTrackers;
    }

    function addNonStakingAccount(address _account) external onlyRole(ADMIN_ROLE) {
        require(!nonStakingAccounts[_account], "YieldToken: account already marked");
        _updateRewards(_account);
        nonStakingAccounts[_account] = true;
        nonStakingSupply += balanceOf(_account);
    }

    function removeNonStakingAccount(address _account) external onlyRole(ADMIN_ROLE) {
        require(nonStakingAccounts[_account], "YieldToken: account not marked");
        _updateRewards(_account);
        nonStakingAccounts[_account] = false;
        nonStakingSupply -= balanceOf(_account);
    }

    function setInWhitelistMode(bool _inWhitelistMode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        inWhitelistMode = _inWhitelistMode;
    }

    /**
     * @dev Implementation of removeAdmin from IYieldToken using AccessControl
     */
    function removeAdmin(address _account) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ADMIN_ROLE, _account);
    }

    /**
     * @dev Recovers ERC20 tokens accidentally sent to this contract.
     */
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).safeTransfer(_account, _amount);
    }
}