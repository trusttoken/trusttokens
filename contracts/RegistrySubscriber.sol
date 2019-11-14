import "./ClaimableContract.sol";

contract RegistrySubscriber is ClaimableContract {
    event SetRegistry(address indexed registry);

    function setRegistry(Registry _registry) onlyOwner public {
        registry = _registry;
        emit SetRegistry(registry);
    }

    modifier onlyRegistry {
      require(msg.sender == address(registry));
      _;
    }

    function syncAttributeValue(address _who, bytes32 _attribute, uint256 _value) public onlyRegistry {
        attributes[_attribute][_who] = _value;
    }
}
