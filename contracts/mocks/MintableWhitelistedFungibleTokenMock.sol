pragma solidity ^0.5.13;

import "../ValTokenWithHook.sol";

contract ValTokenWithHookMock is ValTokenWithHook {
    function mint(address _to, uint256 _value) external {
        _mint(_to, _value);
    }
}
