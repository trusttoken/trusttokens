pragma solidity ^0.5.13;

import "../TrustToken.sol";

contract MockTrustToken is TrustToken {
    Registry registry_;

    constructor(Registry _registry) public {
        registry_ = _registry;
    }

    function registry() internal view returns (Registry) {
        return registry_;
    }

    // @dev faucet for testing TrustToken
    function faucet(address reciever, uint256 amount) public {
        require(amount <= 100000000000, "can only mint 1000 TRU at once");
        _mint(reciever, amount);
    }
}
