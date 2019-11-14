pragma solidity ^0.4.23;

import "./WhitelistedFungibleToken.sol";

contract MintableWhitelistedFungibleToken is WhitelistedFungibleToken {
    event Mint(address indexed to, uint256 indexed amount);

    function mint(address _to, uint256 _value) external {
        emit Transfer(address(0), _to, _value);
        emit Mint(_to, _value);
        address to = _resolveRecipient(_to);
        if (_to != to) {
            emit Transfer(_to, to, _value);
        }
        require(attributes[PASSED_KYCAML][to] != 0, "unregistered recipient; visit app.trusttoken.com");
        _addBalance(to, _value);
        totalSupply += _value;
    }
}
