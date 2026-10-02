// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/MathLib.sol";


contract DrainMe is Ownable, ERC4626 {
    // State variables
    mapping(address => uint256) public collaterals;
    mapping(address => uint256) public borrowed; // В USDC (6 знаков)

    uint256 public totalCollaterals;
    uint256 public constant ETH_PRICE = 2000e18; // Хардкодим $2000 за 1 ETH для начала
    uint256 public constant LIQUIDATION_THRESHOLD = 0.8e18; // 80% (в WAD)
    uint256 public constant LTV = 0.75e18; // 75% (в WAD)
    uint256 public totalBorrowed;
    bool private locked;

    // Events
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event DustWithdrawn(address indexed owner, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    
    constructor(IERC20 _usdc) 
        ERC20("DrainMe Share", "dmSHARE")
        ERC4626(_usdc)
        Ownable(msg.sender)
    {
        require(address(_usdc) != address(0), "USDC address cannot be zero");
    }

    // Modifiers
    modifier noReentrancy() {
        require (!locked, 'Reentrency detected');
        locked = true;
        _;
        locked = false;
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
        uint256 remainingCollateral = collaterals[_to] - amount;
        uint256 remainingCollateralValue = MathLib.wadMul(remainingCollateral, ETH_PRICE);
        uint256 maxRemainingBorrow = MathLib.wadMul(remainingCollateralValue, LTV);
        require(borrowed[_to] * 1e12 <= maxRemainingBorrow, "Withdrawing this deposit will put your loan in a precarious situation; reduce the amount or pay off part of the debt.");
        collaterals[_to] -= amount;
        totalCollaterals -= amount;
        emit CollateralWithdrawn(_to, amount);
        (bool success, ) = _to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function withdrawEthDust() external onlyOwner noReentrancy {
        uint256 dust = address(this).balance - totalCollaterals;
        require(dust > 0, "No dust to withdraw");
        emit DustWithdrawn(owner(), dust);
        (bool success, ) = owner().call{value: dust}("");
        require(success, "Transfer failed");
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

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalBorrowed;
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(assets > 0, "Cannot deposit 0");
        return super.deposit(assets, receiver);
    }
    
    function borrow(uint256 amount) external noReentrancy {
        require(amount > 0, "Amount cant be less than 0");
        require(collaterals[msg.sender] > 0, "No collateral deposited");
        uint256 amountInWad = amount * 1e12; 
        (uint256 collateralValue, uint256 currentBorrowedValue) = getAccountData(msg.sender);
        uint256 maxBorrow = MathLib.wadMul(collateralValue, LTV);
        require(currentBorrowedValue + amountInWad <= maxBorrow, "Borrow amount exceeds LTV");
        require(IERC20(asset()).balanceOf(address(this)) >= amount, "Insufficient USDC liquidity");
        borrowed[msg.sender] += amount;
        totalBorrowed += amount;

        emit Borrowed(msg.sender, amount);
        require(IERC20(asset()).transfer(msg.sender, amount), "Transfer failed");
    }

    function repay(uint256 amount) external noReentrancy {
        require(amount > 0, "Amount must be > 0");
        uint256 userDebt = borrowed[msg.sender];
        require(userDebt >= amount, "Repaying more than owed");
        borrowed[msg.sender] -= amount;
        totalBorrowed -= amount;

        emit Repaid(msg.sender, amount);
        require(IERC20(asset()).transferFrom(msg.sender, address(this), amount), "USDC transfer failed");
    }
}