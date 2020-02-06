pragma solidity ^0.5.13;

import "./mocks/MockStakedToken.sol";
import "./mocks/StakedTokenProxyImplementation.sol";
import "../true-currencies/contracts/Proxy/OwnedUpgradeabilityProxy.sol";

contract StakingOpportunityFactory {
    address public owner;
    address public pendingOwner;
    Registry public registry;
    /*StakedTokenProxyImplementation*/ address[] public migrations;
    bytes[] public upgradeCalls;

    bytes32 constant IS_REGISTERED_CONTRACT = "isRegisteredContract";

    constructor(Registry _registry, address /*StakedTokenProxyImplementation*/ _implementation) public {
        owner = msg.sender;
        registry = _registry;
        migrations.push(_implementation);
        upgradeCalls.push("");
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event StakingOpportunity(StakedToken indexed opportunity, bool upgradeable);
    event UpgradeFailure(address indexed proxy, address indexed priorImplementation, address indexed nextImplementation, bytes failure);
 
    function migrationCount() public view returns (uint256) {
        return migrations.length;
    }

    function createStakingOpportunity(StakingAsset _stakeAsset, StakingAsset _rewardAsset, address _liquidator) external returns (StakedToken) {
        StakedToken result = new MockStakedToken(_stakeAsset, _rewardAsset, Registry(address(this)), _liquidator);
        registry.setAttributeValue(address(result), IS_REGISTERED_CONTRACT, 1);
        emit StakingOpportunity(result, false);
        return result;
    }

    function createProxyStakingOpportunity(StakingAsset _stakeAsset, StakingAsset _rewardAsset, address _liquidator) external returns (StakedToken) {
        OwnedUpgradeabilityProxy proxy = new OwnedUpgradeabilityProxy();
        address priorImplementation = migrations[0];
        proxy.upgradeTo(priorImplementation);
        StakedTokenProxyImplementation(address(proxy)).initialize(_stakeAsset, _rewardAsset, Registry(address(this)), _liquidator);
        uint256 _currentVersion = 0;
        uint256 _toVersion = migrations.length - 1;
        while(_currentVersion ++< _toVersion && gasleft() > 50000) {
            address nextImplementation = migrations[_currentVersion];
            proxy.upgradeTo(nextImplementation);
            if (upgradeCalls[_currentVersion].length > 3) {
                (bool success, bytes memory result) = address(proxy).call(upgradeCalls[_currentVersion]);
                if (!success) {
                    emit UpgradeFailure(address(proxy), priorImplementation, address(nextImplementation), result);
                    // revert upgrade and stop
                    proxy.upgradeTo(priorImplementation);
                    break;
                }
            }
            priorImplementation = nextImplementation;
        }

        registry.setAttributeValue(address(proxy), IS_REGISTERED_CONTRACT, 1);
        emit StakingOpportunity(StakedToken(address(proxy)), true);
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

    function appendMigration(address _implementation, bytes calldata _upgradeCall) onlyOwner external {
        migrations.push(_implementation);
        upgradeCalls.push(_upgradeCall);
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

    function migrateFrom(OwnedUpgradeabilityProxy _proxy, uint256 _currentVersion, uint256 _toVersion) external {
        address priorImplementation = _proxy.implementation();
        require(priorImplementation == migrations[_currentVersion]);
        while(_currentVersion ++< _toVersion) {
            address nextImplementation = migrations[_currentVersion];
            _proxy.upgradeTo(nextImplementation);
            if (upgradeCalls[_currentVersion].length > 3) {
                (bool success, bytes memory result) = address(_proxy).call(upgradeCalls[_currentVersion]);
                if (!success) {
                    emit UpgradeFailure(address(_proxy), priorImplementation, address(nextImplementation), result);
                    // revert upgrade and stop
                    _proxy.upgradeTo(priorImplementation);
                    return;
                }
            }
            priorImplementation = nextImplementation;
        }
    }
}
