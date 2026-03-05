// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../tokens/IYieldTracker.sol";

contract CYSE is ERC20, AccessControl {
    using SafeERC20 for IERC20;

    // Define role identifiers
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant HANDLER_ROLE = keccak256("HANDLER_ROLE");

    uint256 public nonStakingSupply;
    bool public inPrivateTransferMode;
    address[] public yieldTrackers;

    mapping(address => bool) public nonStakingAccounts;

    /**
     * @dev Sets up the token and grants the deployer the default admin role.
     */
    constructor() ERC20("CYSE", "CYSE") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ==========================================
    // Core ERC20 Overrides & Hooks
    // ==========================================
        
    /**
     * @dev Centralized hook for minting, burning, and transferring.
     * Replaces the custom _transfer, _mint, and _burn logic.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        // Update rewards and non-staking supply for the sender
        if (from != address(0)) {
            _updateRewards(from);
            if (nonStakingAccounts[from]) {
                nonStakingSupply -= value;
            }
        }

        // Update rewards and non-staking supply for the receiver
        if (to != address(0)) {
            _updateRewards(to);
            if (nonStakingAccounts[to]) {
                nonStakingSupply += value;
            }
        }

        super._update(from, to, value);
    }

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        if (inPrivateTransferMode) {
            require(hasRole(HANDLER_ROLE, _msgSender()), "CYSE: msg.sender not whitelisted");
        }
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        // Handlers can bypass allowance checks
        if (hasRole(HANDLER_ROLE, _msgSender())) {
            _transfer(from, to, value);
            return true;
        }

        if (inPrivateTransferMode) {
            revert("CYSE: msg.sender not whitelisted");
        }

        return super.transferFrom(from, to, value);
    }

    // ==========================================
    // Yield Tracking & Staking View Functions
    // ==========================================

    function _updateRewards(address _account) private {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            IYieldTracker(yieldTrackers[i]).updateRewards(_account);
        }
    }

    function claim(address _receiver) external {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            IYieldTracker(yieldTrackers[i]).claim(_msgSender(), _receiver);
        }
    }

    function recoverClaim(address _account, address _receiver) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            IYieldTracker(yieldTrackers[i]).claim(_account, _receiver);
        }
    }

    function totalStaked() external view returns (uint256) {
        return totalSupply() - nonStakingSupply;
    }

    function stakedBalance(address _account) external view returns (uint256) {
        if (nonStakingAccounts[_account]) {
            return 0;
        }
        return balanceOf(_account);
    }

    // ==========================================
    // Admin & Configuration Functions
    // ==========================================

    function mint(address _account, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _burn(_account, _amount);
    }

    function setYieldTrackers(address[] memory _yieldTrackers) external onlyRole(DEFAULT_ADMIN_ROLE) {
        yieldTrackers = _yieldTrackers;
    }

    function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        inPrivateTransferMode = _inPrivateTransferMode;
    }

    function addNonStakingAccount(address _account) external onlyRole(ADMIN_ROLE) {
        require(!nonStakingAccounts[_account], "CYSE: account already marked");
        _updateRewards(_account);
        nonStakingAccounts[_account] = true;
        nonStakingSupply += balanceOf(_account);
    }

    function removeNonStakingAccount(address _account) external onlyRole(ADMIN_ROLE) {
        require(nonStakingAccounts[_account], "CYSE: account not marked");
        _updateRewards(_account);
        nonStakingAccounts[_account] = false;
        nonStakingSupply -= balanceOf(_account);
    }

    /**
     * @dev Recovers ERC20 tokens accidentally sent to this contract.
     */
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).safeTransfer(_account, _amount);
    }
}