// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title DRAIN.ME v0.1 - Simple Vault
/// @author nostylist⁺
/// @notice Simple ETH vault for deposits and withdrawals
contract DrainMe {
    // State variables
    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Deposit ETH into the vault
    function deposit() external payable {
        require(msg.value > 0, "Cannot deposit 0");
        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from the vault
    /// @param amount Amount of ETH to withdraw
    function withdraw(uint256 amount) external {
        require(amount > 0, "Cannot withdraw 0");
        require(deposits[msg.sender] >= amount, "Insufficient balance");

        deposits[msg.sender] -= amount;
        totalDeposits -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Get deposit balance for a user
    /// @param user Address to check
    function getDeposit(address user) external view returns (uint256) {
        return deposits[user];
    }

    /// @notice Get total deposits in protocol
    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }
}