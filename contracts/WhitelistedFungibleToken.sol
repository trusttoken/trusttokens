pragma solidity ^0.4.23;

import "./ERC20.sol";
import "./RegistrySubscriber.sol";

contract WhitelistedFungibleToken is ModularStandardToken, RegistrySubscriber {
    bytes32 constant PASSED_KYCAML = "hasPassedKYC/AML";
    bytes32 constant IS_DEPOSIT_ADDRESS = "isDepositAddress";

    event Burn(address indexed from, uint256 indexed amount);

    function _resolveRecipient(address _to) internal view returns (address to) {
        to = address(attributes[IS_DEPOSIT_ADDRESS][address(uint160(to) >> 20)]);
        if (to == 0) {
            to = _to;
        }
    }

    function _transferFromAllArgs(address _from, address _to, uint256 _value, address _spender) internal {
        require(attributes[PASSED_KYCAML][_from] != 0, "blacklisted sender; contact support@trusttoken.com");
        uint256 newAllowance = _subAllowance(_from, _spender, _value);
        uint256 loweredBalance = _subBalance(_from, _value);
        _to = _resolveRecipient(_to);
        require(attributes[PASSED_KYCAML][_to] != 0, "unregistered recipient; visit app.trusttoken.com");
        uint256 priorBalance = _addBalance(_to, _value);
    }
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        _transferFromAllArgs(_from, _to, _value, msg.sender);
        return true;
    }
    function transfer(address _to, uint256 _value) external returns (bool) {
        _transferAllArgs(msg.sender, _to, _value);
        return true;
    }
    function _transferAllArgs(address _from, address _to, uint256 _value) internal {
        require(attributes[PASSED_KYCAML][_from] != 0, "blacklisted sender; contact support@trusttoken.com");
        uint256 loweredBalance = _subBalance(_from, _value);
        _to = _resolveRecipient(_to);
        require(attributes[PASSED_KYCAML][_to] != 0, "unrecognized recipient");
        uint256 priorBalance = _addBalance(_to, _value);
    }


    function burn(uint256 _value) external {
        _burnAllArgs(msg.sender, _value);
    }

    function _burnAllArgs(address _from, uint256 _value) internal {
        emit Transfer(_from, address(0), _value);
        emit Burn(_from, _value);
        _subBalance(_from, _value);
        totalSupply -= _value;
    }
}
