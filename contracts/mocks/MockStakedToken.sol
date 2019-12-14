pragma solidity ^0.5.13;


import "../StakingAsset.sol";

contract MockRewardPool is RewardPool {
    StakingAsset rewardAsset_;

    function rewardAsset() internal view returns (StakingAsset) {
        return rewardAsset_;
    }

    constructor(StakingAsset _rewardAsset, address _liquidator, address _owner) RewardPool(_liquidator, _owner) public {
        rewardAsset_ = _rewardAsset;
    }
}

contract MockStakedToken is StakedToken {
    StakingAsset stakeAsset_;
    StakingAsset rewardAsset_;
    RewardPool rewardPool_;
    Registry registry_;

    constructor(StakingAsset _stakeAsset, StakingAsset _rewardAsset, Registry _registry, address _liquidator) public {
        stakeAsset_ = _stakeAsset;
        rewardAsset_ = _rewardAsset;
        registry_ = _registry;
        rewardPool_ = new MockRewardPool(_rewardAsset, _liquidator, address(this));
    }
    function stakeAsset() internal view returns (StakingAsset) {
        return stakeAsset_;
    }
    function rewardAsset() internal view returns (StakingAsset) {
        return rewardAsset_;
    }
    function rewardPool() internal view returns (RewardPool) {
        return rewardPool_;
    }
    function registry() internal view returns (Registry) {
        return registry_;
    }
}
