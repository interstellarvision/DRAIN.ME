// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; 
import "forge-std/Test.sol";
import "../src/DrainMe.sol";

contract BadOwner {
}

import "forge-std/Test.sol";
import "../src/DrainMe.sol"; 

contract DrainMeTest is Test {
    receive() external payable {}
    DrainMe public vault;
    address user = makeAddr("user"); 

    function setUp() public {
        vault = new DrainMe();
        vm.deal(user, 10 ether); 
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



