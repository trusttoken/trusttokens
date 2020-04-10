pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;

import "./ALiquidator.sol";

/**
 * @title Liquidator
 * @dev Implementation of ALiquidator
**/
contract Liquidator is ALiquidator {
    address pool_;
    Registry registry_;
    IERC20 outputToken_;
    IERC20 stakeToken_;
    UniswapV1 outputUniswap_;
    UniswapV1 stakeUniswap_;
    constructor(Registry _registry, IERC20 _outputToken, IERC20 _stakeToken, UniswapV1 _outputUniswap, UniswapV1 _stakeUniswap) public {
        registry_ = _registry;
        outputToken_ = _outputToken;
        stakeToken_ = _stakeToken;
        outputUniswap_ = _outputUniswap;
        stakeUniswap_ = _stakeUniswap;
        initialize();
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }
    function setPool(address _pool) external onlyOwner {
        pool_ = _pool;
    }
    function pool() internal view returns (address) {
        return pool_;
    }
    function outputToken() internal view returns (IERC20) {
        return outputToken_;
    }
    function stakeToken() internal view returns (IERC20) {
        return stakeToken_;
    }
    function registry() internal view returns (Registry) {
        return registry_;
    }
    function outputUniswapV1() internal view returns (UniswapV1) {
        return outputUniswap_;
    }
    function stakeUniswapV1() internal view returns (UniswapV1) {
        return stakeUniswap_;
    }
}
