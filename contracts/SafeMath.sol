pragma solidity ^0.4.23;

/**
 * Forked subset of Openzeppelin SafeMath allowing custom underflow/overflow messages
 */
library SafeMath {
    function add(uint256 a, uint256 b, string memory overflowMessage) internal pure returns (uint256 result) {
        result = a + b;
        require(result >= a, overflowMessage);
    }
    function sub(uint256 a, uint256 b, string memory underflowMessage) internal pure returns (uint256 result) {
        require(b <= a, underflowMessage);
        result = a - b;
    }
}
