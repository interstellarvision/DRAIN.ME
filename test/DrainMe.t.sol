// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DrainMe.sol"; // Путь к твоему контракту

contract DrainMeTest is Test {
    DrainMe public vault;
    address user = makeAddr("user"); // Создаем виртуального юзера

    // 1. Подготовка
    function setUp() public {
        vault = new DrainMe();
        vm.deal(user, 10 ether); // Даем юзеру 10 тестовых эфиров
    }

    // 2. Тест депозита
    function test_Deposit() public {
        vm.startPrank(user); // Говорим Foundry: "Дальше все действия делает этот юзер"
        
        vault.deposit{value: 1 ether}();
        
        assertEq(vault.deposits(user), 1 ether); // Проверяем баланс в маппинге
        assertEq(address(vault).balance, 1 ether); // Проверяем реальный баланс контракта
        
        vm.stopPrank();
    }

    // 3. Тест вывода
    function test_Withdraw() public {
        vm.startPrank(user);
        vault.deposit{value: 5 ether}();
        
        vault.withdraw(2 ether);
        
        assertEq(vault.deposits(user), 3 ether);
        assertEq(address(vault).balance, 3 ether);
        vm.stopPrank();
    }

    // 4. Тест безопасности (ожидаем ошибку)
    function test_RevertOnInsufficientBalance() public {
        vm.startPrank(user);
        vault.deposit{value: 1 ether}();

        vm.expectRevert("Insufficient balance"); // Мы ждем именно эту ошибку
        vault.withdraw(2 ether); // Юзер пытается снять больше, чем есть
        vm.stopPrank();
    }

    function test_EmitsDepositedEvent() public {
        // Ждем ивент: (проверять ли адрес, проверять ли сумму, ...)
        vm.expectEmit(true, false, false, true); 
        emit DrainMe.Deposited(user, 1 ether);
        
        vm.prank(user);
        vault.deposit{value: 1 ether}();
    }    

    function test_WithdrawActuallySendsETH() public {
        uint256 initialBalance = user.balance; // Сохраняем сколько было

        vm.startPrank(user);
        vault.deposit{value: 1 ether}();
        vault.withdraw(1 ether);
        vm.stopPrank();

        assertEq(user.balance, initialBalance, "User should have their ETH back");
    }

    function test_UserIsolation() public {
        address hacker = makeAddr("hacker");
        vm.deal(hacker, 1 ether);

        // Юзер 1 депает 10 ETH
        vm.prank(user);
        vault.deposit{value: 10 ether}();

        // Хакер депает 0.1 ETH
        vm.prank(hacker);
        vault.deposit{value: 0.1 ether}();

        // Хакер пытается снять 5 ETH (деньги юзера 1)
        vm.startPrank(hacker);
        vm.expectRevert("Insufficient balance");
        vault.withdraw(5 ether);
        vm.stopPrank();
    }    

    function test_TotalDepositsFlow() public {
        address user2 = makeAddr("user2");
        vm.deal(user2, 5 ether);

        // Юзер 1 кладет 1 ETH
        vm.prank(user);
        vault.deposit{value: 1 ether}();

        // Юзер 2 кладет 2 ETH
        vm.prank(user2);
        vault.deposit{value: 2 ether}();

        assertEq(vault.totalDeposits(), 3 ether, "Total deposits mismatch after deposits");

        // Юзер 1 забирает всё
        vm.prank(user);
        vault.withdraw(1 ether);

        assertEq(vault.totalDeposits(), 2 ether, "Total deposits mismatch after withdraw");
    }

// Проверка: нельзя положить 0
    function test_RevertOnZeroDeposit() public {
        vm.startPrank(user);
        vm.expectRevert("Cannot deposit 0");
        vault.deposit{value: 0}();
        vm.stopPrank();
    }

    // Проверка: нельзя снять 0
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
        // Ждем ивент: (проверять ли адрес, проверять ли сумму, ...)
        vm.expectEmit(true, false, false, true); 
        emit DrainMe.Withdrawn(user, 1 ether);
        
        vault.withdraw(1 ether);
        vm.stopPrank();
    }    

}