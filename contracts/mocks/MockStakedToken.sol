pragma solidity ^0.5.13;


import "../StakingAsset.sol";

contract MockStakedToken is StakedToken {
    StakingAsset stakeAsset_;
    StakingAsset rewardAsset_;
    Registry registry_;
    address liquidator_;

    constructor(StakingAsset _stakeAsset, StakingAsset _rewardAsset, Registry _registry, address _liquidator) public {
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
