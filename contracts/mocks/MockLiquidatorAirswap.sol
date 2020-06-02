pragma solidity 0.5.13;

pragma experimental ABIEncoderV2;

import "../ALiquidatorAirswap.sol";

/**
 * @title Liquidator
 * @dev Implementation of ALiquidator
**/
contract MockLiquidatorAirswap is ALiquidatorAirswap {
    address pool_;
    Registry registry_;
    IERC20 outputToken_;
    IERC20 stakeToken_;
    UniswapV1 outputUniswap_;
    UniswapV1 stakeUniswap_;
    bool initialized;
    constructor(
        address registryAddress,
        address outputTokenAddress,
        address stakeTokenAddress,
        address outputUniswapAddress,
        address stakeUniswapAddress
    ) public {
        registry_ = Registry(registryAddress);
        outputToken_ = IERC20(outputTokenAddress);
        stakeToken_ = IERC20(stakeTokenAddress);
        outputUniswap_ = UniswapV1(outputUniswapAddress);
        stakeUniswap_ = UniswapV1(stakeUniswapAddress);
        owner = msg.sender;
        initialized = false;
        emit OwnershipTransferred(address(0), owner);
    }
    
    function configure() external onlyOwner {
        require(!initialized, "already initialized");
        initialized = true;
        initialize();
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
