// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import '@openzeppelin/contracts/access/Ownable.sol';

contract DrainMe is Ownable{
    constructor() Ownable(msg.sender) {
    }

    // State variables
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public collaterals;
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public totalDeposits;
    uint256 public totalCollaterals;
    bool private locked;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event DustWithdrawn(address indexed owner, uint256 amount);
    event EmergencyWithdrawn(uint256 amount);
    event PendingWithdrawalClaimed(address indexed user, uint256 amount);
    event PendingWithdrawalCreated(address indexed owner, uint256 amount);


    // Modifiers
    modifier noReentrancy() {
        require (!locked, 'Reentrency detected');
        locked = true;
        _;
        locked = false;
    }
    function deposit() external payable {
        require(msg.value > 0, "Cannot deposit 0");
        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external noReentrancy {
        require(amount > 0, "Cannot withdraw 0");
        require(deposits[msg.sender] >= amount, "Insufficient balance");
        deposits[msg.sender] -= amount;
        totalDeposits -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    function depositCollateral() external payable {
        require(msg.value > 0, 'value must be more than 0');
        collaterals[msg.sender] += msg.value;
        totalCollaterals += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    function getCollateral(address user) external view returns (uint256) {
        return collaterals[user];
    }

    function getTotalCollaterals() external view returns (uint256) {
        return totalCollaterals;
    }

    function withdrawCollateral(address _to, uint256 amount) external onlyOwner noReentrancy {
        require(collaterals[_to] >= amount, "Insufficient collateral");
        collaterals[_to] -= amount;
        totalCollaterals -= amount;
        (bool success, ) = _to.call{value: amount}("");
        require(success, "Transfer failed");
        emit CollateralWithdrawn(_to, amount);
    }

    function withdrawDust() external onlyOwner noReentrancy {
        uint256 dust = address(this).balance - totalDeposits - totalCollaterals;
        require(dust > 0, "No dust to withdraw");
        (bool success, ) = owner().call{value: dust}("");
        require(success, "Transfer failed");
        emit DustWithdrawn(owner(), dust);
    }

    function emergencyWithdraw() external onlyOwner noReentrancy {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No funds to withdraw");
        (bool success, ) = owner().call{value: contractBalance}("");
        if (!success) {
            pendingWithdrawals[owner()] += contractBalance;
            emit PendingWithdrawalCreated(owner(), contractBalance);
        } else {
            totalDeposits = 0;
            totalCollaterals = 0;
            emit EmergencyWithdrawn(contractBalance); 
            }   
    }

// В DrainMe.sol
    function claimPendingWithdrawal(address from, address payable to) external onlyOwner noReentrancy {
        uint256 amount = pendingWithdrawals[from];
        require(amount > 0, "No pending withdrawal");

        pendingWithdrawals[from] = 0;

        (bool success, ) = to.call{value: amount}("");
        require(success, "Claim failed");
        emit PendingWithdrawalClaimed(from, amount);
    }

    function getDeposit(address user) external view returns (uint256) {
        return deposits[user];
    }

    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }
}