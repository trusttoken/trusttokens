pragma solidity ^0.5.13;

import "./ERC20.sol";
import "./RegistrySubscriber.sol";

contract ValTokenWithHook is ModularStandardToken, RegistrySubscriber {

    event Burn(address indexed from, uint256 indexed amount);
    event Mint(address indexed to, uint256 indexed amount);

    function _resolveRecipient(address _to) internal view returns (address to, bool hook) {
        bytes32 flags = (attributes[uint144(uint160(_to) >> 20)]);
        if (flags == 0) {
            to = _to;
            attributes[uint144(uint160(to) >> 20)] = to;
            hook = false;
        } else {
            require(!(flags & ACCOUNT_BLACKLISTED), "blacklisted recipient");
            to = address(flags);
            hook = bool(flags & ACCOUNT_HOOK);
        }
    }

    function _resolveSender(address _from) internal view returns (address from) {
        bytes32 flags = (attributes[uint144(uint160(_from) >> 20)]);
        require(!(flags & ACCOUNT_BLACKLISTED), "blacklisted sender");
        from = address(flags);
        require(from == _from, "account collision");
    }

    function _transferFromAllArgs(address _from, address _to, uint256 _value, address _spender) internal {
        uint256 newAllowance = _subAllowance(_from, _spender, _value);
        _transferAllArgs(_from, _to, _value);
    }
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        _transferFromAllArgs(_from, _to, _value, msg.sender);
        return true;
    }
    function transfer(address _to, uint256 _value) external returns (bool) {
        _transferAllArgs(_resolveSender(msg.sender), _to, _value);
        return true;
    }
    function _transferAllArgs(address _from, address _to, uint256 _value) internal {
        uint256 loweredBalance = _subBalance(_resolveSender(_from), _value);
        bool hasHook;
        _to, hasHook = _resolveRecipient(_to);
        uint256 priorBalance = _addBalance(_to, _value);
        if (hasHook) {
            TrueCoinReceiver(_to).tokenFallback(_from, _value);
        }
    }

    function _burn(address _from, uint256 _value) internal {
        emit Transfer(_from, address(0), _value);
        emit Burn(_from, _value);
        _subBalance(_from, _value);
        totalSupply -= _value;
    }

    function _mint(address _to, uint256 _value) internal {
        emit Transfer(address(0), _to, _value);
        emit Mint(_to, _value);
        address to = _resolveRecipient(_to);
        if (_to != to) {
            emit Transfer(_to, to, _value);
        }
        _addBalance(to, _value);
        totalSupply += _value;
    }
}
