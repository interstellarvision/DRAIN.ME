// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; 
import "forge-std/Test.sol";
import "../src/DrainMe.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract BadOwner {
}

contract DrainMeTest is Test {
    receive() external payable {}
    MockUSDC public usdc;
    DrainMe public vault;
    address user = makeAddr("user"); 

    function setUp() public {
        usdc = new MockUSDC();
        vault = new DrainMe(address(usdc));
        vm.deal(user, 10 ether); 
        usdc.mint(address(this), 1_000_000 * 1e6); // 1M USDC
        usdc.approve(address(vault), 1_000_000 * 1e6);
        vault.provideLiquidity(100_000 * 1e6); // Заливаем 100k в пул
    }

    function test_Deposit() public {
        vm.startPrank(user); 
        
        vault.deposit{value: 1 ether}();
        
        assertEq(vault.deposits(user), 1 ether); 
        assertEq(address(vault).balance, 1 ether); 
        
        vm.stopPrank();
    }

    function test_Withdraw() public {
        vm.startPrank(user);
        vault.deposit{value: 5 ether}();
        
        vault.withdraw(2 ether);
        
        assertEq(vault.deposits(user), 3 ether);
        assertEq(address(vault).balance, 3 ether);
        vm.stopPrank();
    }

    function test_RevertOnInsufficientBalance() public {
        vm.startPrank(user);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Insufficient balance"); 
        vault.withdraw(2 ether); 
        vm.stopPrank();
    }

    function test_EmitsDepositedEvent() public {
        vm.expectEmit(true, false, false, true); 
        emit DrainMe.Deposited(user, 1 ether);
        
        vm.prank(user);
        vault.deposit{value: 1 ether}();
    }    

    function test_WithdrawActuallySendsETH() public {
        uint256 initialBalance = user.balance; 

        vm.startPrank(user);
        vault.deposit{value: 1 ether}();
        vault.withdraw(1 ether);
        vm.stopPrank();

        assertEq(user.balance, initialBalance, "User should have their ETH back");
    }

    function test_UserIsolation() public {
        address hacker = makeAddr("hacker");
        vm.deal(hacker, 1 ether);

        vm.prank(user);
        vault.deposit{value: 10 ether}();

        vm.prank(hacker);
        vault.deposit{value: 0.1 ether}();

        vm.startPrank(hacker);
        vm.expectRevert("Insufficient balance");
        vault.withdraw(5 ether);
        vm.stopPrank();
    }    

    function test_TotalDepositsFlow() public {
        address user2 = makeAddr("user2");
        vm.deal(user2, 5 ether);

        vm.prank(user);
        vault.deposit{value: 1 ether}();

        vm.prank(user2);
        vault.deposit{value: 2 ether}();

        assertEq(vault.totalDeposits(), 3 ether, "Total deposits mismatch after deposits");

        vm.prank(user);
        vault.withdraw(1 ether);

        assertEq(vault.totalDeposits(), 2 ether, "Total deposits mismatch after withdraw");
    }

    function test_RevertOnZeroDeposit() public {
        vm.startPrank(user);
        vm.expectRevert("Cannot deposit 0");
        vault.deposit{value: 0}();
        vm.stopPrank();
    }

    function test_RevertOnZeroWithdraw() public {
        vm.startPrank(user);
        vault.deposit{value: 1 ether}();
        
        vm.expectRevert("Cannot withdraw 0");
        vault.withdraw(0);
        vm.stopPrank();
    }

    function test_MultipleDepositsAndWithdrawals() public {
        vm.startPrank(user);

        vault.deposit{value: 3 ether}();
        assertEq(vault.deposits(user), 3 ether);
        vault.deposit{value: 5 ether}();
        assertEq(vault.deposits(user), 8 ether);
        vault.withdraw(vault.deposits(user));
        assertEq(vault.deposits(user), 0 ether);
        vm.stopPrank();
    }

    function test_getDeposit() public {
        vm.startPrank(user);
        vault.deposit{value: 2 ether}();
        uint256 deposit = vault.getDeposit(user);
        assertEq(deposit, 2 ether);
        vm.stopPrank();
    }

    function test_getTotalDeposits() public {
        address user2 = makeAddr("user2");
        vm.deal(user2, 3 ether);

        vm.prank(user);
        vault.deposit{value: 2 ether}();

        vm.prank(user2);
        vault.deposit{value: 3 ether}();

        uint256 total = vault.getTotalDeposits();
        assertEq(total, 5 ether);
    }

    function test_EmitsWithdrawnEvent() public {
        vm.startPrank(user);
        vault.deposit{value: 1 ether}();
        vm.expectEmit(true, false, false, true); 
        emit DrainMe.Withdrawn(user, 1 ether);
        
        vault.withdraw(1 ether);
        vm.stopPrank();
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

    function test_CollateralIsolation() public {
        address user2 = makeAddr("user2");
        vm.deal(user, 2 ether);
        vm.deal(user2, 4 ether);
        vm.startPrank(user);
        vault.deposit{value: 2 ether}();
        vm.stopPrank();
        vm.startPrank(user2);
        vault.depositCollateral{value: 4 ether}();
        vm.stopPrank();
        uint256 totalCollateral = vault.getTotalCollaterals();
        assertEq(totalCollateral, 4 ether);
        uint256 totalDeposit = vault.getTotalDeposits();
        assertEq(totalDeposit, 2 ether);
    }

    function test_EmergencyWithdraw_Success() public {
        address owner = vault.owner();
        vm.deal(address(vault), 10 ether);
        vm.startPrank(owner);
        vm.expectEmit(false, false, false, true);
        emit DrainMe.EmergencyWithdrawn(10 ether);
        vault.emergencyWithdraw();
        vm.stopPrank();
        assertEq(address(vault).balance, 0, "Vault balance should be zero after emergency withdraw");
    }

    function test_EmergencyWithdraw_PendingWhenFail() public {
        BadOwner badOwner = new BadOwner();
        

        vault.transferOwnership(address(badOwner));
        vm.deal(user, 10 ether);
        vm.prank(user);
        vault.deposit{value: 5 ether}();

        vm.prank(address(badOwner));
        vault.emergencyWithdraw();

        assertEq(address(badOwner).balance, 0);
        assertEq(vault.pendingWithdrawals(address(badOwner)), 5 ether);
        assertEq(vault.getTotalDeposits(), 5 ether);
    }   

    function test_ClaimPendingWithdrawal_AfterOwnershipTransfer() public {
        BadOwner badOwner = new BadOwner();
        address goodUser = makeAddr("goodUser");
        
        vm.deal(address(this), 10 ether);
        vault.deposit{value: 10 ether}();
        
        vault.transferOwnership(address(badOwner));
        
        vm.prank(address(badOwner));
        vault.emergencyWithdraw();
        assertEq(vault.pendingWithdrawals(address(badOwner)), 10 ether);

        vm.prank(address(badOwner));
        vault.claimPendingWithdrawal(address(badOwner), payable(goodUser));
        assertEq(vault.pendingWithdrawals(address(badOwner)), 0);
        assertEq(goodUser.balance, 10 ether);
    }

    function test_Reentrancy_Protected() public {
        vm.deal(user, 10 ether);
        vm.prank(user);
        vault.deposit{value: 10 ether}();

        Attacker attacker = new Attacker(vault);
        vm.deal(address(attacker), 1 ether);

        vm.prank(address(attacker));
        vm.expectRevert("Transfer failed");
        attacker.attack{value: 1 ether}();
        assertEq(address(vault).balance, 10 ether);
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
        vault.borrow(9000 * 10 ** 6); // Attempt to borrow more than 80% of collateral value
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

    function test_ProvideLiquidity_Success() public {
        address owner = vault.owner();
        vm.prank(owner);
        vault.provideLiquidity(50_000 * 10 ** 6); // Provide additional liquidity
        assertEq(usdc.balanceOf(address(vault)), 150_000 * 10 ** 6, "Vault USDC balance should increase");
    }

    function test_ProvideLiquidity_OnlyOwner_Reverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vault.provideLiquidity(50_000 * 10 ** 6);
    }
}

    contract Attacker {
    DrainMe vault;
    constructor(DrainMe _vault) { vault = _vault; }

    function attack() external payable {
        vault.deposit{value: msg.value}();
        vault.withdraw(msg.value);
    }

    receive() external payable {
        if (address(vault).balance >= msg.value) {
            vault.withdraw(msg.value);
        }
    }
}



