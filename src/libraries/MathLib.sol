// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library MathLib {
    uint constant WAD = 1e18;
    uint constant RAY = 1e27;
    function wadMul(uint a, uint b) internal pure returns (uint) {
        return (a * b + WAD / 2) / WAD;
    }

    function wadDiv(uint a, uint b) internal pure returns (uint) {
        require(b != 0, "Division by zero");
        return (a * WAD + b / 2) / b;
    }

    function rayMul(uint a, uint b) internal pure returns (uint) {
        return (a * b + RAY / 2) / RAY;
    }
    
    function rayDiv(uint a, uint b) internal pure returns (uint) {
        require(b != 0, "Division by zero");
        return (a * RAY + b / 2) / b;
    }

    function rayPow(uint x, uint n) internal pure returns (uint z) {
    z = n % 2 != 0 ? x : RAY;

    for (n /= 2; n != 0; n /= 2) {
        x = rayMul(x, x);
        if (n % 2 != 0) {
            z = rayMul(z, x);
        }
    }
    }

    function wadToRay(uint _wad) internal pure returns (uint) {
        return _wad * 1e9;
    }

    function rayToWad(uint _ray) internal pure returns (uint) {
        return (_ray + 1e9 / 2) / 1e9; // Тоже с округлением!
    }

}