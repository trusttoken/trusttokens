pragma solidity ^0.5.13;


import "../StakingPool.sol";


contract MockStakingPool is StakingPool {
    Registry registry_;
    StakingAsset rewardAsset_;
    StakingAsset favoredAsset_;
    IERC20 uniswap_;
    address liquidator_;

    constructor(Registry _registry, StakingAsset _rewardAsset, StakingAsset _favoredAsset, IERC20 _uniswap, address _liquidator) public {
        registry_ = _registry;
        rewardAsset_ = _rewardAsset;
        favoredAsset_ = _favoredAsset;
        uniswap_ = _uniswap;
        liquidator_ = _liquidator;
    }
    
    function getExchange(IERC20 asset1, IERC20 asset2) internal view returns (IERC20) {
        return uniswap_;
    }

    function registry() internal view returns (Registry) {
        return registry_;
    }
    function rewardAsset() internal view returns (StakingAsset) {
        return rewardAsset_;
    }
    function favoredAsset() internal view returns (StakingAsset) {
        return favoredAsset_;
    }
    function liquidator() internal view returns (address) {
        return liquidator_;
    }
}
