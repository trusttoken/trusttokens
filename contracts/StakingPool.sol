pragma solidity ^0.5.13;

import "../true-currencies/registry/contracts/Registry.sol";
import "./mocks/MockStakedToken.sol";
import "./SafeMath.sol";


contract StakingPool {
    using SafeMath for uint256;
    mapping (address => uint256) attributes;
    StakingAsset[] stakedTokens; 

    bytes32 constant CAN_STAKE = "canStake";

    uint256 constant ATTRIBUTE_CAN_STAKE         = 0xff00000000000000000000000000000000000000000000000000000000000000;
    uint256 constant ATTRIBUTE_CAN_STAKE_INV     = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant ATTRIBUTE_IS_STAKED         = 0x00ff000000000000000000000000000000000000000000000000000000000000;
    uint256 constant ATTRIBUTE_IS_STAKED_INV     = 0xff00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant ATTRIBUTE_STAKE_ADDRESS     = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;
    uint256 constant ATTRIBUTE_STAKE_ADDRESS_INV = 0xffffffffffffffffffffffff0000000000000000000000000000000000000000;

    uint256 constant PRECISION = 21000;
    uint256 constant FAVOR = 2;
    function registry() internal view returns (Registry);
    function rewardAsset() internal view returns (StakingAsset);
    function favoredAsset() internal view returns (StakingAsset);
    function liquidator() internal view returns (address);
    function uniswapFor(IERC20 asset1, IERC20 asset2) internal view returns (IERC20);

    event StakingOpportunity(IERC20 asset, StakedToken stakedAsset); 

    modifier onlyRegistry {
        require(msg.sender == address(registry()));
        _;
    }

    function syncAttributeValue(address _who, bytes32 _attribute, uint256 _value) external onlyRegistry {
        if (_attribute == CAN_STAKE) {
            if (_value == 0) {
                attributes[_who] &= ATTRIBUTE_CAN_STAKE;
                // TODO determine what should do if we remove stakeability
            } else {
                attributes[_who] |= ATTRIBUTE_CAN_STAKE;
            }
        }
    }

    function stakedAssetForAsset(IERC20 _token) internal view returns (StakedToken) {
        return StakedToken(address(attributes[address(_token)]));
    }

    function createStakingOpportunity(StakingAsset _token) external {
        uint256 flags = attributes[address(_token)];
        if (flags & ATTRIBUTE_CAN_STAKE == 0 || flags & ATTRIBUTE_STAKE_ADDRESS != 0) {
            return;
        }
        stakedTokens.push(_token);
        // XXX
        StakedToken asset = new MockStakedToken(_token, rewardAsset(), registry(), liquidator());
        attributes[address(_token)] |= uint256(address(asset));
        emit StakingOpportunity(_token, asset);
    }

    function award(uint256 _reward) external {
        require(rewardAsset().transferFrom(msg.sender, address(this), _reward));
    }

    function tokenFallback(address /*originalSender*/, uint256 _amount) external {
        IERC20 reward = rewardAsset();
        require(msg.sender == address(reward));
        IERC20 favored = favoredAsset();
        uint256 len = stakedTokens.length;
        StakedToken[] memory assetPools = new StakedToken[](len);
        IERC20[] memory assets = new IERC20[](len);
        uint256[] memory partialValues = new uint256[](len);
        uint256 total = 0;
        for (uint256 i = len; i --> 0;) {
            StakingAsset token = stakedTokens[i];
            assets[i] = token;
            StakedToken stakedToken = stakedAssetForAsset(token);
            assetPools[i] = stakedToken;
            IERC20 uniswap = uniswapFor(reward, token);
            uint256 partialValue = PRECISION * reward.balanceOf(address(uniswap)) / token.balanceOf(address(uniswap));
            if (token == favored) {
                partialValue = partialValue.mul(FAVOR, "overflow");
            }
            partialValues[i] = partialValue;
            total = partialValue.add(total, "");
        }
        for (uint256 i = len; i --> 0;) {
            uint256 share = partialValues[i] * _amount / total;
            total = total.sub(partialValues[i], "underflow");
            _amount -= share;
            assetPools[i].award(share);
        }
    }
}
