pragma solidity ^0.5.13;

import "./mocks/MockStakedToken.sol";
import "./mocks/StakedTokenProxyImplementation.sol";
import "../true-currencies/contracts/Proxy/OwnedUpgradeabilityProxy.sol";

contract StakingOpportunityFactory {
    address public owner;
    address public pendingOwner;
    Registry public registry;
    /*StakedTokenProxyImplementation*/ address public initializer;
    address public currentImplementation;

    bytes32 constant IS_REGISTERED_CONTRACT = "isRegisteredContract";

    constructor(Registry _registry, address /*StakedTokenProxyImplementation*/ _implementation) public {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
        registry = _registry;
        currentImplementation = initializer = _implementation;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event StakingOpportunity(StakedToken indexed opportunity, bool indexed upgradeable);
    event UpgradeFailure(address indexed proxy, address indexed priorImplementation, address indexed nextImplementation, bytes failure);

    function createStakingOpportunity(StakingAsset _stakeAsset, StakingAsset _rewardAsset, address _liquidator) external returns (StakedToken) {
        StakedToken result = new MockStakedToken(_stakeAsset, _rewardAsset, Registry(address(this)), _liquidator);
        registry.setAttributeValue(address(result), IS_REGISTERED_CONTRACT, 1);
        emit StakingOpportunity(result, false);
        return result;
    }

    function createProxyStakingOpportunity(StakingAsset _stakeAsset, StakingAsset _rewardAsset, address _liquidator) external returns (StakedToken) {
        OwnedUpgradeabilityProxy proxy = new OwnedUpgradeabilityProxy();
        address priorImplementation = initializer;
        proxy.upgradeTo(priorImplementation);
        StakedTokenProxyImplementation(address(proxy)).initialize(_stakeAsset, _rewardAsset, Registry(address(this)), _liquidator);
        address finalImplementation = currentImplementation;
        if (finalImplementation != priorImplementation) {
            proxy.upgradeTo(finalImplementation);
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

    bytes32 constant EMPTY_CONTRACT = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    function upgradeAllTo(address _implementation) onlyOwner external {
        bytes32 codeHash;
        assembly { codeHash := extcodehash(_implementation) }
        require(codeHash != 0x0 && codeHash != EMPTY_CONTRACT);
        currentImplementation = _implementation;
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

    function migrate(OwnedUpgradeabilityProxy _proxy) external {
        address priorImplementation = _proxy.implementation();
        address finalImplementation = currentImplementation;
        if (priorImplementation != finalImplementation) {
            _proxy.upgradeTo(finalImplementation);
        }
    }

    function getAttributeValue(address _account, bytes32 _attribute) external view returns (uint256) {
        return registry.getAttributeValue(_account, _attribute);
    }
}
