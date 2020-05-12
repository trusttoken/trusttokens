pragma solidity ^0.5.13;

import { StakedToken } from "./StakedToken.sol";
import "./StakedTokenProxy.sol";
import "./Proxy/OwnedUpgradeabilityProxy.sol";


/**
 * @title StakingOpportunityFactory
 * @dev A Registry for creating staking opportunities.
 * Creates and tracks instances of StakedTokens (staking opportunities)
 * Duplicates some ownership logic but with different storage.
 * Referenes the actual registry and has support for upgrade calls.
 */
contract StakingOpportunityFactory {
	address public owner;
	address public pendingOwner;
	Registry public registry; // actual registry

	// initial implemetation
	/*StakedTokenProxy*/ address public initializer;

	// current implementation
	address public currentImplementation;

	// flag from actual registry
	bytes32 constant IS_REGISTERED_CONTRACT = "isRegisteredContract";

	/**
	 * @dev Constructor for StakingOpportunityFactory.
	 * Initializes contract with real registry and first implementation.
	 * @param _registry registry to set (should be actual registry)
	 */
	constructor(Registry _registry, address /*StakedTokenProxy*/ _implementation) public {
		owner = msg.sender;
		emit OwnershipTransferred(address(0), owner);
		registry = _registry;
		currentImplementation = initializer = _implementation;
	}

	// events
	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
	event StakingOpportunity(StakedToken indexed opportunity, bool indexed upgradeable);
	event UpgradeFailure(address indexed proxy, address indexed priorImplementation, address indexed nextImplementation, bytes failure);

	/**
	 * @dev Creates a StakedToken (staking opportunity)
	 * Given a staking asset, reward asset, and liqudiator address creates
	 * a new staking opportunity and stores it in registry.
	 * @param _stakeAsset Asset to stake. Usually TRUST.
	 * @param _rewardAsset Asset to reward. Usually TUSD.
	 * @param _liquidator address of liquidator contract for this opportunity
	 * @return StakedToken created by this contract.
	 */
	function createStakingOpportunity(StakingAsset _stakeAsset, StakingAsset _rewardAsset, address _liquidator) external returns (StakedToken) {
		StakedToken result = new StakedToken(_stakeAsset, _rewardAsset, Registry(address(this)), _liquidator);
		// recieve fallbacks from TrueUSD and TrustTokens
		registry.setAttributeValue(address(result), IS_REGISTERED_CONTRACT, 1);
		emit StakingOpportunity(result, false);
		return result;
	}

	/**
	 * @dev Creates a StakedToken (staking opportunity)
	 * Given a staking asset, reward asset, and liqudiator address creates
	 * a new proxy staking opportunity and stores it in registry.
	 * @param _stakeAsset Asset to stake. Usually TRUST.
	 * @param _rewardAsset Asset to reward. Usually TUSD.
	 * @param _liquidator address of liquidator contract for this opportunity
	 * @return StakedToken created by this contract.
	 */
	function createProxyStakingOpportunity(StakingAsset _stakeAsset, StakingAsset _rewardAsset, address _liquidator) external returns (StakedToken) {
		OwnedUpgradeabilityProxy proxy = new OwnedUpgradeabilityProxy();
		address priorImplementation = initializer;
		proxy.upgradeTo(priorImplementation);
		StakedTokenProxy(address(proxy)).initialize(_stakeAsset, _rewardAsset, Registry(address(this)), _liquidator);
		address finalImplementation = currentImplementation;
		if (finalImplementation != priorImplementation) {
			proxy.upgradeTo(finalImplementation);
		}
		// set this as a registered contract so it can recieve fallback functions
		registry.setAttributeValue(address(proxy), IS_REGISTERED_CONTRACT, 1);
		emit StakingOpportunity(StakedToken(address(proxy)), true);
		return StakedToken(address(proxy));
	}

	/**
	 * @dev Sync attribute values to children.
	 * @param attribute attribute to sync
	 * @param accounts accounts to sync from
	 * @param subscribers subscribers to sync to
	 */
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

	/**
	 * @dev Upgrade all StakingAssets to new implementation
	 * Only owner can set a new implementation.
	 * @param _implementation new implementation
	 */
	function upgradeAllTo(address _implementation) onlyOwner external {
		bytes32 codeHash;
		assembly { codeHash := extcodehash(_implementation) }
		// ensure contract created correctly
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

	/**
	 * @dev Transfer ownership of this contract.
	 */
	function transferOwnership(address newOwner) public onlyOwner {
		pendingOwner = newOwner;
	}

	/**
	 * @dev Claim ownership of this contract.
	 */
	function claimOwnership() public onlyPendingOwner {
		emit OwnershipTransferred(owner, pendingOwner);
		owner = pendingOwner;
		pendingOwner = address(0);
	}

	/**
	 * @dev Migrate function is callable by anyone as long as it has proxy approval.
	 * Migrations are not foolproof, must be very careful when migrating.
	 * Risk is that if we store a bad upgrade implementation it will break.
	 */
	function migrate(OwnedUpgradeabilityProxy _proxy) external {
		address priorImplementation = _proxy.implementation();
		address finalImplementation = currentImplementation;
		// check proxy implementation versus final implemetation
		if (priorImplementation != finalImplementation) {
			_proxy.upgradeTo(finalImplementation);
		}
	}

	/**
	 * @dev Gets attribute value and forwards to real registry
	 * @param _account accout to request value from.
	 * @param _attribute attribute requested
	 */
	function getAttributeValue(address _account, bytes32 _attribute) external view returns (uint256) {
		return registry.getAttributeValue(_account, _attribute);
	}
}
