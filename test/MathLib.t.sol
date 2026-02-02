// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../src/libraries/MathLib.sol";
import "forge-std/Test.sol";

contract MathLibTest is Test {
    function test_WadMul_Rounding() public {
        uint a = 3e18;
        uint b = 0.5e18;
        uint result = MathLib.wadMul(a, b);
        assertEq(result, 1.5e18);
    }

    function test_WadMul_Rounding_Proof() public {
        uint a = 1;
        uint b = 5e17;
        uint result = MathLib.wadMul(a, b);
        assertEq(result, 1); // Если бы округления не было, тут был бы 0!
    }

    function test_RayDiv() public {
        uint a = 5e27;
        uint b = 2e27;
        uint result = MathLib.rayDiv(a, b);
        assertEq(result, 2.5e27);
    }

    function test_RayPow_2() public {
        uint x = 1.1e27; // 2 in RAY
        uint n = 2;
        uint result = MathLib.rayPow(x, n);
        assertEq(result, 1.21e27); // 1.1^2 = 1.21 in RAY
    }

    function test_RayPow_3() public {
        uint x = 2e27; // 2 in RAY
        uint n = 3;
        uint result = MathLib.rayPow(x, n);
        assertEq(result, 8e27); // 2^3 = 8 in RAY
    }

    function test_RayToWad_Rounding() public {
        uint ray = 1e27 + 0.6e9; // 1.0000000006 in RAY
        uint wad = MathLib.rayToWad(ray);
        assertEq(wad, 1e18 + 1);
    }

    function test_LargeNumbers() public {
        uint a = 1000000000e18; // 1 миллиард токенов
        uint b = 2e18;             // Множитель 2
        uint result = MathLib.wadMul(a, b);
        assertEq(result, 2000000000e18);
    }

}

