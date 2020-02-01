pragma solidity ^0.5.13;

import "./ValTokenWithHook.sol";


contract TrustToken is ValTokenWithHook {
    function decimals() public pure returns (uint8) {
        return 8;
    }
    function rounding() public pure returns (uint8) {
        return 8;
    }
    function name() public pure returns (string memory) {
        return "TrustToken";
    }
    function symbol() public pure returns (string memory) {
        return "TRUST";
    }
}
