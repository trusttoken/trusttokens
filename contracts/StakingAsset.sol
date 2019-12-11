pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./ValTokenWithHook.sol";

contract StakingAsset is IERC20 {
    function name() external returns (string memory);
    function symbol() external returns (string memory);
}

contract RewardPool {
    function rewardAsset() internal view returns (StakingAsset);

    constructor(address _liquidator, address _owner) public {
        rewardAsset().approve(_liquidator, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        rewardAsset().approve(_owner, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }
 
    function tokenFallback(address /*_originalSender*/, uint256 /*_amount*/) external view {
        assert(msg.sender == address(rewardAsset()));
    }
}


contract StakedToken is ValTokenWithHook {
    using SafeMath for uint256;

    uint256 cumulativeRewardsPerStake;
    mapping (address => uint256) claimedRewardsPerStake;
    uint256 rewardsRemainder;

    /**
        Returns the withdrawable amount of rewards belonging to this staker
    **/
    function unclaimedRewards(address _staker) public view returns (uint256 unclaimedRewards_) {
        uint256 stake = balanceOf[_staker];
        if (stake == 0) {
            return 0;
        }
        unclaimedRewards_ = stake.mul(cumulativeRewardsPerStake.sub(claimedRewardsPerStake[_staker], "underflow"), "overflow");
    }

    function stakeAsset() internal view returns (StakingAsset);
    function rewardPool() internal view returns (RewardPool);

    /**
        Issue stake to _staker according to _amount
        Invoked after _amount is deposited in this contract
    */
    function _deposit(address _staker, uint256 _amount) internal {
        uint256 balance = stakeAsset().balanceOf(address(this));
        uint256 stakeAmount;
        if (_amount < balance) {
            stakeAmount = _amount.mul(totalSupply, "overflow").div(balance - _amount, "insufficient deposit");
        } else {
            // first staker
            require(totalSupply == 0);
            stakeAmount = _amount * 2100;
        }
        _mint(_staker, stakeAmount);
    }

    function tokenFallback(address _originalSender, uint256 _amount) external {
        require(msg.sender == address(stakeAsset()), "Wrong token");
        _deposit(_originalSender, _amount);
    }

    function deposit(uint256 _amount) external {
        require(stakeAsset().transferFrom(msg.sender, address(this), _amount));
    }

    function award(uint256 _amount) external {
        require(stakeAsset().transferFrom(msg.sender, address(rewardPool()), _amount));
        uint256 remainder = rewardsRemainder.add(_amount, "overflow");
        uint256 totalStake = totalSupply;
        uint256 rewardsAdded = remainder.div(totalStake, "total stake is zero");
        rewardsRemainder = remainder % totalStake;
        cumulativeRewardsPerStake = cumulativeRewardsPerStake.add(rewardsAdded, "cumulative rewards overflow");
    }
}
