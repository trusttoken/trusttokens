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
    uint256 stakePendingWithdrawal;
    mapping (address => mapping (uint256 => uint256)) pendingWithdrawals;

    uint256 constant UNSTAKE_PERIOD = 21 days;
    event PendingWithdrawal(address indexed staker, uint256 indexed timestamp, uint256 indexed amount);

    /**
        Returns the withdrawable amount of rewards belonging to this staker
    **/
    function unclaimedRewards(address _staker) public view returns (uint256 unclaimedRewards_) {
        uint256 stake = balanceOf[_staker];
        if (stake == 0) {
            return 0;
        }
        unclaimedRewards_ = stake.mul(cumulativeRewardsPerStake.sub(claimedRewardsPerStake[_staker], "underflow"), "unclaimed rewards overflow");
    }

    function stakeAsset() internal view returns (StakingAsset);
    function rewardAsset() internal view returns (StakingAsset);
    function rewardPool() internal view returns (RewardPool);

    function _transferAllArgs(address _from, address _to, uint256 _value) internal {
        uint256 priorRewards = claimedRewardsPerStake[msg.sender];
        uint256 resultBalance = _subBalance(_resolveSender(_from), _value);
        if (resultBalance == 0) {
            claimedRewardsPerStake[msg.sender] = 0;
        }
        emit Transfer(_from, _to, _value);
        bool hasHook;
        address to;
        (to, hasHook) = _resolveRecipient(_to);
        if (_to != to) {
            emit Transfer(_to, to, _value);
        }
        uint256 priorBalance = _addBalance(to, _value);
        if (priorBalance > _value) {
            claimedRewardsPerStake[to] = (_value * priorRewards + priorBalance * claimedRewardsPerStake[to]) / (_value + priorBalance);
        } else {
            claimedRewardsPerStake[to] = cumulativeRewardsPerStake;
        }
        if (hasHook) {
            TrueCoinReceiver(to).tokenFallback(_from, _value);
        }
    }

    /**
     * At award time, award is not distributed to pending withdrawals
     * At deposit time, pending withdrawals are remembered to calculate stake per deposit
     * At slash time, pending withdrawals are slashed
     * So, pending withdrawals are quantified in stake
     * Pending withdrawals reduce both
     *
     */
    function _burn(address _from, uint256 _value) internal returns (uint256 resultBalance_, uint256 resultSupply_) {
        (resultBalance_, resultSupply_) = super._burn(_from, _value);
        uint256 userClaimedRewardsPerStake = claimedRewardsPerStake[_from];
        uint256 totalRewardsPerStake = cumulativeRewardsPerStake;
        uint256 pendingRewards = (totalRewardsPerStake - userClaimedRewardsPerStake) * _value;
        if (resultBalance_ == 0) {
            // pay out the unclaimed rewards to the pool
            cumulativeRewardsPerStake = totalRewardsPerStake + pendingRewards / resultSupply_;
            rewardsRemainder = rewardsRemainder.add(pendingRewards % resultSupply_, "rewardsRemainder overflow");
        } else {
            // merge unclaimed rewards with remaining balance
            // TODO this can go negative
            claimedRewardsPerStake[_from] = userClaimedRewardsPerStake - pendingRewards / resultBalance_;
            rewardsRemainder = rewardsRemainder.add(pendingRewards % resultBalance_, "rewardsRemainder overflow");
        }
    }

    function _mint(address _to, uint256 _value) internal {
        emit Transfer(address(0), _to, _value);
        emit Mint(_to, _value);
        (address to, bool hook) = _resolveRecipient(_to);
        if (_to != to) {
            emit Transfer(_to, to, _value);
        }
        uint256 priorBalance = _addBalance(to, _value);
        claimedRewardsPerStake[_to] = (cumulativeRewardsPerStake * _value + claimedRewardsPerStake[_to] * priorBalance) / (priorBalance + _value);
        totalSupply += _value;
        if (hook) {
            TrueCoinReceiver(to).tokenFallback(address(0x0), _value);
        }
    }

    /**
        Issue stake to _staker according to _amount
        Invoked after _amount is deposited in this contract
    */
    function _deposit(address _staker, uint256 _amount) internal {
        uint256 balance = stakeAsset().balanceOf(address(this));
        uint256 stakeAmount;
        if (_amount < balance) {
            stakeAmount = _amount.mul(totalSupply.add(stakePendingWithdrawal, "stakePendingWithdrawal > totalSupply"), "overflow").div(balance - _amount, "insufficient deposit");
        } else {
            // first staker
            require(totalSupply == 0, "pool drained");
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

    function initUnstake(uint256 _maxAmount) external {
        uint256 unstake = balanceOf[msg.sender];
        if (unstake > _maxAmount) {
            unstake = _maxAmount;
        }
        _burn(msg.sender, unstake);
        stakePendingWithdrawal = stakePendingWithdrawal.add(unstake, "stakePendingWithdrawal overflow");
        pendingWithdrawals[msg.sender][now] = pendingWithdrawals[msg.sender][now].add(unstake, "pendingWithdrawals overflow");
        emit PendingWithdrawal(msg.sender, now, unstake);
    }

    function finalizeUnstake(uint256[] calldata _timestamps) external {
        uint256 total = 0;
        for (uint256 i = _timestamps.length; i --> 0;) {
            uint256 timestamp = _timestamps[i];
            require(timestamp + UNSTAKE_PERIOD < now);
            total = total.add(pendingWithdrawals[msg.sender][timestamp], "stake overflow");
            pendingWithdrawals[msg.sender][timestamp] = 0;
        }
        stakePendingWithdrawal = stakePendingWithdrawal.sub(total, "stakePendingWithdrawal underflow");
    }

    function award(uint256 _amount) external {
        require(rewardAsset().transferFrom(msg.sender, address(rewardPool()), _amount));
        uint256 remainder = rewardsRemainder.add(_amount, "overflow");
        uint256 totalStake = totalSupply;
        uint256 rewardsAdded = remainder.div(totalStake, "total stake is zero");
        rewardsRemainder = remainder % totalStake;
        cumulativeRewardsPerStake = cumulativeRewardsPerStake.add(rewardsAdded, "cumulative rewards overflow");
    }

    function claimRewards(address _destination) external {
        uint256 stake = balanceOf[msg.sender];
        if (stake == 0) {
            return;
        }
        uint256 dueRewards = stake.mul(cumulativeRewardsPerStake.sub(claimedRewardsPerStake[msg.sender], "underflow"), "dueRewards overflow");
        if (dueRewards == 0) {
            return;
        }
        claimedRewardsPerStake[msg.sender] = cumulativeRewardsPerStake;
        require(attributes[uint144(uint160(msg.sender) >> 20)] & ACCOUNT_KYC != 0, "please register at app.trusttoken.com");
        require(rewardAsset().transferFrom(address(rewardPool()), _destination, dueRewards));
    }
}
