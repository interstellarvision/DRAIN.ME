// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/MathLib.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract DrainMe is Ownable{
    // State variables
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public collaterals;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => uint256) public borrowed; // В USDC (6 знаков)

    uint256 public totalDeposits;
    uint256 public totalCollaterals;
    uint256 public constant ETH_PRICE = 2000e18; // Хардкодим $2000 за 1 ETH для начала
    uint256 public constant LIQUIDATION_THRESHOLD = 0.8e18; // 80% (в WAD)
    uint256 public constant LTV = 0.75e18; // 75% (в WAD)
    uint256 public totalBorrowed;
    bool private locked;
    IERC20 public immutable USDC;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event DustWithdrawn(address indexed owner, uint256 amount);
    event EmergencyWithdrawn(uint256 amount);
    event PendingWithdrawalClaimed(address indexed user, uint256 amount);
    event PendingWithdrawalCreated(address indexed owner, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    
    constructor(address _usdc) Ownable(msg.sender) {
        require(_usdc != address(0), "USDC address cannot be zero");
        USDC = IERC20(_usdc);

    }

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

    function provideLiquidity(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(USDC.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }

    function getAccountData(address user) public view returns (uint256 collateralValue, uint256 borrowedValue) {
        collateralValue = MathLib.wadMul(collaterals[user], ETH_PRICE);
        borrowedValue = borrowed[user] * 1e12;
        return (collateralValue, borrowedValue);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        (uint256 collateralValue, uint256 borrowedValue) = getAccountData(user);
        if (borrowedValue == 0) {
            return type(uint256).max;
        }
        uint256 liquidationValue = MathLib.wadMul(collateralValue, LIQUIDATION_THRESHOLD);
        return MathLib.wadDiv(liquidationValue, borrowedValue);
    }

    function borrow(uint256 amount) external noReentrancy {
        require(amount > 0, "Amount cant be less than 0");
        require(collaterals[msg.sender] > 0, "No collateral deposited");
        uint256 amountInWad = amount * 1e12; 
        (uint256 collateralValue, uint256 currentBorrowedValue) = getAccountData(msg.sender);
        uint256 maxBorrow = MathLib.wadMul(collateralValue, LTV);
        require(currentBorrowedValue + amountInWad <= maxBorrow, "Borrow amount exceeds LTV");
        require(USDC.balanceOf(address(this)) >= amount, "Insufficient USDC liquidity");
        borrowed[msg.sender] += amount;
        totalBorrowed += amount;
        require(USDC.transfer(msg.sender, amount), "Transfer failed");

        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external noReentrancy {
        require(amount > 0, "Amount must be > 0");
        uint256 userDebt = borrowed[msg.sender];
        require(userDebt >= amount, "Repaying more than owed");
        borrowed[msg.sender] -= amount;
        totalBorrowed -= amount;
        require(USDC.transferFrom(msg.sender, address(this), amount), "USDC transfer failed");

        emit Repaid(msg.sender, amount);
    }
}