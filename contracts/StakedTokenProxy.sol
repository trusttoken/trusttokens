pragma solidity 0.5.13;

import { StakingAsset } from "./StakingAsset.sol";
import { AStakedToken } from "./AStakedToken.sol";
import { Registry } from "@trusttoken/registry/contracts/Registry.sol";
import { RegistrySubscriber } from "./RegistrySubscriber.sol";

/**
 * @title StakedTokenProxy
 * @dev Proxy Implementation of AStakedToken
**/
contract StakedTokenProxy is AStakedToken {
    StakingAsset stakeAsset_;
    StakingAsset rewardAsset_;
    Registry registry_;
    address liquidator_;

    constructor() public {
    }

    function initialize(StakingAsset _stakeAsset, StakingAsset _rewardAsset, Registry _registry, address _liquidator) external {
        require(address(registry_) == address(0));
        stakeAsset_ = _stakeAsset;
        rewardAsset_ = _rewardAsset;
        registry_ = _registry;
        liquidator_ = _liquidator;
        initialize();
    }
    function stakeAsset() internal view returns (StakingAsset) {
        return stakeAsset_;
    }
    function rewardAsset() internal view returns (StakingAsset) {
        return rewardAsset_;
    }
    function registry() internal view returns (Registry) {
        return registry_;
    }
    function liquidator() internal view returns (address) {
        return liquidator_;
    }
}

contract StakedTokenProxyMigration is StakedTokenProxy {
    uint256 public importantNumber;
    function onUpgrade(uint256 _importantNumber) external {
        require(importantNumber == 0, "already migrated");
        importantNumber = _importantNumber;
    }
}
