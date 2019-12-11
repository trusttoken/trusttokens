pragma solidity ^0.5.13;

import "../true-currencies/contracts/CompliantDepositTokenWithHook.sol";


contract TrustToken is CompliantDepositTokenWithHook {
    function decimals() public pure returns (uint8) {
        return 18;
    }
    function rounding() public pure returns (uint8) {
        return 18;
    }
    function name() public pure returns (string memory) {
        return "TrustToken";
    }
    function symbol() public pure returns (string memory) {
        return "TRU";
    }
}
