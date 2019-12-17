pragma solidity ^0.5.13;

import "../TrustToken.sol";

contract MockTrustToken is TrustToken {
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
