// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; 
import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/DrainMe.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract DrainMeTest is Test {
    receive() external payable {}
    MockUSDC public usdc;
    DrainMe public vault;
    address user = makeAddr("user"); 

    function setUp() public {
        usdc = new MockUSDC();
        vault = new DrainMe(IERC20(address(usdc)));
        vm.deal(user, 10 ether); 
        usdc.mint(address(this), 1_000_000 * 1e6); // 1M USDC
        usdc.approve(address(vault), 1_000_000 * 1e6);
        vault.deposit(100_000 * 1e6, address(this)); // Заливаем 100k в пул
    }
   
  
    function test_InitialOwner() public {
        address owner = vault.owner();
        assertEq(owner, address(this), "Owner should be the deployer");
    }

    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        vault.transferOwnership(newOwner);
        assertEq(vault.owner(), newOwner, "Ownership transfer failed");
    }

    function test_OnlyOwnerCanTransfer() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vault.transferOwnership(newOwner);
    }

    function test_RenounceOwnership() public {
        vault.renounceOwnership();
        assertEq(vault.owner(), address(0), "Ownership renouncement failed");
    }

    function test_CollateralDeposit() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 2 ether}();
        uint256 collateral = vault.getCollateral(user);
        assertEq(collateral, 2 ether);
        vm.stopPrank();
    }

    function test_WithdrawCollateral_Success() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 3 ether}();
        vm.stopPrank();

        address owner = vault.owner();
        vm.startPrank(owner);
        vault.withdrawCollateral(user, 2 ether);
        vm.stopPrank();

        uint256 remainingCollateral = vault.getCollateral(user);
        assertEq(remainingCollateral, 1 ether);
    }

    function test_WithdrawCollateral_InsufficientBalance() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 3 ether}();
        vm.stopPrank();

        address owner = vault.owner();
        vm.startPrank(owner);
        vm.expectRevert('Insufficient collateral');
        vault.withdrawCollateral(user, 4 ether);
        vm.stopPrank();
    }


    function test_WithdrawCollateral_OnlyOwner() public {
        vm.prank(user);
        vault.depositCollateral{value: 1 ether}();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vault.withdrawCollateral(user, 1 ether);
    }

    function test_Borrow_Success() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(1000 * 10 ** 6); // Borrow 1000 USDC
        vm.stopPrank();
    }

    function test_Borrow_NoCollateral_Reverts() public {
        vm.prank(user);
        vm.expectRevert("No collateral deposited");
        vault.borrow(1000 * 10 ** 6);
    }

    function test_Borrow_ExceedsLTV_Reverts() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vm.expectRevert("Borrow amount exceeds LTV");
        vault.borrow(9000 * 10 ** 6); // Attempt to borrow more than 75% of collateral value
        vm.stopPrank();
    }

    function test_Borrow_InsufficientLiquidity_Reverts() public {
        vm.startPrank(user);
        vm.deal(user, 90 ether);
        vault.depositCollateral{value: 90 ether}();
        vm.expectRevert("Insufficient USDC liquidity");
        vault.borrow(120_000 * 10 ** 6); // Attempt to borrow more than available liquidity
        vm.stopPrank();
    }

    function test_Borrow_ZeroAmount_Reverts() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vm.expectRevert("Amount cant be less than 0");
        vault.borrow(0);
        vm.stopPrank();
    }

    function test_Borrow_EmitsEvent() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vm.expectEmit(true, false, false, true);
        emit DrainMe.Borrowed(user, 1000 * 10 ** 6);
        vault.borrow(1000 * 10 ** 6);
        vm.stopPrank();
    }
    
    function test_Repay_Success() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(1000 * 10 ** 6); // Borrow 1000 USDC

        usdc.mint(user, 1000 * 10 ** 6); // Mint USDC to user for repayment
        usdc.approve(address(vault), 1000 * 10 ** 6); // Approve vault to spend USDC

        vault.repay(500 * 10 ** 6); // Repay half of the borrowed amount
        vm.stopPrank();
    }

    function test_Repay_ZeroAmount_Reverts() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(1000 * 10 ** 6); // Borrow 1000 USDC

        usdc.mint(user, 1500 * 10 ** 6); // Mint more USDC than owed
        usdc.approve(address(vault), 1500 * 10 ** 6); // Approve vault to spend USDC

        vm.expectRevert('Amount must be > 0');
        vault.repay(0); // Attempt to repay zero amount
    }

    function test_Repay_ExceedsDebt_Reverts() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(1000 * 10 ** 6); // Borrow 1000 USDC

        usdc.mint(user, 1500 * 10 ** 6); // Mint more USDC than owed
        usdc.approve(address(vault), 1500 * 10 ** 6); // Approve vault to spend USDC

        vm.expectRevert("Repaying more than owed");
        vault.repay(1500 * 10 ** 6); // Attempt to repay more than owed
        vm.stopPrank();
    }

    function test_Repay_EmitsEvent() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(1000 * 10 ** 6); 
        usdc.mint(user, 1500 * 10 ** 6);
        usdc.approve(address(vault), 1500 * 10 ** 6);
        
        vm.expectEmit(true, false, false, true);
        emit DrainMe.Repaid(user, 500 * 10 ** 6);
        vault.repay(500 * 10 ** 6); // Repay half of the borrowed amount
        vm.stopPrank();
    }

    function test_HealthFactor_NoBorrow() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        uint256 healthFactor = vault.getHealthFactor(user);
        assertEq(healthFactor, type(uint256).max, "Health factor should be max when no borrow");
        vm.stopPrank();
    }
    
    function test_HealthFactor_AfterBorrow() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(2000 * 10 ** 6); // Borrow 2000 USDC
        uint256 healthFactor = vault.getHealthFactor(user);
        assertEq(healthFactor, 4 * 10 ** 18, "Health factor should be 4e18 after borrowing");
        vm.stopPrank();
    }

    function test_HealthFactor_AfterRepay() public {
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(2000 * 10 ** 6); // Borrow 2000 USDC
        uint256 healthFactorBefore = vault.getHealthFactor(user);
        usdc.mint(user, 2000 * 10 ** 6);
        usdc.approve(address(vault), 2000 * 10 ** 6);
        vault.repay(1000 * 10 ** 6); // Repay half of the borrowed amount
        uint256 healthFactorAfter = vault.getHealthFactor(user);
        assertTrue(healthFactorAfter > healthFactorBefore, "Health factor should improve after repay");
        vm.stopPrank();
    }

    // === ERC-4626 DEPOSIT / WITHDRAW ===

    function test_Deposit_MintsShares() public {
        usdc.mint(user, 1000 * 1e6);
        
        vm.startPrank(user);
        usdc.approve(address(vault), 1000 * 1e6);
        uint256 shares = vault.deposit(1000 * 1e6, user);
        vm.stopPrank();
        
        assertEq(shares, 1000 * 1e6, "Should mint 1000 shares");
        assertEq(vault.balanceOf(user), 1000 * 1e6, "User should have 1000 shares");
    }

    function test_Redeem_BurnsShares() public {
        usdc.mint(user, 1000 * 1e6);
        
        vm.startPrank(user);
        usdc.approve(address(vault), 1000 * 1e6);
        vault.deposit(1000 * 1e6, user);
        
        uint256 assets = vault.redeem(1000 * 1e6, user, user);
        vm.stopPrank();
        
        assertEq(assets, 1000 * 1e6, "Should return 1000 USDC");
        assertEq(vault.balanceOf(user), 0, "Shares should be burned");
        assertEq(usdc.balanceOf(user), 1000 * 1e6, "User should have USDC back");
    }

    function test_Deposit_ZeroAmount_Reverts() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 1000 * 1e6);
        vm.expectRevert();
        vault.deposit(0, user);
        vm.stopPrank();
    }

    function test_TotalAssets_IncludesBorrowed() public {
        uint256 totalBefore = vault.totalAssets();
        
        // user берёт в долг
        vm.startPrank(user);
        vm.deal(user, 5 ether);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(2000 * 1e6);
        vm.stopPrank();
        
        uint256 totalAfter = vault.totalAssets();
        assertEq(totalAfter, totalBefore, "TotalAssets should not change after borrow");
    }

    function test_SharePrice_StableAfterBorrow() public {
        // user1 депозитит
        address user1 = makeAddr("user1");
        usdc.mint(user1, 10_000 * 1e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000 * 1e6);
        vault.deposit(10_000 * 1e6, user1);
        vm.stopPrank();
        
        uint256 sharesBefore = vault.convertToAssets(1e6); // цена 1 share до borrow
        
        // user2 берёт в долг
        address user2 = makeAddr("user2");
        vm.deal(user2, 5 ether);
        vm.startPrank(user2);
        vault.depositCollateral{value: 5 ether}();
        vault.borrow(5000 * 1e6);
        vm.stopPrank();
        
        uint256 sharesAfter = vault.convertToAssets(1e6); // цена 1 share после borrow
        
        assertEq(sharesAfter, sharesBefore, "Share price must not change after borrow");
    }

    function test_SharePrice_GrowsAfterRepayWithExtra() public {
        // Этот тест симулирует ситуацию когда кто-то "донатит" USDC в vault
        // (в реальности это будут проценты, но их пока нет — 2.5)
        
        address depositor = makeAddr("depositor");
        usdc.mint(depositor, 10_000 * 1e6);
        vm.startPrank(depositor);
        usdc.approve(address(vault), 10_000 * 1e6);
        vault.deposit(10_000 * 1e6, depositor);
        vm.stopPrank();
        
        // донатим 1000 USDC напрямую в vault (симуляция процентов)
        usdc.mint(address(vault), 1000 * 1e6);
        
        // теперь totalAssets = 111_000 (100k setUp + 10k depositor + 1k донат)
        // но shares выпущено на 110_000 (100k setUp shares + 10k depositor shares)
        // share price вырос
        
        uint256 assetsPerShare = vault.convertToAssets(1e6);
        assertTrue(assetsPerShare > 1e6, "Share price should be above 1:1 after donation");
    }

    function test_MultipleDepositors_FairShares() public {
        // user1 депозитит первым
        address user1 = makeAddr("user1");
        usdc.mint(user1, 5000 * 1e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 5000 * 1e6);
        vault.deposit(5000 * 1e6, user1);
        vm.stopPrank();
        
        // user2 депозитит вторым (при том же share price)
        address user2 = makeAddr("user2");
        usdc.mint(user2, 3000 * 1e6);
        vm.startPrank(user2);
        usdc.approve(address(vault), 3000 * 1e6);
        vault.deposit(3000 * 1e6, user2);
        vm.stopPrank();
        
        // оба должны иметь shares пропорционально вкладу
        assertEq(vault.balanceOf(user1), 5000 * 1e6, "User1 should have 5000 shares");
        assertEq(vault.balanceOf(user2), 3000 * 1e6, "User2 should have 3000 shares");
    }

    function test_WithdrawWithBorrowedFunds() public {
        // user1 депозитит
        address user1 = makeAddr("user1");
        usdc.mint(user1, 5000 * 1e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 5000 * 1e6);
        vault.deposit(5000 * 1e6, user1);
        vm.stopPrank();
        
        address user2 = makeAddr("user2");
        vm.deal(user2, 1 ether);
        vm.startPrank(user2);
        vault.depositCollateral{value: 1 ether}();
        vault.borrow(1500 * 1e6); // Borrow 1500 USDC
        vm.stopPrank();
        
        address owner = vault.owner();
        vm.startPrank(owner);
        vm.expectRevert("Withdrawing this deposit will put your loan in a precarious situation; reduce the amount or pay off part of the debt.");
        vault.withdrawCollateral(user2, 0.5 ether); // Attempt to withdraw collateral
        vm.stopPrank();

        assertEq(vault.getCollateral(user2), 1 ether, "Collateral should remain unchanged");
        assertEq(vault.borrowed(user2), 1500 * 1e6, "Borrowed amount should remain unchanged");
    }

    function test_WithdrawWithBorrowedFunds_Success() public {
        // user1 депозитит
        address user1 = makeAddr("user1");
        usdc.mint(user1, 5000 * 1e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 5000 * 1e6);
        vault.deposit(5000 * 1e6, user1);
        vm.stopPrank();
        
        address user2 = makeAddr("user2");
        vm.deal(user2, 1 ether);
        vm.startPrank(user2);
        vault.depositCollateral{value: 1 ether}();
        vault.borrow(1000 * 1e6); // Borrow 1000 USDC
        vm.stopPrank();
        
        uint256 user2BalanceBefore = user2.balance; // Check user2's balance before withdrawal
        
        address owner = vault.owner();
        vm.startPrank(owner);
        vault.withdrawCollateral(user2, 0.2 ether); // Attempt to withdraw collateral
        vm.stopPrank();

        assertEq(user2.balance, user2BalanceBefore + 0.2 ether, "User2 should receive withdrawn collateral");
        assertEq(vault.getCollateral(user2), 0.8 ether, "Collateral should remain unchanged");
        assertEq(vault.borrowed(user2), 1000 * 1e6, "Borrowed amount should remain unchanged");
        
    }

    function test_WithdrawCollateral_AtLtvBoundary() public {
        // user1 депозитит
        address user1 = makeAddr("user1");
        usdc.mint(user1, 5000 * 1e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 5000 * 1e6);
        vault.deposit(5000 * 1e6, user1);
        vm.stopPrank();
    
        address user2 = makeAddr("user2");
        vm.deal(user2, 1 ether);
        vm.startPrank(user2);
        vault.depositCollateral{value: 1 ether}();
        vault.borrow(1200 * 1e6); // Borrow 1200 USDC
        vm.stopPrank();
        
        uint256 user2BalanceBefore = user2.balance; // Check user2's balance before withdrawal
        uint256 totalCollateralsBefore = vault.getTotalCollaterals();
        
        address owner = vault.owner();
        vm.startPrank(owner);
        vault.withdrawCollateral(user2, 0.2 ether); // Attempt to withdraw collateral
        vm.stopPrank();

        assertEq(user2.balance, user2BalanceBefore + 0.2 ether, "User2 should receive withdrawn collateral");
        assertEq(vault.getCollateral(user2), 0.8 ether, "Collateral should be reduced by withdrawn amount");
        assertEq(vault.borrowed(user2), 1200 * 1e6, "Borrowed amount should remain unchanged");
        assertEq(vault.getTotalCollaterals(), totalCollateralsBefore - 0.2 ether, "Total collaterals should be reduced by withdrawn amount");

    }

    function test_WithdrawCollateral_AtLtvBoundary_revert() public {
        // user1 депозитит
        address user1 = makeAddr("user1");
        usdc.mint(user1, 5000 * 1e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 5000 * 1e6);
        vault.deposit(5000 * 1e6, user1);
        vm.stopPrank();
    
        address user2 = makeAddr("user2");
        vm.deal(user2, 1 ether);
        vm.startPrank(user2);
        vault.depositCollateral{value: 1 ether}();
        vault.borrow(1200 * 1e6); // Borrow 1200 USDC
        vm.stopPrank();
        
        uint256 user2BalanceBefore = user2.balance; // Check user2's balance before withdrawal
        uint256 totalCollateralsBefore = vault.getTotalCollaterals();
        
        address owner = vault.owner();
        vm.startPrank(owner);
        vm.expectRevert("Withdrawing this deposit will put your loan in a precarious situation; reduce the amount or pay off part of the debt.");        
        vault.withdrawCollateral(user2, 0.2 ether + 1 wei); // Attempt to withdraw more than allowed by LTV boundary
        vm.stopPrank();

        assertEq(user2.balance, user2BalanceBefore, "User2 shouldn't receive withdrawn collateral");
        assertEq(vault.getCollateral(user2), 1 ether, "Collateral shouldn't be reduced by withdrawn amount");
        assertEq(vault.borrowed(user2), 1200 * 1e6, "Borrowed amount should remain unchanged");
        assertEq(vault.getTotalCollaterals(), totalCollateralsBefore, "Total collaterals shouldn't be reduced by withdrawn amount");

    }
}