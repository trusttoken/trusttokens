pragma solidity ^0.5.13;

import "./mocks/MockStakedToken.sol";
import "./mocks/StakedTokenProxyImplementation.sol";
import "../true-currencies/contracts/Proxy/OwnedUpgradeabilityProxy.sol";

contract StakingOpportunityFactory {
    address public owner;
    address public pendingOwner;
    Registry public registry;
    /*StakedTokenProxyImplementation*/ address public implementation;
    bytes public upgradeCall;

    bytes32 constant IS_REGISTERED_CONTRACT = "isRegisteredContract";

    constructor(Registry _registry, address /*StakedTokenProxyImplementation*/ _implementation) public {
        registry = _registry;
        implementation = _implementation;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event StakingOpportunity(StakedToken indexed opportunity, bool upgradeable);
    event UpgradeFailure(address indexed proxy, address indexed priorImplementation, address indexed nextImplementation, bytes failure);
 
    function createStakingOpportunity(StakingAsset _stakeAsset, StakingAsset _rewardAsset, address _liquidator) external returns (StakedToken) {
        StakedToken result = new MockStakedToken(_stakeAsset, _rewardAsset, Registry(address(this)), _liquidator);
        registry.setAttributeValue(address(result), IS_REGISTERED_CONTRACT, 1);
        emit StakingOpportunity(result, false);
        return result;
    }

    function createProxyStakingOpportunity(StakingAsset _stakeAsset, StakingAsset _rewardAsset, address _liquidator) external returns (StakedToken) {
        OwnedUpgradeabilityProxy proxy = new OwnedUpgradeabilityProxy();
        proxy.upgradeTo(implementation);
        StakedTokenProxyImplementation(address(proxy)).initialize(_stakeAsset, _rewardAsset, Registry(address(this)), _liquidator);

        registry.setAttributeValue(address(proxy), IS_REGISTERED_CONTRACT, 1);
        return StakedToken(address(proxy));
    }

    function syncAttributeValues(bytes32 attribute, address[] calldata accounts, RegistrySubscriber[] calldata subscribers) external {
        for (uint256 i = subscribers.length; i --> 0;) {
            RegistrySubscriber subscriber = subscribers[i];
            for (uint256 j = accounts.length; j --> 0; ) {
                address account = accounts[j];
                subscriber.syncAttributeValue(account, attribute, registry.getAttributeValue(account, attribute));
            }
        }
    }

    function setDefaultImplementation(address _implementation, bytes calldata _upgradeCall) onlyOwner external {
        implementation = _implementation;
        upgradeCall = _upgradeCall;
    }

    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "only pending owner");
        _;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner = newOwner;
    }

    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function upgrade(OwnedUpgradeabilityProxy _proxy) external {
        address _implementation = implementation;
        address priorImplementation = _proxy.implementation();
        require(priorImplementation == _implementation);
        _proxy.upgradeTo(_implementation);
        if (upgradeCall.length > 3) {
            (bool success, bytes memory result) = address(_proxy).call(upgradeCall);
            if (!success) {
                emit UpgradeFailure(address(_proxy), priorImplementation, address(_implementation), result);
                // revert
                _proxy.upgradeTo(priorImplementation);
            }
        }
    }
}
